# Session services implementation handoff

Base: `81d020d26c8ce668c9508cf1cd9d78a9fbe1f092`.
This lane changes only the authorized One service/action files and this note. It does not change persistent declarations, ServiceContracts, PlannerRuntime, OneStore, intents, features, platform, development assembly, package or project configuration.

## Assembly and identity

Construct `ActivityCenter(store:defaults:runtime:)` with an already selected/opened ActivityStore. The initializer does not inspect process arguments, select a path, open a database, import an outbox or start UIKit background work. It retains a real ActivityRecorder, a runtime-generated recorder session, and cancellable flush scheduling. Subscribe to `activity.didChange` **with `object: activity`**; using only the name would observe other sessions. Export now requires `export(_:to:)` with a caller-selected destination. Live file identity/recovery, test Activity settings reset and synthetic paging rows move to root composition; they are no longer initializer effects.

Construct CalendarSync and RemindersSync with explicit defaults, runtime, arguments and lazy `makeStore` closures. They conform to NativeCalendarService and ReminderService respectively. NativeCalendarService remains the explicit live-only refinement of CalendarService; deterministic calendar implementations must not claim it. All CalendarSync readers/editor helpers retain their own EventKit store. NativeEvents is an instance presenter retained by that CalendarSync, with a cancellable polling task and instance delegate. Existing editor saves and unchanged Done preserve `.saved`; Cancel preserves `.canceled`; More Options forwards the actual system action. Title reads/renames use CalendarService operations and never manufacture a replacement EKEvent. Failed local rename after a successful external rename attempts compensation and returns false; this is not a cross-store atomic transaction.

Construct reminders first, then `Ledger(activity:reminders:runtime:)`, then call `reminders.configure(container, ledger: ledger)` once. This explicit lifecycle attachment breaks the reminder/ledger construction cycle: RemindersSync retains a weak ledger, while the application/session retains both. Reconciliation does not run its pass without that ledger. The save observer is scoped to the configured main context, not all stores. Root intent handlers using another context must explicitly request reconciliation after their writes. Forget-link/dispose invalidate snapshots already awaiting EventKit. The existing completion revision fence, expected receipt, Apple-wins conflict baseline, deletion retry sets and maximum external-delete cap remain in the real adapter.

Construct exactly one `Ringer(defaults:runtime:)` for the live application and pass it to **both** `AlarmCenter(driver:)` and `TimerController(defaults:runtime:driver:donate:)`. Ringer is the only source of AlarmManager.shared. TimerController enforces identity of its defaults with the driver's defaults. The driver's protected timer IDs combine persisted TimerStore IDs and in-flight claims; alarm reconciliation checks them again after awaits. Timer startup reserves/persists before scheduling, serializes overlapping starts, suppresses refresh of an uncommitted schedule, and cancels a schedule accepted after a user cancellation. Failed startup removes only that timer and does not restore a previously cancelled Focus timer. Stop never completes a task. Root must use these same retained adapters for early AppIntent invocations and UI initialization, not construct another ownership set.

TimerController is a real TimerService. Its running timers, recents, sound and Pomodoro log use explicit defaults; all timing uses runtime. Donation is a required callback supplied only by live composition. The former debug `-uiTestingTimers`, `-uiTestingRecents`, `-pomodoroRounds` in-class fake branches are removed. Test/development assembly must provide a development TimerService for those scenarios; production must not select fake AlarmKit through arguments.

Construct `Reminders(center:alarms:reminders:ledger:runtime:)` with an explicit UNUserNotificationCenter and then configure its container. Its notification callbacks dispatch the same TaskActions with the same reminder adapter, ledger and runtime. `plannerReminderDate` overloads preserve the task/event notification projection using explicit calendar/clock, without altering model declarations.

