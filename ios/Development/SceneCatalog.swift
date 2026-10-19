#if DEBUG
import SwiftUI
import SwiftData
import TodayCore
import TodayScenes
import TodayTestSupport
import FeatureClock
import FeatureHealth
import One
import TodayData
import TodayPlatform
import TodayDesignSystem
import TodayPlannerUI
import FeatureToday
import FeatureCalendar
import FeatureReminders
import FeatureAsk
import FeatureSettings
import FeatureActivity
import FeatureSearch

/// Root assembly supplies the legacy service sandbox. A fresh ModelContainer alone does not
/// isolate ActivityCenter, EventKit, AlarmKit, widget writes or static UserDefaults readers.
@MainActor
struct SceneCatalogRuntime {
    var prepareLegacyEnvironment: ((SceneConfiguration, ModelContainer, UserDefaults) throws -> Void)?
    /// Called only after prepareLegacyEnvironment succeeds; must return sandboxed concrete adapters.
    var makeServices: ((SceneConfiguration, ModelContainer, UserDefaults) throws -> SceneCatalogServices)?
    var disposeLegacyEnvironment: (() -> Void)?
    /// Optional assembly overrides; otherwise the cards call the real AskNativeActions.
    var applyChange: ((PendingChange, ModelContext, UndoToast) -> Void)?
    var applyAlways: (([(task: OneTask, start: Date)], ModelContext, UndoToast) -> Void)?
    var applyTidy: (([TidyRow], ModelContext, UndoToast) -> Void)?
    static let isolatedFeatures = SceneCatalogRuntime()
}

/// Concrete production constructor dependencies. Root owns their system-write boundaries.
@MainActor
struct SceneCatalogServices {
    let calendar: CalendarSync
    let reminders: RemindersSync
    let notifications: Reminders
    let alarms: AlarmCenter
    let timers: TimerController
    let activity: ActivityCenter
    let diagnostics: LocalDiagnostics
    let requestReminderAccess: @MainActor () async -> Void
    let activitySummary: @MainActor () -> ActivityCenter.Summary
    let clearActivity: @MainActor () -> Void
    let exportActivity: @MainActor (ActivityExportFormat) async throws -> URL
    let shareDiagnostics: @MainActor (URL) -> AnyView
    let reset: @MainActor (ModelContext) -> Void
}

@MainActor
final class SceneSession {
    let identity = UUID()
    let configuration: SceneConfiguration
    let container: ModelContainer
    let defaults: UserDefaults
    let health: HealthModel
    let healthLine: HealthLineModel?
    private let preparedServices: SceneCatalogServices?
    private var disposed = false

    var services: SceneCatalogServices {
        guard let preparedServices else { preconditionFailure("Scene was not prepared for legacy services.") }
        return preparedServices
    }
    let world: WorldClockStore
    let stopwatch: StopwatchModel
    let toast = UndoToast()
    let runtime: SceneCatalogRuntime
    private let suiteName: String

