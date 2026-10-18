import SwiftUI
import SwiftData
import UserNotifications

/// Keys for the choices in Settings (read by the screens they affect).
enum SettingsKey {
    static let showOverdue = "today.setting.showOverdue"
    static let showAlarms = "today.setting.showAlarmsInToday"
    static let jumpToNow = "today.setting.jumpToNow"
    static let autoArchiveChats = "today.setting.autoArchiveChats"
    static let travelTime = "today.setting.travelTime"
    static let healthSummary = "today.setting.healthSummary"
}

/// Settings is its own screen (opened from the sidebar). Each screen's options live here, not in the sidebar;
/// the destructive "Delete All Data" is the last row and needs two confirmations.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.showOverdue) private var showOverdue = true
    @AppStorage(SettingsKey.showAlarms) private var showAlarms = true
    @AppStorage(SettingsKey.jumpToNow) private var jumpToNow = true
    @AppStorage(SettingsKey.autoArchiveChats) private var autoArchiveChats = true
    @AppStorage(SmartListLayout.orderKey) private var smartOrder = ""
    @AppStorage(SmartListLayout.hiddenKey) private var smartHidden = ""
    @AppStorage(SettingsKey.travelTime) private var travelTime = true
    @AppStorage(SettingsKey.healthSummary) private var healthSummary = true

    @State private var calendarOn = CalendarSync.shared.isOn
    @State private var remindersOn = RemindersSync.shared.isConnected
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showsCalendars = false
    @State private var askingFirst = false
    @State private var askingSecond = false
    @AppStorage(ActivitySettings.pausedKey) private var activityPaused = false

    var body: some View {
        NavigationStack {
            Form {
                AppearanceSection()

                Section {
                    Toggle(isOn: $calendarOn) { Label("Apple Calendar", systemImage: "calendar") }
                    Toggle(isOn: $remindersOn) { Label("Apple Reminders", systemImage: "checklist") }
                    Button { PerformanceTrace.shared.beginPage("settings.calendars"); showsCalendars = true } label: {
                        HStack {
                            Label("Calendars", systemImage: "calendar.badge.checkmark")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose which calendars show in Today")
                    statusRow(title: "Alarms", icon: "alarm",
                              value: Ringer.isAvailable ? (Ringer.isDenied ? "Not allowed" : "Allowed") : "Needs iOS 26",
                              showsSettings: Ringer.isDenied)
                    statusRow(title: "Notifications", icon: "bell.badge",
                              value: notificationStatus == .authorized || notificationStatus == .provisional ? "Allowed"
                                  : (notificationStatus == .denied ? "Not allowed" : "Off"),
                              showsSettings: notificationStatus == .denied,
                              turnOn: notificationStatus == .notDetermined ? {
                                  Task {
                                      await Reminders.shared.requestPermission()
                                      notificationStatus = await Reminders.shared.authorizationStatus()
                                  }
                              } : nil)
                } header: {
                    Text("Apple Calendar, Reminders and Alarms")
                } footer: {
                    Text("Today shows your Apple Calendar events and Apple Reminders next to your alarms. Your data stays in Apple's apps; Today does not send it anywhere.")
                }

                Section {
                    Toggle("Show overdue reminders", isOn: $showOverdue)
                    Toggle("Show alarms in Today and Calendar", isOn: $showAlarms)
                    Toggle("Scroll to now when Today opens", isOn: $jumpToNow)
                    TodayTimelineSettings()
                    explainedToggle("Travel time", isOn: $travelTime,
                                    caption: "Shows the drive time and when to leave for events with a location today and tomorrow. Your location and the event's address go to Apple Maps only; nothing else leaves your iPhone.")
                    explainedToggle("Health summary", isOn: $healthSummary,
                                    caption: "Shows one line from Apple Health on Today: your steps and last night's sleep, or the first metrics you chose. Today only reads them.")
                    HealthMetricsLink()
                } header: {
                    Text("Today")
                }

                CalendarSettingsSection()

                RemindersSettingsSection()

                smartListsSection

                AlarmsSettingsSection()

                Section {
                    NavigationLink {
                        YearHolidaysSettingsView().performanceDestination("settings.holidays")
                    } label: {
                        Label("Holidays in Year", systemImage: "flag")
                    }
                    .accessibilityIdentifier("settings.yearHolidays")
                    .performanceNavigationAction("settings.holidays")
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Which holidays and festivals the Year view marks.")
                }

                Section {
                    AutomaticChangesToggle()
                    NavigationLink("Scope and duration") {
                        AutomaticChangesView().performanceDestination("settings.automaticChanges")
                    }
                    .accessibilityIdentifier("settings.automaticChanges")
                    .performanceNavigationAction("settings.automaticChanges")
                    AskSuggestionsSettingRow()
                    explainedToggle("Archive finished chats", isOn: $autoArchiveChats,
                                    caption: "A chat moves to Archived a week after its last message, or an hour after everything it added is done. Archived chats stay in the sidebar under Archived.")
                } header: {
                    Text("AI")
                } footer: {
                    Text("Turn on for 7 days to plan untimed reminders due today into free time. Only Today’s own planned times change. Every automatic change has Undo and an Activity entry.")
                }

                Section {
                    NavigationLink {
                        ActivityDataView().performanceDestination("settings.activityData")
                    } label: {
                        HStack {
                            Label("Activity data", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text(activityPaused ? "Paused" : "On").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.activityData")
                    .performanceNavigationAction("settings.activityData")
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Today keeps a record of changes and AI decisions, only on this iPhone. See what is recorded, pause it, export it or clear it.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                } header: {
                    Text("About")
                }

                // Last, on purpose: nothing destructive sits anywhere else in the app.
                Section {
                    Button(role: .destructive) { askingFirst = true } label: {
                        Text("Delete All Data…")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Clears what Today stores on this device. Your Apple Calendar and Apple Reminders are not changed.")
                }
            }
            .performanceDestination("settings")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                Ledger.flush(context)
                notificationStatus = await Reminders.shared.authorizationStatus()
            }
            .onChange(of: calendarOn) { _, on in
                guard on != CalendarSync.shared.isOn else { return }
                Task {
                    await CalendarSync.shared.setEnabled(on)
                    calendarOn = CalendarSync.shared.isOn   // stays off if access was refused
                }
            }
            .onChange(of: travelTime) { _, _ in
                WidgetFeed.rewriteFromStore()   // add or drop "Leave by" on the widget
            }
            .onChange(of: remindersOn) { _, on in
                guard on != RemindersSync.shared.isConnected else { return }
                Task {
                    if on { await RemindersSync.shared.connect() } else { RemindersSync.shared.disconnect() }
                    remindersOn = RemindersSync.shared.isConnected
                }
            }
            .confirmationDialog("Delete all data stored in Today?", isPresented: $askingFirst, titleVisibility: .visible) {
                Button("Continue…", role: .destructive) { askingSecond = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the reminders, events, alarms, lists and Activity Today keeps on this device. It can't be undone.")
            }
            .sheet(isPresented: $showsCalendars) { CalendarsSheet().performanceDestination("settings.calendars") }
            .sheet(isPresented: $askingSecond) {
                DeleteDataConfirmation {
                    DataReset.run(context)
                    dismiss()
                }
            }
        }
    }

    /// Which smart lists show at the top of Reminders: a switch per list, press, hold and drag to reorder (no Edit mode).
    private var smartListsSection: some View {
        let layout = SmartListLayout(order: smartOrder, hidden: smartHidden)
        return Section {
            ForEach(layout.order) { smart in
                Toggle(isOn: Binding(
                    get: { !layout.hidden.contains(smart) },
                    set: { shown in
                        var l = SmartListLayout(order: smartOrder, hidden: smartHidden)
                        if shown { l.hidden.remove(smart) } else { l.hidden.insert(smart) }
                        smartHidden = l.hiddenString
                    }
                )) {
                    HStack(spacing: 12) {
                        ListGlyph(color: smart.color, symbol: smart.symbol, size: 28)
                        Text(smart.title)
                    }
                }
                .accessibilityIdentifier("smartToggle.\(smart.rawValue)")
            }
            .onMove { from, to in
                var l = SmartListLayout(order: smartOrder, hidden: smartHidden)
                l.order.move(fromOffsets: from, toOffset: to)
                smartOrder = l.orderString
            }
        } header: {
            Text("Reminders Smart Lists")
        } footer: {
            Text("Shown at the top of Reminders. Press and hold one, then drag, to change the order.")
        }
    }

    /// A switch with its own short explanation right under it (a Section footer can only describe the whole group).
    private func explainedToggle(_ title: String, isOn: Binding<Bool>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func statusRow(title: String, icon: String, value: String, showsSettings: Bool, turnOn: (() -> Void)? = nil) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let turnOn {
                Button("Turn On", action: turnOn).font(.subheadline)
            } else if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline)
            } else {
                Text(value).foregroundStyle(.secondary)
            }
        }
    }

    private static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Second confirmation: the user must type DELETE before the button works.
struct DeleteDataConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    var onConfirm: () -> Void
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Everything Today stores on this device will be deleted: reminders, events, alarms and lists. Apple Calendar and Apple Reminders are not touched.")
                    TextField("Type DELETE to confirm", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                }
                Section {
                    Button("Delete All Data", role: .destructive) {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).uppercased() != "DELETE")
                }
            }
            .navigationTitle("Are you sure?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

/// Clears Today's own data. Never touches Apple Calendar or Apple Reminders.
@MainActor
enum DataReset {
    static func run(_ context: ModelContext) {
        // Forget the link first so a local wipe is never mirrored to Apple Reminders.
        RemindersSync.shared.forgetLink()
        try? context.delete(model: OneTask.self)
        try? context.delete(model: OneEvent.self)
        try? context.delete(model: OneAlarm.self)
        try? context.delete(model: OneList.self)
        try? context.delete(model: Habit.self)
        try? context.delete(model: ChatThread.self)
        try? context.delete(model: AIGrant.self)
        // Clear pending shares before forgetting receipts, or an ack failure could resurrect deleted reminders.
        // If the inbox is unreadable, retain only the opaque receipts until it can be safely cleared.
        if let pending = try? ShareInbox.read(),
           pending.isEmpty || ShareInbox.acknowledge(Set(pending.map(\.id))) {
            try? context.delete(model: ShareImportReceipt.self)
        }
        Ledger.clearAll(context)
        try? context.save()
    }
}

/// Both Settings entry points edit the existing bounded grant, without a second preference.
private struct AutomaticChangesToggle: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIGrant.expires, order: .reverse) private var grants: [AIGrant]
    @AppStorage(ActivitySettings.pausedKey) private var paused = false
    @AppStorage(ActivitySettings.tierKey(.changes)) private var recordsChanges = true
    @State private var saveFailed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let active = Grants.active(grants.compactMap(\.info), scope: .planFreeTime, now: .now)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { active != nil }, set: { enabled in
                    do {
                        try GrantStore.setEnabled(enabled, scope: .planFreeTime, context: context)
                    } catch {
                        saveFailed = true
                    }
                })) {
                    Label("Automatic changes", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.automaticChanges.toggle")
                if let active {
                    Text("Until " + active.expires.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("grant.expiry")
                } else {
                    Text("Off. Turn on for 7 days.").font(.footnote).foregroundStyle(.secondary)
                }
                if paused || !recordsChanges {
                    Text("Automatic changes wait while Activity recording is paused or Changes is off.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("grant.recordingWarning")
                }
            }
        }
        .alert("Couldn’t save automatic changes", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again.")
        }
    }
}

