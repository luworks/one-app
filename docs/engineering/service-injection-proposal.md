# Explicit service injection for all Workbench scenes

Status: root-ratified direction for implementation; not an isolation claim. Concrete source signatures in `ServiceContracts.swift` and `PlannerRuntime.swift` are authoritative. Native EventKit UI remains a separate explicit live capability. Reminder completion receipts retain their existing `RemindersSync.Remote` identity while gaining a value initializer. Read against `2145eb6ef9cbb0b1c7dd404200df15a8f8f8ba48` (current checkout; descendant of requested `ee0a478`). No build, simulator, permission prompt or production service was started for this diagnosis.

## Decision

Keep the existing real feature screens and action algorithms. Replace concrete global service access with required, typed instance dependencies at their existing constructors, and pass those instances through every action and Undo closure. Keep the SwiftData compatibility boundary explicit in `One`. Do not add a universal `Services.current`, a mutable process mode, a default `.live` parameter, or a Workbench `-uiTesting` switch.

Use two composition roots: production constructs live adapters once; each Workbench `SceneSession` constructs its own deterministic implementations. Production adapter implementations may remain in `One` while they need its models. Do not force them into `TodayPlatform` by introducing a reverse package dependency. Core owns only Foundation contracts; shared formats remain extension-safe. This follows [architecture.md](architecture.md).

The smallest viable change is **not** five substituted singleton names: Calendar's native editors, the static ledger buffer, notification delegates, model helpers, Ask's model calls, travel lookups and non-AppStorage preferences all bypass those five seams today.

## Evidence and actual effect boundary

Paths below are relative to `ios/`; function names are the stable source handles. This inventory covers effects reachable from real scene rendering, interaction, nested sheets and shell/intent launch. It does not assert that every branch currently compiles after the ongoing module reconstruction.