Construct WidgetFeed with the container, CalendarService, ReminderService, runtime, enabled switch, travel callback, snapshot sink and reload callback. Production composition selects App Group saving, WidgetCenter reload, background registration and travel-cache update wiring explicitly. A session can select an inspectable local sink. The travel callback has the existing `(minutes: Int, leaveBy: Date)?` result and receives explicit now. No widget algorithm resolves CalendarSync or TravelTimes. `registerBackgroundRefresh` and `scheduleBackgroundRefresh` are explicit live lifecycle operations; never invoke them in a development session. The existing BackgroundTasks main-queue handoff remains confined here.

Dispose view-owned watch tasks first; then dispose CalendarSync, RemindersSync, Reminders, WidgetFeed and UndoToast; flush/dispose Ledger before disposing ActivityCenter; remove isolated defaults last. AlarmCenter/TimerController watch methods end when their calling task is cancelled. Live AlarmKit schedules are intentionally not cancelled just because a view disappears. There is no separate service-instance cleanup that cancels another owner's timers.

## Action consumers

`PlannerActions` is a real observable action capability with private dependencies and required `init(calendar:reminders:alarms:ledger:runtime:)`. It exposes complete/reopen, task/alarm/entry delete, planned time, automatic planning, capture insertion, Activity Undo, capture Undo/title/rename. It delegates to the existing production algorithms with explicit dependencies; it exposes no service getter. Feature entry points must install this object in the environment and propagate it through nested sheets, navigation and UIKit hosting roots. No static compatibility locator remains to make old consumers compile.

TaskActions completion keeps remote commit before local mutation. Linked save failure retains accepted state and schedules reconciliation; local failure restores completion state. Toast Undo captures the accepted Remote receipt and passes it as `expected`, restores the prior due/plan and follows the same persistence path. Undo refuses a deleted model. Local recurrence advancement uses the original copy/checklist-reset algorithm with runtime calendar, IDs and time. CalendarEntries uses the real Recurrence algorithm with explicit calendar. Planned time still does not change deadlines.

Ledger owns pending entries, their context, flush flag/task, and session Undo identities. `dispose()` flushes only its own context and cancels its delayed task. Save failure keeps pending model-backed entries rather than writing temporary IDs. Activity Undo checks recorded/session Undo identities before restoring a deletion. Reference encoding and snapshots remain pure static helpers; all side-effectful methods are instances. No static ledger buffer or static ActivityCenter write survives. List create/rename/delete now record list changes through the supplied ledger. GrantStore mutations receive ledger/runtime, retain seven-day expiry and commit-before-recording for the Settings toggle. AutoPlan retains the Changes-recording gate and AutonomyPolicy, uses runtime for every policy window, and does not undo into deleted tasks.

Capture insertion remains in CapturePersistence; `insert` and `insertRecorded` now **throw** on local save failure. They return the existing final PersistentIdentifier / `(id, entry)` only after a successful save, and record creation afterward. Callers must handle the error before resolving a preview/card as Added. `makeAlarm(now:calendar:)` and `makeEvent(calendar:)` require explicit time/calendar. CaptureUndo uses CalendarService title/rename rather than exposing EventKit objects, and schedules alarms through the supplied AlarmService.

DataReset requires `ShareInboxReading` (`read() throws -> [SharedReminder]`, `acknowledge(Set<UUID>) -> Bool`). Root supplies the actual ShareInbox adapter; development supplies an empty/fixture inbox. It preserves forget-link before model clearing, inbox read/ack before receipt removal, then local Activity clear and save. An unreadable/unacknowledged inbox retains opaque receipts. No local reset calls external deletion.

FirstRun's static methods now require their capability plus explicit defaults/arguments (notifications for alarms); they cannot choose live adapters. SyncDumpProbe requires `init(sync:)`. NativeEventSheet and NativeEventEditor require an explicit native calendar plus start date. CalEntry overlap/span and CalendarEntries.on now require calendar.

## Contract corrections and root follow-up