/// Settings → AI → Automatic changes: the same seven-day scope as the plan card, with its end date and Revoke.
/// What no grant can ever cover is listed too (see `AutonomyPolicy`).
struct AutomaticChangesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIGrant.expires, order: .reverse) private var grants: [AIGrant]

    private var active: [AIGrant] { grants.filter { $0.info?.isActive(at: .now) ?? false } }

    var body: some View {
        Form {
            Section {
                AutomaticChangesToggle()
            } footer: {
                Text("Turn on for 7 days. Only Today’s own planned times change; every automatic change has Undo and an Activity entry.")
            }
            Section {
                if active.isEmpty {
                    Text("None. AI changes wait for your tap.").foregroundStyle(.secondary)
                }
                ForEach(active) { g in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GrantScope(rawValue: g.scope)?.title ?? g.scope)
                            Text("Until " + g.expires.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke", role: .destructive) {
                            withAnimation { GrantStore.revoke(g, context: context) }
                            try? context.save()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("grant.revoke")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("grant.row")
                }
            } header: {
                Text("Allowed")
            } footer: {
                Text(GrantScope.planFreeTime.detail + " Overdue reminders, ones that ring as alarms, and ones you placed yourself still ask.")
            }
            Section {
                ForEach(Self.never, id: \.self) { Label($0, systemImage: "lock").font(.subheadline) }
            } header: {
                Text("Always asks")
            } footer: {
                Text("No grant covers these. Each one is a card you apply with a tap.")
            }
        }
        .navigationTitle("Automatic changes")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let never = [
        "Writing Apple Calendar or Apple Reminders",
        "Moving or changing events",
        "Changing deadlines",
        "Deleting anything",
        "Anything that notifies other people",
    ]
}