    init(configuration: SceneConfiguration, datasetURL: URL? = SceneSession.bundledDataset,
         runtime: SceneCatalogRuntime = .isolatedFeatures) throws {
        self.configuration = configuration
        self.runtime = runtime
        let descriptor = SceneRegistry.descriptor(for: configuration.scene)
        if let blocker = descriptor.integrationBlocker {
            throw SceneConfigurationError.integrationRequired(configuration.scene, blocker)
        }
        // A separate disposable domain per session also isolates simultaneous previews of the same scene.
        suiteName = "today.workbench.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw SceneSessionError.defaults }
        self.defaults = defaults
        var completed = false
        let disposableSuite = suiteName
        defer { if !completed { defaults.removePersistentDomain(forName: disposableSuite) } }
        container = try ModelContainer(
            for: OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self,
            ChatThread.self, LedgerEntry.self, AIGrant.self, ShareImportReceipt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        if descriptor.capabilities.contains(.legacyEnvironment) {
            guard let prepare = runtime.prepareLegacyEnvironment, let makeServices = runtime.makeServices,
                  runtime.disposeLegacyEnvironment != nil else {
                throw SceneConfigurationError.integrationRequired(configuration.scene,
                    "Root must supply prepareLegacyEnvironment, makeServices and disposeLegacyEnvironment for a real sandbox.")
            }
            // No concrete singleton or view may be constructed before this gate.
            do {
                try prepare(configuration, container, defaults)
                preparedServices = try makeServices(configuration, container, defaults)
            } catch {
                runtime.disposeLegacyEnvironment?()
                throw error
            }
        } else { preparedServices = nil }
        defer {
            if !completed, descriptor.capabilities.contains(.legacyEnvironment) {
                runtime.disposeLegacyEnvironment?()
            }
        }
        if (configuration.scenario != .empty || configuration.scene == .remindersList),
           descriptor.capabilities.contains(.inMemoryModels) || Self.needsModelFixture(configuration.scene) {
            guard let datasetURL else { throw SceneSessionError.missingDataset }
            // The existing loader accepts a clock/calendar. SampleData is deliberately avoided because
            // insertIfNeeded writes UserDefaults.standard and uses Date.now.
            try TestDataset.load(path: datasetURL.path, into: container.mainContext,
                                 now: configuration.now, calendar: configuration.calendar)
            try Self.normalize(container.mainContext, configuration: configuration)
            if configuration.scenario == .dense {
                // Reuse the same versioned dataset, offset by minutes to exercise actual overlap/layout.
                for offset in 1...5 {
                    try TestDataset.load(path: datasetURL.path, into: container.mainContext,
                                         now: configuration.now.addingTimeInterval(Double(offset) * 60),
                                         calendar: configuration.calendar)
                }
                try Self.normalize(container.mainContext, configuration: configuration)
            }
        }
        if configuration.scenario == .empty, configuration.scene == .remindersList {
            try container.mainContext.delete(model: OneTask.self)
            try container.mainContext.delete(model: OneEvent.self)
            try container.mainContext.delete(model: OneAlarm.self)
            try container.mainContext.delete(model: ChatThread.self)
            try container.mainContext.save()
        }
        let selection = HealthSelectionStore(defaults: defaults, arguments: [])
        let baseHealth = SceneHealthSource(configuration: configuration)
        let source: any HealthSource = configuration.scenario == .error
            ? ScriptedHealthSource(base: baseHealth, stalledSeries: Set(HealthMetric.defaults)) : baseHealth
        health = HealthModel(source: source, store: selection, timeout: configuration.scenario == .error ? 0.05 : HealthTimeout.seconds)
        healthLine = preparedServices == nil ? nil : HealthLineModel(source: source)
        let cities = CityDatabase.shared
        world = WorldClockStore(database: cities, defaults: defaults,
                                homeZoneIdentifier: configuration.timeZoneIdentifier, arguments: [])
        if configuration.scenario != .empty {
            for key in ["Europe/London", "Asia/Shanghai", "America/New_York"] {
                if let city = cities.city(forKey: key) { world.add(city) }
            }
            if configuration.scenario == .dense {
                for city in cities.cities.prefix(12) { world.add(city) }
            }
        }
        var stopwatchArguments = ["-uiTesting"]
        if configuration.scenario != .empty {
            stopwatchArguments += ["-uiTestingStopwatch", "5.75"]
            if configuration.scenario == .dense {
                stopwatchArguments += ["-uiTestingStopwatchLaps", "4.2,6.5,5.1,8.2,3.3,6.8,4.1,9.2"]
            }
        }
        let now = configuration.now
        stopwatch = StopwatchModel(defaults: defaults, now: { now }, arguments: stopwatchArguments)
        completed = true
    }

    /// Bundle the existing fixture in Mock/Workbench; source-path fallback supports local previews only.
    static var bundledDataset: URL? {
        if let url = Bundle.main.url(forResource: "today-dataset", withExtension: "json") { return url }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("tests/fixtures/today-dataset.json")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        if preparedServices != nil { runtime.disposeLegacyEnvironment?() }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func needsModelFixture(_ id: TodaySceneID) -> Bool {
        switch id {
        case .clockAlarms, .reminderEditor, .reminderListEditor, .alarmEditor, .eventEditor,
             .ask, .askPlan, .askChange, .askTidy: true
        default: false
        }
    }

    private static func normalize(_ context: ModelContext, configuration: SceneConfiguration) throws {
        let tasks = try context.fetch(FetchDescriptor<OneTask>(sortBy: [SortDescriptor(\.title)]))
        for (index, task) in tasks.enumerated() {
            task.createdAt = configuration.now.addingTimeInterval(-Double(index))
            if task.isDone { task.doneAt = configuration.now.addingTimeInterval(-60) }
        }
        for list in try context.fetch(FetchDescriptor<OneList>()) { list.createdAt = configuration.now }
        for (index, alarm) in try context.fetch(FetchDescriptor<OneAlarm>(sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute)])).enumerated() {
            alarm.createdAt = configuration.now
            alarm.alarmKitID = configuration.uuid(at: UInt64(index))
        }
        for (index, chat) in try context.fetch(FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.title)])).enumerated() {
            chat.id = configuration.uuid(at: UInt64(index + 100))
        }
        try context.save()
    }
}