| Source and entry point | Actual effect / necessary seam |
| --- | --- |
| `Sources/One/CalendarSync.swift`: lazy `store`, `prepareStore`, `prepare`, `setEnabled`, `connectIfFirstRun`, `setVisibleCalendars`, event lookup/save/delete | EventKit construction, store-change subscription, access request, calendar reads/writes, standard defaults. `version`, readiness, metadata and hidden-calendar filtering are behavior, not optional mocks. |
| Same file: `NativeEvents.edit/watch/Delegate`, `ExistingCalendarEventEditor.save`, `SystemEventEditor` coordinator; `Features/FeatureCalendar/NativeCalendarChooser.swift` | UIKit presentation, EventKit editor/viewer/chooser writes, refresh callbacks and polling. Inject a native presenter separately; no Workbench path may create an EK controller/store, including callbacks. Preserve native save/dismiss semantics. |
| `Sources/One/RemindersSync.swift`: `configure`, `connect*`, `disconnect`, `forgetLink`, `scheduleReconcile`, `reconcile`, `commitCompletion`, `didPersistCompletion`, `noteDeleted` | EventKit reads/writes; local-save/store-change subscriptions; delayed reconciliation; persisted fingerprint/tombstone defaults; local SwiftData mutations; sync-conflict Activity. `configure` currently observes **all** model saves (`object: nil`); a live adapter must ignore foreign containers. |
| `Sources/One/Reminders.swift`: `configure`, permission methods, `resync`, notification response delegate | UN categories/delegate, permission, scheduled alerts, badge, Done/Snooze/Tomorrow actions. Notification callbacks must receive the same action dependencies as views. |
| `Sources/One/Ringer.swift`: authorization, `sync/reconcile`, `stop`; `AlarmCenter.swift`: `watch`, authorization/alarm update loops | AlarmKit permission, enumerate/schedule/cancel/stop; mutates stable `alarmKitID` and retires one-shot alarms. Ringer must preserve IDs owned by running timers. Watch cancellation must be session-owned. |
| `Sources/One/TimerController.swift`: initializer, `start/pause/resume/cancel/refresh/watch`, recents/sound/log setters; `TimerIntents.swift` | AlarmKit, `TimerStore`/recents/Pomodoro/defaults persistence, intent donation, update streams. Existing fake mode depends on launch arguments and is not a Workbench isolation boundary. |
| `Sources/One/ActivityCenter.swift`: initializer, `record`, `flushInBackground`, `importOutbox`, `prune`, `clear`, `summary`, `export` | Opens/recover/prunes user Activity SQLite, batches records, mutates Activity settings, imports/removes App Group outbox, background task, export file. Workbench can record into its session-only memory store, never the user's Activity database or outbox. |
| `Sources/One/Ledger.swift`: `pending`, `flushScheduled`, `record/flush/undo`, `LedgerMigration.run`, `GrantStore`, `AutoPlan.run` | Process-static buffer can mix contexts even with injected Activity. Undo reads snapshots and reconciles/deletes reminders; migration and grants write. Convert the buffer and scheduled task to an instance, not a static function with a new service argument. Keep recording/Undo/autonomy policy coupled. |
| `Sources/One/Models.swift`: `Capture.insert/insertRecorded`; `TaskActions`, `ListActions`, `AlarmActions`, `EntryDeletion`, `CaptureUndo`, `DataReset` | SwiftData + ledger + indirect EventKit/AlarmKit. These helpers are not pure. `DataReset.run` reads/acknowledges `ShareInbox`; ordering protects receipts from resurrecting shares. `CaptureUndo.rename/title` also reaches native calendar objects. |
| `Sources/One/WidgetFeed.swift`: `configure`, `update`, `rewriteFromStore`, background registration/scheduling/run | App Group snapshot write, WidgetKit reload, BGTask scheduling, Reminders reconciliation, Calendar warmup; installs `TravelTimes.didUpdateEstimate`. Snapshot selection (`items`) also reads live calendar/travel. |
| `Sources/TodayShell/HomeView.swift`: `bootstrap`, `.task`, model signature task, foreground/background handlers, `importShared`, `autoPlan`, `dropDeletedMirrors`, `newEvent`; `Destinations.swift` | Starts all services above; imports/acknowledges shares, migrates Activity, creates defaults/sample data, handles quick actions, stores tab state. Destinations currently reconstruct `.shared` dependencies despite feature constructors. Workbench must not instantiate HomeView/OneStore/AppDelegate as its sandbox. |
| `Sources/One/OneStore.swift`: `start/container`; `App/OneApp.swift`; `Sources/One/AppIntents.swift`: `perform`, `IntentSupport`; `TimerIntents.swift` queries/actions | First caller may be Siri with no UI. Opens the live model store, registers notifications/sync/widgets and performs writes without a SwiftUI environment. Preserve one process identity and initialize before any intent query or perform. |
| `Sources/TodayPlatform/TravelTimes.swift`: initializer, `seconds/label/widgetFields`, delegate, `eta/save`; planner rows and `FeatureAsk/AskSuggestionContext.swift` | Rendering an eligible event can request location, start MapKit geocoding/ETA/network work, cache defaults and trigger widget writes. Inject this even when Calendar reads are already isolated. |
| `Sources/TodayPlatform/AlarmSounds.swift`: `SoundPreview.play/stop`; `FeatureClock/AlarmEditor.swift` SoundScreen | AVAudioSession activation and audio playback. A Workbench sound selection must exercise the binding with session-only preview behavior. |
| `Features/FeatureAsk`: `VoiceInput.start/stop`, `Understander.prewarm/parse`, `AICapture.propose/refineTitle`, `ChatResponse.respond`, `Editing.plan`, `AskSuggestionRanker.rank`; `AskSuggestionList` memory | Speech/mic permission, audio engine/session, Foundation Models sessions/prewarm, global suggestion cache and Activity. Simulator unavailability is not isolation proof. Even `VoiceInput.stop()` touches AVAudioSession. |
| `Features/FeatureHealth/HealthModel.swift`, `TodayHealthLine.swift`, `TodayPlatform/HealthKitSource.swift` | Existing `HealthSource` is the correct injected boundary: authorization and queries only (Today has no Health write API). Selection changes persist defaults. Inject clock and selection store into both Health models; do not construct HealthKitSource in Workbench. |
| `FeatureSearch/SearchView.swift` `SearchMemory`; `FeatureReminders/RemindersView.swift`; preference readers; `TodayPlatform/Appearance.swift`; Settings permission links; `LocalDiagnostics.start/exportURL` | Standard-default reads/writes, settings URL opening, window appearance changes, MetricKit subscription and export files. `.defaultAppStorage(session.defaults)` only redirects `@AppStorage`, not direct `.standard`, static readers or default constructor arguments. |

Other source-backed bypasses: `CalendarEntries.make` selects `CalendarSync.shared`; `TodayPlannerUI/Rows.swift`, `ExternalEventRow.swift`, `EntryActions.swift`, `FeatureToday/DayAgenda.swift` and `FeatureSearch/SearchView.swift` query globals; `EveningReviewSheet.apply` deletes via RemindersSync; Clock editors still call static Ringer. Search for inferred `.shared` as well as fully qualified names: `TodayShell/Destinations.swift` lines 21–56 are a concrete example.

## Contracts to ratify

The following are proposed signatures, not declarations already present. No schema fields, encoded values or persistent module names change. All model-facing contracts are `@MainActor` and package-visible in `One` (public only when an executable composition root needs them). SwiftData objects and contexts never cross actors.

### Core: only values, time and identity

