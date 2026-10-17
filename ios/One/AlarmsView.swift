import SwiftUI
import SwiftData
import UserNotifications

/// The Alarms tab, modeled on the Alarms tab of Apple's Clock app: big light times with a small AM/PM and a green switch per row.
/// No Edit button or large title (the app's top bar already says "Alarms"); swipe left or long-press a row to delete.
/// Adding is the app-wide + at the bottom right.
/// Alarms are real: each one is an AlarmKit alarm (they ring through Silent and Focus). The tasks and events
/// you marked "Ring as alarm" follow in their own section. Reminders and event alerts live in Apple Reminders / Calendar.
/// Like Clock, the tab has four sections (Alarms · World Clock · Stopwatch · Timer), picked from a quiet switcher under
/// the top bar. The section lives in `HomeView`, so leaving the tab and coming back finds the same one.
/// The kitchen-timer card (`TimerCard`) is the Timer section: one AlarmKit countdown at a time.
struct AlarmsView: View {
    @Binding var section: ClockSection
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: [SortDescriptor(\OneAlarm.hour), SortDescriptor(\OneAlarm.minute)]) private var alarms: [OneAlarm]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @State private var notificationStatus: UNAuthorizationStatus = .authorized
    @State private var editing: OneAlarm?
    @State private var adding = false
    @State private var center = AlarmCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            ClockSectionBar(selection: $section)
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 6)
            Group {
                switch section {
                case .alarms: alarmsList
                case .worldClock: WorldClockView()
                case .stopwatch: StopwatchView()
                case .timer:
                    ScrollView {
                        TimerCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
        .sheet(item: $editing) { AlarmEditor(alarm: $0) }
        .sheet(isPresented: $adding) { AlarmEditor() }
        .task { await center.watch(context: context) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await FirstRun.alarms()
            notificationStatus = await Reminders.shared.authorizationStatus()
            await Ringer.sync(context)
        }
    }

    private var alarmsList: some View {
        List {
            nextAlarmRow
            authorizationBanner
            Section {
                if alarms.isEmpty { emptyState }
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm, state: center.state(of: alarm)) { editing = alarm }
                        .contextMenu {
                            Button { editing = alarm } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { delete(alarm) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                .onDelete { offsets in offsets.map { alarms[$0] }.forEach(delete) }
            }

            if !ringing.isEmpty {
                Section {
                    ForEach(ringing) { item in
                        ItemAlarmRow(item: item)
                    }
                } header: { SectionTitle("From reminders and events") }
            }
            if notificationStatus != .authorized && notificationStatus != .provisional {
                notificationsRow
            }
        }
        .listStyle(.plain)
    }

    // MARK: Next alarm

    /// "Next alarm in 7 hr 12 min" while an alarm is on. The "Alarms" title is the app's top bar, so it isn't repeated here.
    @ViewBuilder private var nextAlarmRow: some View {
        if let hint = nextAlarmHint {
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("alarms.next")
                .frame(maxWidth: .infinity, alignment: .leading)
                .plainRow(top: 4, bottom: 8)
        }
    }

    // MARK: Data

    fileprivate struct Ringing: Identifiable {
        let id: String
        let title: String
        let fire: Date
    }

    /// Items that will ring as an alarm, soonest first.
    private var ringing: [Ringing] {
        let now = Date.now
        let t = tasks.filter { $0.ringsAsAlarm && !$0.isDone }.compactMap { task in
            task.reminderDate.map { Ringing(id: "t\(task.persistentModelID.hashValue)", title: task.title, fire: $0) }
        }
        let e = events.filter(\.ringsAsAlarm).compactMap { event in
            event.reminderDate.map { Ringing(id: "e\(event.persistentModelID.hashValue)", title: event.title, fire: $0) }
        }
        return (t + e).filter { $0.fire > now }.sorted { $0.fire < $1.fire }
    }

    /// "Next alarm in 7 hr 12 min" while at least one alarm is on.
    private var nextAlarmHint: String? {
        let now = Date.now
        return AlarmPlan.nextAlarmText(rings: alarms.compactMap { $0.nextRing(now: now) }, now: now)
    }

    private func delete(_ alarm: OneAlarm) {
        let backup = alarm.copy()
        withAnimation(.snappy) { context.delete(alarm) }
        Task { await Ringer.sync(context) }
        toast?.show("Deleted alarm \(backup.timeToday.formatted(date: .omitted, time: .shortened))") {
            withAnimation(.snappy) { context.insert(backup) }
            try? context.save()
            Task { await Ringer.sync(context) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "alarm").font(.largeTitle).foregroundStyle(.secondary)
            Text("No Alarms").font(.title3.weight(.semibold))
            Text("Tap + to add an alarm. Alarms ring through Silent and Focus.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alarms.empty")
        .plainRow(top: 0, bottom: 0)
    }

    // MARK: Permission

    /// Apple-style wording for AlarmKit's three states. Notifications for reminders are a separate card at the bottom.
    @ViewBuilder private var authorizationBanner: some View {
        switch center.authorization {
        case .authorized:
            EmptyView()
        case .notDetermined:
            banner(symbol: "alarm", title: "Allow Alarms",
                   text: "Allow Today to schedule alarms that ring even on Silent or in a Focus.",
                   button: "Allow Alarms") { Task { await center.requestAuthorization() } }
        case .denied:
            banner(symbol: "alarm.slash", title: "Alarms Are Off",
                   text: "Allow alarms for Today in Settings so they can ring.",
                   button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .unavailable:
            banner(symbol: "alarm.slash", title: "Update iOS to Ring Alarms",
                   text: "Ringing alarms need iOS 26 or later.", button: nil) {}
        }
    }

    private func banner(symbol: String, title: String, text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            if let button {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("alarms.permission")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .plainRow(top: 4, bottom: 8)
    }

    private var notificationsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications Are Off", systemImage: "bell.slash").font(.headline)
            Text(notificationStatus == .denied
                 ? "Notifications are turned off for Today. Turn them on in Settings to get reminded when a reminder or event starts."
                 : "Allow notifications so Today can remind you when a reminder or event starts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(notificationStatus == .denied ? "Open Settings" : "Turn On Notifications") {
                if notificationStatus == .denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } else {
                    Task {
                        await Reminders.shared.requestPermission()
                        notificationStatus = await Reminders.shared.authorizationStatus()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .plainRow(top: 16, bottom: 8)
    }
}

private extension View {
    /// A row with no separator and no background, for text and cards between Clock's sections.
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
    }
}

/// The section switcher: four words, the chosen one on a soft gray capsule. Lighter than the tab pills above it,
/// so it reads as part of the page, not a second tab bar.
struct ClockSectionBar: View {
    @Binding var selection: ClockSection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(ClockSection.allCases) { item in
                let selected = item == selection
                Button {
                    withAnimation(.snappy) { selection = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected { Capsule().fill(Color(.secondarySystemFill)) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("clock.section." + item.rawValue)
            }
        }
    }
}

/// Section header as Clock draws it: bold, primary, not capitalized.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color(.label))
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A task or event that rings as an alarm: read-only, it is edited where it lives.
private struct ItemAlarmRow: View {
    let item: AlarmsView.Ringing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text("Rings " + DayLabel.withTime(item.fire))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "alarm").foregroundStyle(Color.accentColor)
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}