enum SceneSessionError: Error, CustomStringConvertible {
    case defaults, missingDataset
    var description: String {
        switch self {
        case .defaults: "Could not create isolated Workbench defaults."
        case .missingDataset: "Bundle tests/fixtures/today-dataset.json in the development target."
        }
    }
}

private struct SceneHealthSource: HealthSource {
    let configuration: SceneConfiguration
    var isAvailable: Bool { configuration.scenario != .unavailable }
    var isSample: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries] {
        Dictionary(uniqueKeysWithValues: metrics.map {
            ($0, configuration.scenario == .empty ? .empty :
                HealthSampleSeries.series(for: $0, now: configuration.now, calendar: configuration.calendar))
        })
    }
    func preferredUnits() async -> HealthUnits? { HealthUnits(locale: Locale(identifier: configuration.localeIdentifier)) }
}

/// The single typed native factory used by Workbench, #Preview and screenshot entry points.
/// Session creation is throwing: unsupported combinations never turn into a plausible default screen.
@MainActor
struct SceneCatalog: View {
    let session: SceneSession
    @State private var day: Date
    @State private var mode: CalendarView.Mode
    @State private var clock: ClockSection = .alarms
    @State private var path: [ReminderTarget] = []
    @State private var pushed = false
    @State private var shownMetrics: Set<HealthMetric> = Set(HealthMetric.defaults)
    @State private var sound = ""
    @State private var opened: OpenedEntry?
    @State private var afterEditor: (() -> Void)?
    @State private var showsTimer = false
    @State private var showsDay = false

    init(session: SceneSession) {
        self.session = session
        _day = State(initialValue: session.configuration.now)
        let id = session.configuration.scene
        _mode = State(initialValue: id == .calendarYear ? .year : id == .calendarMonth ? .month : .week)
    }

    var body: some View {
        content
            .modelContainer(session.container)
            .defaultAppStorage(session.defaults)
            .environment(session.toast)
            .environment(session.health)
            .environment(\.locale, Locale(identifier: session.configuration.localeIdentifier))
            .environment(\.layoutDirection,
                         Locale(identifier: session.configuration.localeIdentifier).language.characterDirection == .rightToLeft
                         ? .rightToLeft : .leftToRight)
            .environment(\.timeZone, session.configuration.calendar.timeZone)
            .environment(\.calendar, session.configuration.calendar)
            .sheet(item: $opened, onDismiss: {
                let completion = afterEditor; afterEditor = nil; completion?()
            }) { editor($0) }
            .sheet(isPresented: $showsTimer) { TimerSection(controller: session.services.timers, alarms: session.services.alarms) }
            .sheet(isPresented: $showsDay) { NavigationStack { agenda } }
            .overlay(alignment: .bottom) { UndoToastView().environment(session.toast) }
    }