```swift
// TodayCore; Foundation only. The scene owns an instance; no mutable static clock.
public struct PlannerRuntime {
    public let now: @Sendable () -> Date
    public let nextID: @Sendable () -> UUID
    public let calendar: Calendar
    public let locale: Locale
    public init(now: @escaping @Sendable () -> Date,
                nextID: @escaping @Sendable () -> UUID,
                calendar: Calendar, locale: Locale)
}
```

Live closures return wall time / UUID; Workbench uses a fixed time and an owned deterministic ID sequence (synchronized if Sendable; no unchecked suppression). Rendering uses fixed time; stopwatch/timer simulation can explicitly advance a session clock. Do not freeze production countdowns. `SceneConfiguration.uuid(at:)` already supplies the stable byte algorithm.

Reuse `HealthSource` instead of inventing another Health protocol. Do not put `OneTask`, `ModelContext`, `EKEvent`, `Color`, `ActivityStore` or `PendingChange` into Core. Existing Core capture/domain constructors that generate IDs must accept explicit IDs/defaults from the runtime when used by session fixtures. Existing persistent model initializers remain identity-compatible; add nonpersistent helper parameters only under root ownership.

### One: narrow compatibility protocols

```swift
@MainActor package protocol CalendarService: AnyObject {
    var version: Int { get }
    var isReady: Bool { get }
    var hasAccess: Bool { get }
    var isOn: Bool { get }
    var usesNativeEditor: Bool { get }
    var hiddenCalendarIDs: Set<String> { get }
    func prepare()
    func prepareStore()
    func connectIfFirstRun() async
    func setEnabled(_ on: Bool) async
    func refresh()
    func calendars() -> [SystemCalendar]
    func setVisibleCalendars(_ selected: Set<String>)
    func events(in interval: DateInterval, excluding: Set<String>) -> [ExternalEvent]
    func events(on day: Date, excluding: Set<String>) -> [ExternalEvent]
    func calendar(forExternalID id: String?) -> SystemCalendar?
    func place(forExternalID id: String?) -> TravelPlace?
    func color(forExternalID id: String?) -> Color?
    func isHidden(externalID: String?) -> Bool
    func isRepeating(externalID: String?) -> Bool
    func audience(externalID: String?) -> (attendees: Int, isOrganizer: Bool)?
    func canDelete(externalID: String?) -> Bool
    func save(_ event: OneEvent, span: EKSpan) -> String?
    func delete(_ event: OneEvent, span: EKSpan) -> Bool
    func delete(externalID: String?, occurrence: Date?, span: EKSpan) -> Bool
    func removedMirrors(_ events: [OneEvent]) -> [OneEvent]
    func title(externalID: String, occurrence: Date?) -> String?
    func rename(externalID: String, occurrence: Date?, to title: String) -> Bool
}

@MainActor package protocol ReminderService: AnyObject {
    var hasAccess: Bool { get }
    var isConnected: Bool { get }
    var isDenied: Bool { get }
    var lastError: String? { get }
    func connectIfFirstRun() async
    func connect() async
    func disconnect()
    func forgetLink()
    func noteDeleted(reminder externalID: String?)
    func noteDeleted(list externalID: String?)
    func scheduleReconcile(after delay: Duration)
    func reconcile() async
    func commitCompletion(_ task: OneTask, done: Bool, restoringDue: Date?,
                          restoresDue: Bool, expected: ReminderCompletionReceipt?) throws
                          -> ReminderCompletionReceipt?
    func didPersistCompletion(_ task: OneTask, restoredDue: Bool)
}
```

Keep `ExternalEvent`/`SystemCalendar` and `EKSpan` in this temporary One boundary; they already contain SwiftUI/platform types. `ReminderCompletionReceipt` is a value with the current `Remote` fields (`id`, title/notes, done/doneAt/due, listID/title, flagged, repeatRule/repeats); supply a memberwise initializer, move the EKReminder conversion into the live adapter, and retain completion-fence comparison semantics. This avoids making development code construct an EKReminder to obtain an Undo receipt. For existential calls, add protocol-extension convenience overloads for current default arguments; they must delegate to `self`, never `.shared`.

Do **not** expose `nativeEvent`/`eventStore` through CalendarService. Native presentation uses a separate `@MainActor NativeCalendarPresenting` with `edit(identifier:start:end:fullOptions:onComplete:)` (matching `NativeEvents.edit`), and chooser creation owned by the feature composition closure. Live presenter receives `CalendarSync` explicitly and owns its delegate/watch task; Workbench presents its real local EventEditor against the session data, and a chooser using session calendar metadata. `CaptureUndo` uses `title/rename` above instead of extracting and writing EKEvent itself. Keep raw EventKit editor types inside the live implementation.