No edit to ServiceContracts.swift or PlannerRuntime.swift was needed for the five live service conformances. Required caller migrations are intentional intermediate compile breaks; do not restore `.shared`, `.standard`, a live constructor default, or a static forwarding API.

- Root must migrate OneStore/App/intent assembly and all static Ledger/Activity calls to retained instances, add PlannerActions to the One target if its source list is explicit, preserve live disk/App Group identity and startup order, and implement the typed inbox adapter.
- Root/feature owners must migrate every signature below, handle throwing capture saves, preserve the actual native edit action, update Activity notification subscriptions and export destination closures, and wire travel updates to the retained WidgetFeed. Direct NativeEvents static calls become NativeCalendarService.edit calls; direct Ringer calls use the retained AlarmService/driver at the live boundary.
- The ratified proposal mentions a TravelTimeProviding contract, but the base ServiceContracts has no such declaration. This lane uses a required narrow widget travel closure rather than inventing/editing the root contract. Root should coordinate the eventual platform protocol and adapt this callback when that seam lands.
- Persistent model declarations/initializers remain unchanged. Their older convenience methods elsewhere still contain wall-clock/calendar reads (`OneTask.nextOccurrence`, `reminderDate`, overdue checks, OneEvent occurrence/reminder helpers, OneAlarm time/retirement helpers). Owned action algorithms avoid those reads using explicit runtime projections. Root must migrate remaining model consumers without editing schema declarations.
- Pure Core/Data presentation helpers still have system-relative defaults: DayLabel uses `Calendar.isDateInToday`, EventSpeech/Date formatting use the system locale, ActivityStore retention/ActivityWindows cutoff may use a default calendar. Owned action day labels now use `plannerDayLabel`; CalEntry.speech and native EventKit editor display still use existing system formatting. Root should add explicit runtime-aware presentation/retention overloads where deterministic rendering needs them; this lane does not edit Core/Data contracts. This handoff does not claim complete Workbench isolation.

Remaining process-wide APIs in these owned files are explicit live adapter boundaries: Ringer's sole AlarmManager.shared; native editor UIKit presentation; ActivityCenter's explicitly called UIKit background flush/outbox import; WidgetFeed's explicitly called BGTaskScheduler registration/submission. NotificationCenter is used with session objects/scoped store observers. No UserDefaults.standard, Calendar.current, Date.now, TodayClock, service `.shared`, production timer fake, unsafe Sendable conformance or Core actor blanket is added/retained in owned algorithms. Operational UUIDs for toast/flush cancellation tokens are not persisted model identity.

## Validation and acceptance boundary

Only lightweight Swift frontend syntax parsing for these 19 One files, source ownership/dependency checks and `git diff --check` run in this lane. Raw output and a JSON source audit are retained in the primary checkout's tests/results and indexed through tests/qa/journal.py. The parser emits the host sysroot/target warning; it exits successfully. Syntax parsing does not resolve imports, type-check conformances or prove behavior.

No Xcode build, SwiftPM run, simulator, device, security identity command or authenticated E2E flow ran: the parent explicitly owns the heavy host lane and consumer migration is pending. Root's focused integrated validation must cover remote completion accepted/local save failure and expected-receipt Undo, recurrence Undo and no resurrection, two independent ledgers/defaults plus dispose, Changes paused under a seven-day grant, calendar read-only/occurrence deletion and native unchanged/changed save callbacks, shared AlarmKit timer protection, capture failed-save preview state, and inbox ack failure during local reset. Real AlarmKit/EventKit/device acceptance remains separate from source and simulator evidence.

## Exact new or changed callable signatures

The following inventory is extracted from the bounded sources against the base commit. Owner names are given by file; unchanged signatures whose owner became an instance are described above. Defaults shown are value defaults, never live service defaults.

### CalendarSync.swift