    @ViewBuilder private var content: some View {
        switch session.configuration.scene {
        case .today:
            NavigationStack { agenda }
        case .todayReview:
            EveningReviewSheet(now: day, tomorrow: session.configuration.calendar.date(byAdding: .day, value: 1, to: day)!, peek: [])
        case .calendarWeek, .calendarMonth, .calendarYear:
            NavigationStack { CalendarView(day: $day, mode: $mode, calendar: session.services.calendar,
                onOpenTask: { opened = .task($0) }, onOpenAlarm: { opened = .alarm($0) },
                onOpenDay: { day = $0; showsDay = true }) }
        case .calendarKey: YearKeySheet()
        case .calendarSources: CalendarsSheet(calendar: session.services.calendar)
        case .eventEditor: EventEditor(event: events.first, day: day, calendar: session.services.calendar)
        case .reminders: RemindersView(isPushed: $pushed, path: $path, sync: session.services.reminders, requestAccess: session.services.requestReminderAccess)
        case .remindersToday: reminderList(.smart(.today))
        case .remindersScheduled: reminderList(.smart(.scheduled))
        case .remindersAll: reminderList(.smart(.all))
        case .remindersFlagged: reminderList(.smart(.flagged))
        case .remindersCompleted: reminderList(.smart(.completed))
        case .remindersList:
            reminderList(lists.first.map { .list($0.persistentModelID) } ?? .defaultList)
        case .reminderEditor: TaskEditor(task: tasks.first)
        case .reminderQuickAdd: QuickReminderSheet()
        case .reminderListEditor: ListEditor(list: lists.first)
        case .clockAlarms: AlarmsView(section: $clock, alarms: session.services.alarms, timers: session.services.timers, showUndo: session.toast.show)
        case .alarmEditor: AlarmEditor(alarm: alarms.first, showUndo: session.toast.show)
        case .alarmSound: NavigationStack { SoundScreen(sound: $sound) }
        case .clockWorld:
            WorldClockView(store: session.world, now: { session.configuration.now }, showUndo: session.toast.show)
        case .cityPicker: CityPicker(store: session.world, now: { session.configuration.now })
        case .clockStopwatch: StopwatchView(model: session.stopwatch)
        case .clockTimer: TimerSection(controller: session.services.timers, alarms: session.services.alarms)
        case .ask:
            AskView(thread: chats.first, calendar: session.services.calendar, now: { session.configuration.now },
                onBack: { _ in }, onAdded: { _ in }, onOpenDay: { day = $0; showsDay = true },
                onOpenTask: { task, completion in afterEditor = completion; opened = .task(task) },
                onOpenAlarm: { alarm, completion in afterEditor = completion; opened = .alarm(alarm) })
        case .askCapture, .askStack, .askPlan, .askChange, .askTidy:
            SceneAskCards(session: session)
        case .activity:
            ActivityView(activity: session.services.activity,
                         flush: { Ledger.flush(session.container.mainContext) },
                         undo: { Ledger.undo($0, context: session.container.mainContext) })
        case .search: SearchView { editor($0) }
        case .settings: settings(.all)
        case .settingsAppearance: settings(.appearance)
        case .settingsApple: settings(.apple)
        case .settingsToday: settings(.today)
        case .settingsCalendar: settings(.calendar)
        case .settingsReminders: settings(.reminders)
        case .settingsSmartLists: settings(.smartLists)
        case .settingsAlarms: settings(.alarms)
        case .settingsAI: settings(.ai)
        case .settingsAbout: settings(.about)
        case .settingsAutomaticChanges: NavigationStack { AutomaticChangesView() }
        case .settingsActivity: NavigationStack { activityData }
        case .settingsHolidays: NavigationStack { YearHolidaysSettingsView() }
        case .settingsDelete: settings(.data)
        case .health: HealthView(model: session.health)
        case .healthDetail:
            HealthMetricDetail(metric: .steps,
                               series: session.configuration.scenario == .empty ? .empty :
                                HealthSampleSeries.series(for: .steps, now: session.configuration.now, calendar: session.configuration.calendar),
                               now: session.configuration.now, units: HealthUnits(locale: Locale(identifier: session.configuration.localeIdentifier)),
                               calendar: session.configuration.calendar)
        case .healthPicker: HealthMetricPicker(shown: $shownMetrics)
        }
    }

    private var agenda: some View {
        DayAgenda(day: $day, showsWeekStrip: false, openTask: { opened = .task($0) },
                  openEvent: { opened = .local($0) }, openTimer: { showsTimer = true })
            .environment(session.healthLine!)
    }