```swift
@MainActor package protocol AlarmService: AnyObject {
    var authorization: AlarmAuthorization { get }
    var states: [UUID: AlarmLiveState] { get }
    var isAvailable: Bool { get }
    func requestAuthorization() async
    func sync(_ context: ModelContext) async
    func stop(_ id: UUID)
    func watch(context: ModelContext) async
}
@MainActor package protocol TimerService: AnyObject {
    var timers: [RunningTimer] { get }
    var ringing: Set<UUID> { get }
    var log: PomodoroLog { get }
    var recents: [RecentTimer] { get }
    var sound: String { get set }
    var message: String? { get }
    func start(seconds: Int, label: String?, byHand: Bool) async -> RunningTimer?
    func pause(_ id: UUID)
    func resume(_ id: UUID)
    func cancel(_ id: UUID)
    func deleteRecent(id: String)
    func refresh()
    func watch() async
}
@MainActor package protocol NotificationService: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestPermission() async -> Bool
    func resync() async
}
```

Merge AlarmCenter's observation/watch responsibility and instance Ringer scheduling behind AlarmService; do not implement one by calling the static other. Timer and alarm live adapters share **one** explicit AlarmKit driver/ownership set, so Ringer never cancels timer IDs. That driver, not a feature, owns `AlarmManager.shared`. Live registration methods (`configure(container)`, notifications delegate assignment) belong to the live composition start, not the feature protocols or initializers. View reads must traverse observable instance properties; existential protocols need no `Observable` conformance. Bindings such as timer sound use `Binding(get:set:)` against the same retained instance, rather than creating another service.

### Required live constructors and start boundary

Use the existing classes as the live implementations of the contracts; do not add a second forwarding layer. Proposed constructors (new driver/storage capability types belong to the root contract commit):

```swift
CalendarSync.init(defaults: UserDefaults, runtime: PlannerRuntime,
                  makeEventStore: @escaping @MainActor () -> EKEventStore)
RemindersSync.init(defaults: UserDefaults, runtime: PlannerRuntime,
                   makeEventStore: @escaping @MainActor () -> EKEventStore,
                   recordActivity: @escaping @MainActor (ActivityEvent) -> Void)
// Lifecycle attachment is explicit, cancellable and scoped to this container:
RemindersSync.start(container: ModelContainer)
RemindersSync.stop()
Reminders.init(center: UNUserNotificationCenter, alarms: any AlarmService,
               runtime: PlannerRuntime)
Reminders.start(container: ModelContainer, actions: PlannerActions)
AlarmCenter.init(driver: any AlarmDriving, runtime: PlannerRuntime)
TimerController.init(driver: any AlarmDriving, persistence: any TimerPersistence,
                     runtime: PlannerRuntime, donate: @escaping @MainActor (Int, String?) async -> Void)
NativeEvents.init(calendar: CalendarSync,
                  presentingController: @escaping @MainActor () -> UIViewController?)
```

`AlarmDriving` is the one live AlarmKit owner used by both adapters: authorization/read/update streams plus schedule/stop/pause/resume/cancel, and a shared set of timer-owned IDs. Its exact schedule payload should preserve Ringer's existing configuration and TimerController's countdown configuration, rather than pretending they are the same alarm. This lower-level driver can remain model-independent in TodayPlatform; if its payload exposes AlarmKit types, it must not be declared in TodayCore. The development AlarmService/TimerService implement the higher-level protocols directly, so they never construct this driver. `TimerPersistence` loads/saves running timers, recents, sound and Pomodoro log using explicit defaults; the controller owns algorithms and state. Live initializer closures may lazily create a store only when requested; Workbench never constructs CalendarSync/RemindersSync, even with a supposedly disabled flag.

Notification delegate configuration needs PlannerActions, which depends on the already-created services. Construct all instances first, build actions second, attach delegates/observers third. Live start must be idempotent and complete before an intent handler mutates data. All service start tokens must have matching stop/cancellation ownership. `ActivityCenter` is constructed before RemindersSync's recording closure; neither initializer starts sync. Keep system access inside explicit startup or user action, not a property initializer that happens to run while building a view.

### Activity and actions: preserve real algorithms, remove static ownership

Make ActivityCenter an instance with `init(store: ActivityStore?, defaults: UserDefaults, runtime: PlannerRuntime)`; translate `settings`, `record`, `recordsChanges`, `summary`, `clear`, `prune`, `export` to instance methods. Retain the existing ActivityStore/Recorder implementations for the session memory store; this is real SQL/Undo behavior without a user database. Outbox import and UIKit background flush are explicit live-lifecycle collaborators, not effects performed by initialization. Keep a session-specific change notification/object; do not broadcast one session's changes to another.

Make Ledger an instance, retaining all current record/undo signatures and algorithms except their static qualification:

