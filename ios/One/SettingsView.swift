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
    @AppStorage(SettingsKey.travelTime) private var travelTime = true

    @State private var calendarOn = CalendarSync.shared.isOn
    @State private var remindersOn = RemindersSync.shared.isConnected
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showsCalendars = false
    @State private var askingFirst = false
    @State private var askingSecond = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $calendarOn) { Label("Apple Calendar", systemImage: "calendar") }
                    Toggle(isOn: $remindersOn) { Label("Apple Reminders", systemImage: "checklist") }
                    Button { showsCalendars = true } label: {
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
                    Toggle("Show alarms in the day", isOn: $showAlarms)
                    Toggle("Scroll to now when Today opens", isOn: $jumpToNow)
                    Toggle("Travel time", isOn: $travelTime)
                } header: {
                    Text("Today")
                } footer: {
                    Text("Travel time shows how long the drive takes to upcoming events with a location today and tomorrow, and when to leave. To work it out, your current location and the event's address go to Apple Maps (MapKit) only; nothing else leaves your iPhone.")
                }

                Section {
                    Toggle("Archive finished chats", isOn: $autoArchiveChats)
                } header: {
                    Text("Chats")
                } footer: {
                    Text("A chat moves to Archived a week after its last message, or an hour after everything it added is done. Archived chats stay in the sidebar under Archived.")
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
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
                Text("This deletes the reminders, events, alarms and lists Today keeps on this device. It can't be undone.")
            }
            .sheet(isPresented: $showsCalendars) { CalendarsSheet() }
            .sheet(isPresented: $askingSecond) {
                DeleteDataConfirmation {
                    DataReset.run(context)
                    dismiss()
                }
            }
        }
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
        try? context.save()
    }
}