    @ViewBuilder private func editor(_ destination: OpenedEntry) -> some View {
        switch destination {
        case .task(let task): TaskEditor(task: task)
        case .local(let event): EventEditor(event: event, calendar: session.services.calendar)
        case .alarm(let alarm): AlarmEditor(alarm: alarm, showUndo: session.toast.show)
        case .system(let id), .editSystem(let id): NativeEventSheet(identifier: id)
        case .new(let start, let end): EventEditor(start: start, end: end, calendar: session.services.calendar)
        }
    }

    private var activityData: some View {
        ActivityDataView(summary: session.services.activitySummary, clear: session.services.clearActivity,
            export: session.services.exportActivity,
            legacyRowCount: { (try? session.container.mainContext.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0 })
    }

    private func settings(_ selection: SettingsView.Selection) -> some View {
        SettingsView(selection: selection, calendar: session.services.calendar, reminders: session.services.reminders,
            notifications: session.services.notifications, diagnostics: session.services.diagnostics,
            calendars: { AnyView(CalendarsSheet(calendar: session.services.calendar)) },
            holidays: { AnyView(YearHolidaysSettingsView()) }, activityData: { AnyView(activityData) },
            shareDiagnostics: session.services.shareDiagnostics, reset: session.services.reset)
    }

    private func reminderList(_ target: ReminderTarget) -> some View {
        NavigationStack { ReminderListScreen(target: target) }
    }
    private var tasks: [OneTask] { (try? session.container.mainContext.fetch(FetchDescriptor<OneTask>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [] }
    private var events: [OneEvent] { (try? session.container.mainContext.fetch(FetchDescriptor<OneEvent>(sortBy: [SortDescriptor(\.start)]))) ?? [] }
    private var lists: [OneList] { (try? session.container.mainContext.fetch(FetchDescriptor<OneList>(sortBy: [SortDescriptor(\.order)]))) ?? [] }
    private var alarms: [OneAlarm] { (try? session.container.mainContext.fetch(FetchDescriptor<OneAlarm>(sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute), SortDescriptor(\.label)]))) ?? [] }
    private var chats: [ChatThread] { (try? session.container.mainContext.fetch(FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.title)]))) ?? [] }
}

/// Real product cards, with local selection state and existing creation/planning/undo APIs.
/// Mutations call AskNativeActions; assembly may override the feedback host.
@MainActor
private struct SceneAskCards: View {
    let session: SceneSession
    @State private var proposals: [CaptureProposal]
    @State private var tidy: [TidyRow]
    @State private var resolved = false
    @State private var entries: [UUID: LedgerItem] = [:]
    @State private var created: [UUID: PersistentIdentifier] = [:]
    @State private var opened: Opened?

    private struct Opened: Identifiable {
        let id: PersistentIdentifier
    }