```swift
@MainActor package final class Ledger {
    package init(activity: ActivityCenter, reminders: any ReminderService,
                 runtime: PlannerRuntime)
    // Existing record/recordUndo/flush/protectedRefs/undo/clear signatures become instance methods.
    // pending, flushScheduled and its cancellable Task are instance-owned.
    package func dispose() // flush only this context, then cancel delayed work
}
```

ActivityCenter does not need a redundant protocol around a real selectable store. Its initializer must neither choose a path nor consult process arguments; file open/recovery is a live factory responsibility. Workbench exports must use an explicit session artifact destination or fail visibly; no silent success or user Activity file writes.

Every side-effectful free/static action gets **required narrow parameters**, no live defaults:

```swift
TaskActions.toggleDone(task, context: context, toast: toast,
                       reminders: reminders, ledger: ledger, runtime: runtime)
TaskActions.delete(task, context: context, toast: toast,
                   reminders: reminders, ledger: ledger, runtime: runtime)
TaskActions.setPlanned(task, to: start, context: context, ledger: ledger /* actor/channel/approval unchanged */)
ListActions.delete(list, keepingTasks: false, in: context, reminders: reminders, ledger: ledger)
AlarmActions.delete(alarm, context: context, toast: toast, alarms: alarms, ledger: ledger)
EntryDeletion.perform(entry, span: span, context: context, toast: toast,
                      calendar: calendar, reminders: reminders, alarms: alarms, ledger: ledger, runtime: runtime)
CaptureUndo.undo(itemRef: ref, entryID: id, title: title, context: context,
                 calendar: calendar, alarms: alarms, ledger: ledger)
CaptureUndo.rename(ref, to: title, in: context,
                   calendar: calendar, reminders: reminders, alarms: alarms)
CalendarEntries.make(in: interval, events: events, tasks: tasks, alarms: localAlarms,
                      calendarService: calendar, now: runtime.now(), calendar: runtime.calendar)
```

Propagate `reminders` through `TaskActions.persistCompletion` and both success/failure/Undo branches. Preserve remote-write-first, local-save-failure recovery and expected-receipt fencing. Undo closures capture the same injected service/ledger/runtime instances as the original action. Add `ledger` to ListActions mutations that record changes, GrantStore grant/revoke/setEnabled and LedgerMigration.run; add calendar/ledger/runtime to AutoPlan.run. Preserve the Changes-recording gate and AutonomyPolicy; no enabled grant can bypass it.

Move `Capture.insert/insertRecorded` out of `Models.swift` to a non-schema `CapturePersistence.swift` in One, requiring `ledger` and `runtime`; pass runtime now/calendar to `makeAlarm/makeEvent`. Return the existing `(PersistentIdentifier, LedgerItem)` after saving, preserving final ID behavior. Plain model fields and schema remain untouched. Pure `copy`, snapshot encoding and reference decoding stay pure. This extraction must not rename or move persistent declarations.

`AskNativeActions.applyChange/applyPlan/applyPlanAlways/applyTidy` keep their existing feedback/selection behavior, add ledger/reminder/runtime dependencies as needed, and use CalendarService instead of CalendarSync. `EveningReviewSheet` uses the same injected actions. Do not implement scene-specific copies of these algorithms. `DataReset.run` receives `reminders`, `ledger` and a typed inbox read/ack capability; session inbox is empty or fixture-backed. Preserve forget-link → clear inbox → drop receipts → save order.

### Feature construction and SwiftUI propagation

Keep required constructors already introduced in CalendarView, AskView, AlarmsView, TimerSection, SettingsView, ActivityView and ActivityDataView; generalize their concrete adapter parameters to the contracts above. Keep ActivityDataView's existing summary/clear/export/legacyRowCount closures. Supply them from the same ActivityCenter/Ledger/context instance; closures are already sufficient DI.

For nested planner rows/actions, use required typed environment objects **per capability**, not one global service bag:

```swift
// In One (model-bound bridge); no static shared or implicit live initializer.
@MainActor @Observable package final class PlannerActions {
    package init(calendar: any CalendarService, reminders: any ReminderService,
                 alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime)
    // Own real task/event/alarm action entry points; dispatch to the algorithms above.
}
// Feature entry constructor receives this object and installs .environment(actions).
// Rows: @Environment(PlannerActions.self) private var actions
// Missing injection fails at the boundary; no EnvironmentKey default constructs live services.
```

PlannerActions is a real action facade with defined methods (complete, delete, plan, entry deletion, capture Undo/rename), not a lookup API. Views needing calendar metadata receive `calendar: any CalendarService` explicitly; TimerRows receives TimerService explicitly. Environment propagation must cover sheets, navigation destinations, context menus and toast/shake Undo. Native UIHostingController roots require explicit reinjection; they do not inherit SwiftUI environment automatically. HomeView receives required feature factories/lifecycle dependencies and forwards them through Destinations, rather than reconstructing `.shared`.