```swift
package init(id: String, eventIdentifier: String, title: String, location: String = "", start: Date, end: Date, isAllDay: Bool, calendarID: String = "", calendarTitle: String, color: Color, place: TravelPlace? = nil, repeats: Bool = false, isBackground: Bool = false, isBirthday: Bool = false, isHoliday: Bool = false)
package init(id: String, title: String, sourceTitle: String, color: Color, isBirthday: Bool = false, isHoliday: Bool = false)
package init(defaults: UserDefaults, runtime: PlannerRuntime, arguments: [String], makeStore: @escaping () -> EKEventStore)
package func dispose()
package func edit(identifier: String?, start: Date, end: Date?, fullOptions: Bool, onComplete: ((EKEventEditViewAction) -> Void)?)
package func title(externalID: String, occurrence: Date?) -> String?
package func rename(externalID: String, occurrence: Date?, to title: String) -> Bool
package init(sync: CalendarSync)
package func dispose()
package func edit(identifier: String?, start: Date, end: Date?, fullOptions: Bool, onComplete: ((EKEventEditViewAction) -> Void)?)
package init(identifier: String, start: Date, calendar: any NativeCalendarService)
package init(identifier: String?, start: Date, calendar: any NativeCalendarService)
```

### RemindersSync.swift

```swift
package init(defaults: UserDefaults, runtime: PlannerRuntime, arguments: [String], makeStore: @escaping () -> EKEventStore)
package func dispose()
package func configure(_ container: ModelContainer, ledger: Ledger)
package init(id: String, title: String, notes: String, isDone: Bool, doneAt: Date?, due: Date?, listID: String, listTitle: String, flagged: Bool, repeatRule: String?, repeats: Bool)
package nonisolated static func date(from c: DateComponents, calendar: Calendar) -> Date?
package static func components(for due: Date, calendar cal: Calendar) -> DateComponents
package init(sync: RemindersSync)
```

### Reminders.swift

```swift
package init(center: UNUserNotificationCenter, alarms: any AlarmService, reminders: any ReminderService, ledger: Ledger, runtime: PlannerRuntime)
package func dispose()
package func plannerReminderDate(_ task: OneTask, runtime: PlannerRuntime) -> Date?
package func plannerReminderDate(_ event: OneEvent, runtime: PlannerRuntime) -> Date?
```

### Ringer.swift

```swift
package init(defaults: UserDefaults, runtime: PlannerRuntime)
package func requireTimerDefaults(_ defaults: UserDefaults)
package func claimTimer(_ id: UUID)
package func releaseTimer(_ id: UUID)
package func requestAuthorization() async
package func sync(_ context: ModelContext) async
package func stop(_ id: UUID)
package static func reconcile(_ context: ModelContext, driver: Ringer) async
```

### AlarmCenter.swift

```swift
package init(driver: Ringer)
package func sync(_ context: ModelContext) async
package func stop(_ id: UUID)
```

### TimerController.swift

```swift
package init(defaults: UserDefaults, runtime: PlannerRuntime, driver: Ringer, donate: @escaping (Int) -> Void)
```

### ActivityCenter.swift

```swift
package init(store: ActivityStore?, defaults: UserDefaults, runtime: PlannerRuntime)
package func dispose()
package func record(_ event: ActivityEvent)
package func flushInBackground()
package func importOutbox()
package func prune()
package func summary() -> Summary
package func clear(tiers: Set<ActivityTier>? = nil, context: ModelContext?)
package func export(_ format: ActivityExportFormat, to url: URL) async throws -> URL
```

### Ledger.swift