    init(session: SceneSession) {
        self.session = session
        let config = session.configuration
        let batch = config.uuid(at: 200)
        let captures = ["Review the design", "Book train tickets", "Water the plants"]
        _proposals = State(initialValue: captures.enumerated().map { index, title in
            var proposal = CaptureProposal(capture: Capture(title: title, day: config.now, hasDay: true, hour: 14 + index),
                                           batchSize: config.scene == .askStack ? 3 : 1, batch: batch)
            proposal.id = config.uuid(at: UInt64(201 + index))
            return proposal
        })
        let tasks = (try? session.container.mainContext.fetch(FetchDescriptor<OneTask>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        _tidy = State(initialValue: tasks.filter { $0.due != nil }.prefix(3).map {
            TidyRow(task: $0, oldDue: $0.due!, choice: .keep)
        })
    }

    private var tasks: [OneTask] {
        (try? session.container.mainContext.fetch(FetchDescriptor<OneTask>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
    private var plan: [(task: OneTask, start: Date)] {
        tasks.filter { !$0.isDone }.prefix(3).enumerated().map {
            ($0.element, session.configuration.now.addingTimeInterval(Double($0.offset + 1) * 3600))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if resolved { Label("Preview resolved", systemImage: "checkmark.circle") }
                else {
                    switch session.configuration.scene {
                    case .askCapture:
                        CaptureCard(capture: $proposals[0].capture, status: proposals[0].status,
                                    onAdd: { add(proposals[0].id) }, onCancel: { proposals[0].status = .dropped },
                                    onUndo: { undo(proposals[0].id) },
                                    onOpen: { open(proposals[0].id) })
                    case .askStack:
                        CaptureStack(proposals: $proposals, lists: ["Work", "Home"], onAdd: add,
                                     onSkip: { id in update(id, status: .dropped) },
                                     onAddAll: { for p in proposals where p.status == .open { add(p.id) } },
                                     onUndo: undo, onOpen: open, onRename: rename)
                    case .askPlan:
                        PlanCard(plan: plan, onApply: applyPlan, onAlways: {
                            if let apply = session.runtime.applyAlways { apply(plan, session.container.mainContext, session.toast) }
                            else {
                                var rows = plan
                                var grant: AIGrant?
                                feedback(AskNativeActions.applyPlanAlways(plan: &rows, grant: &grant,
                                    context: session.container.mainContext, onApproved: { _ in }))
                            }
                            resolved = true
                        }, onCancel: { resolved = true })
                    case .askChange:
                        if let task = tasks.first {
                            let change = PendingChange(subject: .task(task), delete: false, title: task.title,
                                                       oldText: "Current planned time", newStart: session.configuration.now,
                                                       notes: [], attendees: 0)
                            ChangeCard(change: change, onApply: {
                                if let apply = session.runtime.applyChange { apply(change, session.container.mainContext, session.toast) }
                                else { feedback(AskNativeActions.applyChange(change, context: session.container.mainContext,
                                                                            calendar: session.services.calendar)) }
                                resolved = true
                            }, onCancel: { resolved = true })
                        }
                    case .askTidy:
                        TidyCard(rows: $tidy, onApply: {
                            if let apply = session.runtime.applyTidy { apply(tidy, session.container.mainContext, session.toast) }
                            else { feedback(AskNativeActions.applyTidy(rows: &tidy, context: session.container.mainContext)) }
                            resolved = true
                        }, onCancel: { resolved = true })
                    default: EmptyView() // This private host is constructed only for the five card IDs.
                    }
                }
            }
            .padding()
            .navigationTitle("Ask")
            .sheet(item: $opened) { item in
                let model = session.container.mainContext.model(for: item.id)
                if let task = model as? OneTask { TaskEditor(task: task) }
                else if let event = model as? OneEvent { EventEditor(event: event, calendar: session.services.calendar) }
                else if let alarm = model as? OneAlarm { AlarmEditor(alarm: alarm, showUndo: session.toast.show) }
            }
        }
    }

    private func open(_ id: UUID) {
        guard let item = created[id] else { return }
        opened = Opened(id: item)
    }
    private func update(_ id: UUID, status: CardStatus) {
        if let index = proposals.firstIndex(where: { $0.id == id }) { proposals[index].status = status }
    }
    private func rename(_ id: UUID, to title: String) -> Bool {
        guard let modelID = created[id],
              CaptureUndo.rename(Ledger.ref(modelID), to: title, in: session.container.mainContext),
              let index = proposals.firstIndex(where: { $0.id == id }) else { return false }
        proposals[index].capture.title = title
        return true
    }

    private func add(_ id: UUID) {
        guard let proposal = proposals.first(where: { $0.id == id }), (proposal.status == .open || proposal.status == .undone) else { return }
        let result = proposal.capture.insertRecorded(into: session.container.mainContext,
                                                     actor: .todayAI, channel: .ask, approval: .asked)
        created[id] = result.id
        entries[id] = result.entry
        update(id, status: .added)
        session.toast.show("Added") {
            undo(id)
        }
    }
    private func undo(_ id: UUID) {
        guard let entry = entries[id] else { return }
        if Ledger.undo(entry, context: session.container.mainContext) { update(id, status: .undone) }
    }
    private func feedback(_ feedback: AskActionFeedback) {
        if let undo = feedback.undo { session.toast.show(undo.label, undo: undo.action) }
    }
    private func applyPlan() {
        var rows = plan
        feedback(AskNativeActions.applyPlan(plan: &rows, grant: nil, context: session.container.mainContext))
        resolved = true
    }

}

struct SceneFailure: View {
    let error: any Error
    var body: some View {
        ContentUnavailableView("Scene unavailable", systemImage: "exclamationmark.triangle",
                               description: Text(String(describing: error)))
            .accessibilityIdentifier("scene.rejected")
    }
}
#endif