Use capability constructors for remaining effect owners:

- `TravelTimes` use a `TravelTimeProviding` protocol with the current `seconds`, `label`, `widgetFields` signatures (explicit now); inject into Rows, ExternalEventRow, AskSuggestionContext, WidgetFeed. No live defaults.
- `SoundScreen(sound:preview:)`, with `SoundPreviewing.play(_ sound: AlarmSound)` / `stop()`. A development implementation records selection without AVAudioSession. Real SoundPreview keeps current playback.
- `HealthModel(source:store:runtime:timeout:)`, `HealthLineModel(source:runtime:)`; replace TodayClock reads in HealthView/model row/detail navigation. Keep HealthSelectionStore(session defaults, arguments: []) and current loader timeouts.
- `AskView(thread:calendar:now:actions:activity:intelligence:voice:onOpenTask:onOpenAlarm:)`; replace `@State VoiceInput()` with a supplied instance whose construction does not eagerly create an audio engine/recognizer. `VoiceInput` becomes observable session state plus injected `SpeechInputDriving.start(onTranscript:onState:) async` / `stop()`. Live driver owns engine/permissions; scripted driver lives only in development/test support.
- `AskIntelligence` in FeatureAsk: explicit MainActor closure fields matching current `Understander.parse`, `AICapture.propose/refineTitle`, `ChatResponse.respond`, `Editing.plan`, `AskSuggestionRanker.rank`, plus `prewarm` and availability. Preserve the exact current result types (currently feature-private; widen only to package). Live factory calls current model code; development factory returns scripted/domain-rule results and never creates Foundation Models sessions. All seven routes, availability checks and prewarm must use it. A single substituted capture closure leaves chat/edit/ranking live. Suggestion cache becomes session-owned.
- Supply `UserDefaults` explicitly to SearchMemory, preference readers, SmartListLayout mutation, FirstRun, shell restoration, timer/recents/log stores, travel cache and Activity settings. For SwiftUI `@AppStorage`, apply `.defaultAppStorage(defaults)` at each assembly root. Runtime calendar/locale must also reach parsing, recurrence, date formatting and model helpers: SwiftUI environment does not rewrite `Calendar.current` or `Date.now`.
- Inject `openSettings` / external URL actions and diagnostics export closures. Workbench uses inspectable local outcomes, never calls UIApplication.open, starts MetricKit or exports a live diagnostics buffer. Keep UIKit appearance adaptation window-scoped to Workbench's own window.

## Composition, first-launch identity and graph separation

Production-only composition owns a lazily initialized **typed live application instance**, not a feature-accessible service locator. Retain `OneStore.start()` as the idempotent external entry until callers migrate; it delegates store/start ownership to this instance. UI root and AppIntent adapters resolve this one instance at their framework boundary and immediately pass explicit dependencies to handlers. No feature/helper looks it up. AppIntent `init()` stays parameterless as required by the framework; `perform()` delegates to testable `AddReminderHandler(container:notifications:ledger:widgets:runtime:)`. Timer query and create/pause/resume/cancel handlers receive the same TimerService, even when the first invocation precedes app UI initialization. Intent donation and background registration occur only in live adapters. Do not create a second model container or a separately initialized timer ownership set.

Keep the `One` model module, schema list including retired models/receipts, `com.luworks.one`, App Group IDs, widget formats, AlarmKit UUIDs, preference keys and Siri/Shortcuts declarations unchanged. Preserve Add/Apply/Undo previews, Apple Calendar/Reminders conflict ordering, and native event editor save/dismiss behavior. App initialization currently starts diagnostics before OneStore; retain production sequencing deliberately, rather than inheriting Workbench setup.

Workbench SceneSession constructs: in-memory ModelContainer; isolated defaults; runtime; development Calendar/Reminder/Alarm/Timer implementations; memory ActivityCenter + Ledger; real PlannerActions; scripted Ask/speech/travel/sound; existing HealthSource fixture; local inbox/widget sink. Dependency instances are session-owned, no reconfiguration of live instances. `dispose()` cancels model/speech/watch/ledger tasks and observers before removing defaults. It must not let delayed tasks recreate the suite after disposal. Production executable links no development implementations or TodayTestSupport in either Debug or Release; Workbench/TodayMock own those separately. Do not rely on `#if DEBUG`, dead stripping or command-line state as graph proof. Production protocols and algorithms remain real production code, never fake shims.

## Registry discrepancy and migration ownership

The brief says 49 scenes; current `TodaySceneID` actually declares **50 IDs** (including `settings.delete`, `health.detail` and `health.picker`). A read-only extraction of explicit enum raw-value assignments counted 50; use all 50, without silently dropping one to match the brief. `SceneSession` throws when `.legacyEnvironment` has no prepare closure; retain that rejection until explicit assembly exists. A closure mutating singleton state is not an acceptable replacement. Once required constructors exist, replace `prepareLegacyEnvironment` with typed session construction; replace optional `applyChange/applyAlways/applyTidy` closures with required handlers that return the real action feedback before resolving cards; remove legacy capability only after reachability proof.