```swift
package init(activity: ActivityCenter, reminders: any ReminderService, runtime: PlannerRuntime)
package func timeLabel(_ date: Date?, none: String = "Not planned") -> String
package func dayLabel(_ date: Date) -> String
package func dispose()
package func record(_ action: LedgerAction, task: OneTask? = nil, kind: String = "task", title: String, before: String = "", after: String = "", beforeDate: Date? = nil, afterDate: Date? = nil, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade, snapshot: TaskSnapshot? = nil, undoOf: UUID? = nil, context: ModelContext) -> LedgerItem
package func recordUndo(of entry: LedgerItem, task: OneTask? = nil, actor: LedgerActor = .you, channel: LedgerChannel = .app, context: ModelContext) -> LedgerItem
package func flush(_ context: ModelContext)
package func task(for entry: LedgerItem, in context: ModelContext) -> OneTask?
package func prune(_ context: ModelContext, now: Date)
package func count() -> Int
package func clear(_ context: ModelContext)
package func clearAll(_ context: ModelContext)
package func protectedRefs(_ context: ModelContext, now: Date) -> (aiRecent: Set<String>, userChose: Set<String>)
package func task(from s: TaskSnapshot) -> OneTask
package func removeCreatedTask(_ task: OneTask, context: ModelContext, channel: LedgerChannel) -> Bool
package func undo(_ entry: LedgerItem, context: ModelContext) -> Bool
package static func run(context: ModelContext, ledger: Ledger)
package static func seedLegacyForTests(context: ModelContext, arguments: [String], runtime: PlannerRuntime)
package static func active(_ scope: GrantScope, context: ModelContext, now: Date) -> AIGrant?
package static func setEnabled(_ enabled: Bool, scope: GrantScope, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) throws
package static func grant(_ scope: GrantScope, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) -> AIGrant
package static func revoke(_ g: AIGrant, context: ModelContext, ledger: Ledger, runtime: PlannerRuntime)
package static func run(context: ModelContext, toast: UndoToast, calendar: any CalendarService, ledger: Ledger, runtime: PlannerRuntime)
```

### TaskActions.swift

```swift
package func dispose()
package static func toggleDone(_ task: OneTask, context: ModelContext, toast: UndoToast?, reminders: any ReminderService, ledger: Ledger, runtime: PlannerRuntime, actor: LedgerActor = .you, channel: LedgerChannel = .app)
package static func delete(_ task: OneTask, context: ModelContext, toast: UndoToast?, reminders: any ReminderService, ledger: Ledger, runtime: PlannerRuntime, actor: LedgerActor = .you, channel: LedgerChannel = .app)
package static func setPlanned(_ task: OneTask, to start: Date?, context: ModelContext, ledger: Ledger, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade) -> LedgerItem?
package func plannerDayLabel(_ date: Date, runtime: PlannerRuntime, includeTime: Bool = true) -> String
```

### ListActions.swift

```swift
package static func ensureLists(in context: ModelContext, runtime: PlannerRuntime)
package static func create(name: String, colorIndex: Int, symbol: String, in context: ModelContext, ledger: Ledger, runtime: PlannerRuntime) -> OneList?
package static func rename(_ list: OneList, to name: String, in context: ModelContext, ledger: Ledger) -> Bool
package static func delete(_ list: OneList, keepingTasks: Bool = false, in context: ModelContext, reminders: any ReminderService, ledger: Ledger, runtime: PlannerRuntime)
```

### AlarmActions.swift

```swift
package func alarmTitle(_ a: OneAlarm, runtime: PlannerRuntime) -> String
package static func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?, alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime)
```

### EntryDeletion.swift

```swift
package static func perform(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?, calendar: any CalendarService, reminders: any ReminderService, alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime)
```

### CaptureUndo.swift

```swift
package static func undo(itemRef: String?, entryID: UUID?, title: String, context: ModelContext, calendar: any CalendarService, alarms: any AlarmService, ledger: Ledger) -> Bool
package static func title(_ ref: String?, in context: ModelContext, calendar: any CalendarService) -> String?
package static func rename(_ ref: String?, to title: String, in context: ModelContext, calendar: any CalendarService, reminders: any ReminderService, alarms: any AlarmService) -> Bool
```

### DataReset.swift

```swift
package static func run(_ context: ModelContext, reminders: any ReminderService, ledger: Ledger, inbox: any ShareInboxReading)
```

