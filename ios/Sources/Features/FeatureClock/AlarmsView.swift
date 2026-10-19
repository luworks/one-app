#if os(iOS)
import One
import TodayCore
import TodayPlatform
import TodayDesignSystem
import SwiftUI
import SwiftData
import UserNotifications

/// The Alarms section of the Clock tab, modeled on the Alarms tab of Apple's Clock app: big light times with a small AM/PM and a green switch per row.
/// No Edit button or large title (the tab pills on top already say "Clock"); swipe left or long-press a row to delete.
/// Adding is the app-wide + at the bottom right.
/// Alarms are real: each one is an AlarmKit alarm (they ring through Silent and Focus). The tasks and events
/// you marked "Ring as alarm" follow in their own section. Reminders and event alerts live in Apple Reminders / Calendar.
/// Like Clock, the tab has four sections (Alarms · World Clock · Stopwatch · Timer), picked from a quiet switcher under
/// the top bar. The section lives in `HomeView`, so leaving the tab and coming back finds the same one.
/// The Timer section (`TimerSection`) is a copy of Apple's Timers screen: wheel picker, Recents, running timers (AlarmKit countdowns).
package struct AlarmsView: View {
    @Binding var section: ClockSection
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\OneAlarm.hour), SortDescriptor(\OneAlarm.minute)]) private var alarms: [OneAlarm]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @State private var notificationStatus: UNAuthorizationStatus = .authorized
    @State private var editing: OneAlarm?
    @State private var adding = false
    private let center: any AlarmService
    private let timers: any TimerService
    @Environment(PlannerActions.self) private var actions
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(UndoToast.self) private var toast
    private let notifications: any NotificationService
    private let soundPreview: any SoundPreviewing
    private let worldClock: WorldClockStore
    private let stopwatch: StopwatchModel
    private let now: () -> Date
    private let defaults: UserDefaults
    private let arguments: [String]
    private let onAlarmCreated: (OneAlarm, ModelContext) -> Void
    private let showUndo: (String, @escaping () -> Void) -> Void

    package init(section: Binding<ClockSection>, alarms: any AlarmService, timers: any TimerService,
                 notifications: any NotificationService, soundPreview: any SoundPreviewing,
                 worldClock: WorldClockStore, stopwatch: StopwatchModel, now: @escaping () -> Date,
                 defaults: UserDefaults, arguments: [String],
                 onAlarmCreated: @escaping (OneAlarm, ModelContext) -> Void,
                 showUndo: @escaping (String, @escaping () -> Void) -> Void) {
        _section = section
        center = alarms
        self.timers = timers
        self.notifications = notifications
        self.soundPreview = soundPreview
        self.worldClock = worldClock
        self.stopwatch = stopwatch
        self.now = now
        self.defaults = defaults
        self.arguments = arguments
        self.onAlarmCreated = onAlarmCreated
        self.showUndo = showUndo
    }

    package var body: some View {
        VStack(spacing: 0) {
            ClockSectionBar(selection: $section.performanceAction { "clock.\($0.rawValue)" })
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 6)
            Group {
                switch section {
                case .alarms: alarmsList
                case .worldClock: WorldClockView(store: worldClock, now: now, showUndo: showUndo)
                case .stopwatch: StopwatchView(model: stopwatch)
                case .timer: TimerSection(controller: timers, alarms: center, soundPreview: soundPreview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .performanceDestination("clock.\(section.rawValue)")
        }
        .background(Color(.systemBackground))
        .sheet(item: $editing) { AlarmEditor(alarm: $0, alarms: center, soundPreview: soundPreview, runtime: presentation.runtime, defaults: defaults, onCreated: onAlarmCreated) }
        .sheet(isPresented: $adding) { AlarmEditor(alarms: center, soundPreview: soundPreview, runtime: presentation.runtime, defaults: defaults, onCreated: onAlarmCreated) }
        .task { await center.watch(context: context) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await FirstRun.alarms(center, notifications: notifications, arguments: arguments)
            notificationStatus = await notifications.authorizationStatus()
            await center.sync(context)
        }
    }

    private var alarmsList: some View {
        List {
            nextAlarmRow
            permissionRow
            Section {
                if alarms.isEmpty { emptyState }
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm, state: center.state(of: alarm), alarms: center) { editing = alarm }
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
        let now = presentation.now
        let t = tasks.filter { $0.ringsAsAlarm && !$0.isDone }.compactMap { task in
            plannerReminderDate(task, runtime: presentation.runtime).map { Ringing(id: "t\(task.persistentModelID.hashValue)", title: task.title, fire: $0) }
        }
        let e = events.filter(\.ringsAsAlarm).compactMap { event in
            plannerReminderDate(event, runtime: presentation.runtime).map { Ringing(id: "e\(event.persistentModelID.hashValue)", title: event.title, fire: $0) }
        }
        return (t + e).filter { $0.fire > now }.sorted { $0.fire < $1.fire }
    }

    /// "Next alarm in 7 hr 12 min" while at least one alarm is on.
    private var nextAlarmHint: String? {
        let now = presentation.now
        return AlarmPlan.nextAlarmText(rings: alarms.compactMap { $0.isOn ? AlarmPlan.nextRing(hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays, switchedOn: $0.createdAt, now: now, calendar: presentation.calendar) : nil }, now: now)
    }

    private func delete(_ alarm: OneAlarm) {
        actions.delete(alarm, context: context, toast: toast)
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

    /// What is missing, in the words of one slim row: "Alarms and notifications are off". AlarmKit can be undecided,
    /// denied or unavailable (older iOS); notifications can be undecided or denied. Nothing shows when both are allowed.
    private var permissionNotice: (text: String, button: String?)? {
        let alarmsUndecided = center.authorization == .notDetermined
        let alarmsOff = center.authorization == .denied || alarmsUndecided
        let notificationsUndecided = notificationStatus == .notDetermined
        let notificationsOff = notificationStatus == .denied || notificationsUndecided
        if center.authorization == .unavailable && !notificationsOff { return ("Update iOS to ring alarms", nil) }
        let text: String
        switch (alarmsOff, notificationsOff) {
        case (true, true): text = "Alarms and notifications are off"
        case (true, false): text = "Alarms are off"
        case (false, true): text = "Notifications are off"
        case (false, false): return nil
        }
        // Undecided: the button asks. Denied: only Settings can change it.
        return (text, alarmsUndecided || notificationsUndecided ? "Allow" : "Open")
    }

    @ViewBuilder private var permissionRow: some View {
        if let notice = permissionNotice {
            HStack(spacing: 10) {
                Image(systemName: "bell.slash").foregroundStyle(.secondary)
                Text(notice.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let button = notice.button {
                    Button(button) { resolvePermission() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .accessibilityIdentifier("alarms.permission")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("alarms.permissionRow")
            .plainRow(top: 0, bottom: 8)
        }
    }

    /// Asks for what is still undecided; when everything is decided (denied), opens Settings.
    private func resolvePermission() {
        let alarmsUndecided = center.authorization == .notDetermined
        let notificationsUndecided = notificationStatus == .notDetermined
        guard alarmsUndecided || notificationsUndecided else {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }
        Task {
            if alarmsUndecided { await center.requestAuthorization() }
            if notificationsUndecided {
                await notifications.requestPermission()
                notificationStatus = await notifications.authorizationStatus()
            }
        }
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

/// The section switcher: the same pills as the Calendar tab's Week / Month / Year row (`PillSwitcher`).
struct ClockSectionBar: View {
    @Binding var selection: ClockSection

    var body: some View {
        PillSwitcher(items: ClockSection.allCases, selection: $selection,
                     title: { $0.title }, identifier: { "clock.section." + $0.rawValue })
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
    @Environment(PlannerPresentation.self) private var presentation
    let item: AlarmsView.Ringing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text("Rings " + plannerDayLabel(item.fire, runtime: presentation.runtime))
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
#endif