| Bounded follow-up lane | Exclusive files / call sites | Dependency and completion condition |
| --- | --- | --- |
| Root contract/model/config writer | `Package.swift`, Xcode/config/resources; new One service contracts/runtime decisions; `Models.swift`, persistent declarations; `OneStore.swift`, `App/OneApp.swift`, framework intent assembly | Ratify this proposal, keep model writer/reader bridge proof and live identity; own all graph edits. No other lane changes contracts ad hoc. |
| One services/actions | `CalendarSync`, `RemindersSync`, `Reminders`, `Ringer`, `AlarmCenter`, `TimerController`, `ActivityCenter`, `Ledger`, `TaskActions`, `ListActions`, `AlarmActions`, `EntryDeletion`, `CaptureUndo`, `DataReset`, `WidgetFeed`, `FirstRun`; root-created `CapturePersistence` | After contract commit, remove static state/calls and propagate through every Undo/callback. Coordinate `AppIntents`/`TimerIntents` handler edits with root. This lane owns no models/config or feature files. |
| Feature/planner consumers | `Sources/Features/**`, `Sources/TodayPlannerUI/**`, `Sources/TodayShell/**`; coordinate effect adapters in `TodayPlatform/{TravelTimes,AlarmSounds,TodayClock}` as a separate explicit file handoff | One owner per file. Generalize existing constructors, route all direct/inferred globals, retain actual UI algorithms, eliminate constructor-time/global time/defaults leaks. Ask action extraction stays here, not in Workbench. |
| Development assembly | `Development/{SceneCatalog,WorkbenchApp}.swift`, development-only service implementations under root-approved support target | Adapt **all** constructor calls and nested destinations. Use `SettingsView(selection:)` already present for apple/today/smartLists/ai/about instead of fake sections; update stale registry blockers only after these calls are wired. Do not edit service/model/config contracts. |
| Validation/evidence | root-assigned test/fixture files and compact QA evidence only | Prove graph, isolation and behavior; never infer success from an in-memory container or screenshot alone. No simulator/build ownership assumed by this research. |

Coverage groups: Today/review (2); Calendar week/month/year/key/sources/editor (6); Reminders overview, five smart lists, list, editor, quick add, list editor (10); Clock alarms/editor/sound/world/city/stopwatch/timer (7); Ask plus five cards (6); Activity/Search (2); Settings plus thirteen subsections (14); Health/detail/picker (3). The registry total is 50. Use `TodaySceneID.allCases` as the authoritative manifest, not a second handwritten list. In particular, `settings.calendar` and `settings.alarms` currently omit legacy capability despite direct Ringer/first-run effects, so current capability labels cannot certify isolation.

## Required proof and remaining risks

1. Static/graph proof: zero live singleton references (including inferred `.shared`) in Workbench-reachable features/actions; raw EventKit/AlarmKit/UN/AVAudioSession/HealthKit/App Group access only in explicitly selected live adapters. Check product dependency closure and Release archive membership for absence of TodayTestSupport/development implementations. A search alone does not establish runtime isolation.
2. Session proof: enumerate all 50 current IDs and every *supported* scenario. Construct/render independently with fixed now/calendar/locale/seed; retain rejections for unsupported loading/error/denied/revoked until production state seams actually support them. Invoke effectful controls and Undo, nested sheets and settings deletion against session spies. Assert no live factories, user database paths, App Group reads/writes, permission APIs, donation or scheduling were invoked. Compare two simultaneous session ledgers/defaults/timers and one session after disposal. Deterministic screenshots require replacing date-based native timer text in development rendering, plus stable fixture IDs/tie-break ordering; a fixed SwiftUI calendar environment alone is insufficient.
3. Behavioral proof: logic tests for completion accepted remotely/local save fails/Undo expected receipt; calendar this-occurrence/series and read-only deletion; shared AlarmKit ownership of timers; Add/Apply/Undo and paused Changes → no automatic plan. Follow with focused native UI journeys under the root's exclusive runner. No broad suite/build loop is requested here.
4. Identity proof before any bridge exit: baseline real persisted store writer and reconstructed reader preserve model IDs/schema/counts; no package move/rename of persistent declarations. One compatibility protocols can exit only after model-bound operations become domain snapshots/commands with explicit repository transactions, features no longer depend on those helpers, and reviewed store migration passes writer/reader proof. An empty forwarding module is not an exit.