### WidgetFeed.swift

```swift
package init(container: ModelContainer, calendar: any CalendarService, reminders: any ReminderService, runtime: PlannerRuntime, enabled: Bool, travel: @escaping (String, Date, Bool, TravelPlace?, Date) -> (minutes: Int, leaveBy: Date)?, save: @escaping (WidgetSnapshot) -> Bool, reload: @escaping () -> Void)
package func dispose()
package func update(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date, calendar: Calendar)
package func items(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date, calendar: Calendar) -> [WidgetItem]
package func registerBackgroundRefresh()
package func scheduleBackgroundRefresh()
package func rewriteFromStore()
```

### FirstRun.swift

```swift
package static func calendar(_ calendar: any CalendarService, defaults: UserDefaults, arguments: [String]) async
package static func reminders(_ reminders: any ReminderService, defaults: UserDefaults, arguments: [String]) async
package static func alarms(_ alarms: any AlarmService, notifications: any NotificationService, arguments: [String]) async
```

### CalendarEntries.swift

```swift
package func overlaps(_ day: Date, calendar: Calendar) -> Bool
package func span(on day: Date, calendar: Calendar) -> (start: Date, end: Date, allDay: Bool)
package static func make(in interval: DateInterval, events: [OneEvent], tasks: [OneTask], alarms: [OneAlarm] = [], calendarService: any CalendarService, now: Date, calendar: Calendar, forYearMarks: Bool = false) -> [CalEntry]
package static func on(_ day: Date, in entries: [CalEntry], calendar: Calendar) -> [CalEntry]
```

### CapturePersistence.swift

```swift
package func makeAlarm(now: Date, calendar cal: Calendar) -> OneAlarm?
package func makeEvent(calendar: Calendar) -> OneEvent
package func insert(into context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade, ledger: Ledger, runtime: PlannerRuntime) throws -> PersistentIdentifier
package func insertRecorded(into context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade, ledger: Ledger, runtime: PlannerRuntime) throws -> (id: PersistentIdentifier, entry: LedgerItem)
```

### PlannerActions.swift

```swift
package init(calendar: any CalendarService, reminders: any ReminderService, alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime)
package func toggleDone(_ task: OneTask, context: ModelContext, toast: UndoToast?, actor: LedgerActor = .you, channel: LedgerChannel = .app)
package func delete(_ task: OneTask, context: ModelContext, toast: UndoToast?, actor: LedgerActor = .you, channel: LedgerChannel = .app)
package func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?)
package func delete(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?)
package func setPlanned(_ task: OneTask, to start: Date?, context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade) -> LedgerItem?
package func autoPlan(context: ModelContext, toast: UndoToast)
package func insert(_ capture: Capture, into context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade) throws -> (id: PersistentIdentifier, entry: LedgerItem)
package func undo(_ entry: LedgerItem, context: ModelContext) -> Bool
package func undoCapture(itemRef: String?, entryID: UUID?, title: String, context: ModelContext) -> Bool
package func captureTitle(_ ref: String?, in context: ModelContext) -> String?
package func renameCapture(_ ref: String?, to title: String, in context: ModelContext) -> Bool
```

## Retained source evidence

Final lightweight audit: all 17 checks passed, including the DEBUG iOS syntax parse, five declared protocol conformances, one AlarmManager.shared lookup, absence of implicit service/defaults/clock reads, preserved receipt/failure and policy gates, bounded ownership, and byte-identical root models/contracts/runtime. These are source assertions, not runtime tests.

Canonical evidence directory: `/Users/yuanlu/code/one-app/tests/results/session-services-20261018-210955-700ca951`.
QA journal session: `session-services-f1318c12`. Indexed files: `syntax-parse.log`, `diff-check.log`, `source-audit.json`, `bounded.patch` (tracked-file diff at audit time; new source and this note are preserved in the commit). No historical evidence was deleted or overwritten.