Original risks to carry forward: observation can silently stop when replacing concrete `@State` objects with existentials; constructor injection does not remove static Ledger pending state; native UIKit roots can lose environment; notification/save observers can cross-contaminate containers; delayed tasks can outlive scenes; timer donation/query can initialize before UI; a different session clock can change whether capture becomes an alarm; search/caches/defaults can leak despite `.defaultAppStorage`; native event polling/dismissal can regress if refactored casually; memory Activity still needs the same recording/autonomy gates. Temporary EKSpan/Color/model-bound One contracts are deliberate debt, not a claim that Core is now independent or Workbench is already isolated.

Research validation performed: read-only source inspection and registry/call-site inventory only. No compile, logic test, UI test, persistence migration or physical-device acceptance is claimed. The root should record the ratified contract and schedule implementation as a new bounded task.

## Root ratification and first implementation boundary

The integration writer has added `PlannerRuntime` and the model-bound Calendar/NativeCalendar/Reminder/Alarm/Timer/Notification contracts. Root split unchanged LedgerEntry/AIGrant declarations into LedgerModels.swift and Capture conversion/action helpers into CapturePersistence.swift; every persistent declaration stays in module One with unchanged fields and initializers. These source-file moves do not authorize schema edits.

The service/action lane may convert Ledger to a retained instance, remove static service calls from One algorithms, and implement a real `@MainActor @Observable package final class PlannerActions` with required `init(calendar: any CalendarService, reminders: any ReminderService, alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime)`. Its complete/delete/plan/capture entry points must call the existing algorithms with these dependencies, preserving all Undo closures. Feature constructors require this action object; nested controls obtain this specific action capability through SwiftUI environment, without a live default or lookup API. Typed live assembly remains root-owned at OneStore/AppIntents/App and HomeView framework boundaries. No child edits Models.swift, LedgerModels.swift, OneStore.swift, AppIntents.swift, TimerIntents.swift, project/package/config, or ServiceContracts.swift. Report required signature corrections to the root instead.

ActivityCenter receives an explicit store/defaults/runtime and never chooses a path in its initializer. The live factory retains existing disk identity and explicit outbox/background lifecycle. Ledger's pending work and cancellation become instance-owned. Existing static APIs may not survive as a feature-accessible live locator. System adapter construction and startup remain separate. Development fake implementations remain outside production dependencies. Travel/sound/Ask/clock/defaults seams are subsequent required consumer work; neither this contract nor partial conversion establishes Workbench isolation.

## Consumer contract ratification

Every real feature constructor retains its existing behavior inputs and appends required narrow dependencies: `actions: PlannerActions` for mutations, `calendar: any CalendarService`, `reminders: any ReminderService`, `alarms: any AlarmService`, `timers: any TimerService`, `notifications: any NotificationService`, `travel: any TravelTimeProviding`, and `soundPreview: any SoundPreviewing` only where actually needed. Keep existing parameter labels where possible and report exact final signatures. Never default to live dependencies. Nested model-bound controls use `@Environment(PlannerActions.self)` for the specific action capability and `@Environment(PlannerPresentation.self)` for required session clock/calendar/locale/defaults; entry points install them, sheets inherit them, UIKit roots reinject them. No universal service bag or lookup API is introduced. `PlannerPresentation` carries display/preferences only. Preference helper calls use its explicit defaults and date/recurrence calls use its calendar/time.

TravelTimeProviding is a Foundation-value capability in TodayPlatform, reusing the extension-safe TravelPlace value from TodayShared without adding a Core dependency; SoundPreviewing is a package capability alongside its platform type. Live constructors and lifecycle are selected at root, never from a feature. Native Calendar UI is available solely through NativeCalendarService; all callbacks retain the supplied adapter, never reconstruct shared. Production Alarm/Timer adapters share the same root-owned Ringer. Existing feature-specific Ask intelligence and speech capability construction may be implemented by its owner with required closures/driver protocols covering every current model route; fake implementations remain Development-only. Scene assembly is adapted only after consumer signatures are integrated.

## Development implementation boundary

TodayTestSupport may now depend on One/Data/Platform solely to implement required model-bound service contracts under iOS. It remains absent from the production dependency closure. Its new `PlannerTestServices(container:defaults:runtime:arguments:)` owns fake Calendar/Reminder/Alarm/Timer/Notification/Travel/Sound capabilities, a real memory ActivityStore/ActivityCenter/Ledger and real PlannerActions. Every factory input is explicit; no live adapter construction, shared service lookup, standard defaults, EventKit/AlarmKit/AV/Health permission calls, App Group IO or networking is allowed. Fake dependencies model inspectable local outcomes and use existing Core timer/recurrence/value rules. They never claim external atomic writes or real system acceptance. Root constructs the runtime and supplies CLI arguments only from Mock/Workbench assembly. Health and Ask remain their existing explicit capabilities.
