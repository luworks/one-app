# Remaining iOS module topology: implementation map

Research base: `20916054ac6bb6a20cd6536396a03b44aed74de2`, 2026-10-18. Scope: static source diagnosis and this document only. No production/config/model changes, compiler invocation, simulator or device run. Read `AGENTS.md`, `CLAUDE.md`, `ios/README.md`, `architecture.md` and `migration-plan.md` before analysis. AI approval, fixed events, planned time versus deadline, explicit task completion, overdue visibility, local data and existing Undo/Activity semantics remain constraints.

The root is integrating the real Core/Shared/Data/Platform/DesignSystem/Clock/Health products. This checkout has extracted sources but its `ios/Package.swift` still describes the old OneLogic whitelist. Do not implement against that obsolete manifest or re-add extracted originals. Read-only inspection of the root checkout's manifest and existing build file lists confirms the linked products and their source paths; it does not establish acceptance of the proposed next graph.

## Decision and dependency graph

Finish extraction of **all real screens now**. Retain an explicitly bounded `One` compatibility library for installed model and intent identities plus model-bound shared operations. It must contain no Today, Calendar, Reminders, Ask, Clock, Settings, Activity, Search or Shell screen implementation. A small `TodayPlannerUI` target owns actual reusable model-bound rows and gesture modifiers used by several features. This is justified shared implementation, not an empty wrapper. Editors belong to their feature; opening an editor crosses a constructor-supplied action closure, not a feature import.

Edges below mean “imports/depends on”; standard Apple SDKs are omitted. List direct dependencies explicitly in the manifest when their types are named, even if another dependency also imports them.

| Target | Direct dependency set after this pass | Actual owned implementation |
| --- | --- | --- |
| TodayCore | none | Existing domain values/policies/rules; add the six existing SettingsKey constants; smart-list identity/order rules after separating SwiftUI color |
| TodayShared | preserve root's current extension-safe graph | Snapshot, inbox, outbox and speech formats; **not** One's AlarmMeta or model-bound adapters |
| TodayData | TodayCore, TodayShared | Existing Activity SQLite/recorder/export/import/value types |
| TodayPlatform | TodayCore, TodayShared | Existing HealthKit, production clock and measured trace hooks; add model-free travel, sound playback and appearance adapters as described below; never import One |
| TodayDesignSystem | TodayCore | Existing components plus model-free row chrome, shared capture-card presentation and reusable controls |
| One | TodayCore, TodayShared, TodayData, TodayPlatform | Nine persistent models, model-bound calendar/reminder/alarm/timer services, shared mutations, ledger/grants, store opening, Siri/AlarmKit identity bridge; **no feature dependency** |
| TodayPlannerUI | One, TodayCore, TodayDesignSystem, TodayPlatform | Real TaskRow/EventRow/ExternalEventRow/AlarmMarkRow, EntryActions/dialog and UndoToastView; model-bound list deletion confirmation if reused |
| FeatureReminders | One, TodayCore, TodayDesignSystem, TodayPlatform, TodayPlannerUI | RemindersView, ReminderListScreen, QuickReminderSheet, TaskEditor, ListEditor |
| FeatureCalendar | One, TodayCore, TodayDesignSystem, TodayPlatform, TodayPlannerUI | CalendarView and Week/Month/Year implementation, EventEditor, calendar chooser UI and Year settings UI |
| FeatureToday | One, TodayCore, TodayDesignSystem, TodayPlatform, TodayPlannerUI, FeatureHealth | DayAgenda, evening review and health summary presentation, Today timer rows |
| FeatureAsk | One, TodayCore, TodayShared, TodayData, TodayDesignSystem, TodayPlatform | AskView, capture batch UI/state, routing/orchestration and proposal cards; no editor imports |
| FeatureClock | One, TodayCore, TodayDesignSystem, TodayPlatform | Existing World Clock/Stopwatch plus AlarmsView, AlarmEditor and Timer screen implementations |
| FeatureSettings | One, TodayCore, TodayData, TodayDesignSystem, TodayPlatform | Settings and its option sections, grants UI and destructive confirmations; destination builders supplied from composition |
| FeatureActivity | One, TodayCore, TodayData, TodayDesignSystem, TodayPlatform | ActivityView, ActivityDataView and share/export UI |
| FeatureSearch | One, TodayCore, TodayDesignSystem, TodayPlatform | SearchView, result rendering and recents; no editor imports |
| TodayShell | One, TodayCore, TodayShared, TodayData, TodayDesignSystem, TodayPlatform, TodayPlannerUI, all feature products | Actual HomeView, Sidebar, Drawer, cross-feature navigation, destination assembly and app-session lifecycle |
| Xcode app entry (module TodayApp) | TodayShell, One, TodayCore, TodayPlatform (and direct types it constructs) | @main, UIApplicationDelegate adaptor, root modelContainer, appearance, capabilities/resources only |

This graph is acyclic: Core/Shared -> Data/Platform/DesignSystem -> One -> PlannerUI -> independent features -> Shell -> executable (arrows here mean construction order). FeatureToday can depend on the existing FeatureHealth because Health has no reverse edge. No other feature-to-feature dependency is needed. FeatureClock gains One for real alarms/timers while its existing world-clock/stopwatch implementations remain intact.

`One` is intentionally wider than a model-only target in this pass: CalendarSync/RemindersSync/Ledger/TaskActions and TimerController/AppIntents already form shared model-bound closures. Moving their screen callers out is practical now; distributing those operations across features creates cycles or changes identity. This is a documented compatibility bridge, not permission to leave more screens in One.

## Exact source ownership and minimum splits

Paths in this section are relative to `ios/One/` unless prefixed. Line numbers refer to the research base; use declaration boundaries when root integration has shifted them. Move declarations once, delete original production membership, preserve code bodies unless an interface seam below requires adjustment. Do not copy production sources or create an app source whitelist.

### Shared values, presentation and model bridge

| Source/chunk | Destination and required cut |
| --- | --- |
| `Models.swift:5–198` | One: OneTask and OneEvent, every stored property/default/encoded representation unchanged. Pure computed methods may remain here when they only use Core. |
| `Models.swift:199–271` (`extension Capture`) | Split into One/CapturePersistence.swift. Keep `makeTask`, `makeAlarm`, `makeEvent`, `insert`, `insertRecorded` together for this pass: insertion depends on LedgerItem/Ledger, so these are **not Core methods**. Export them from One. |
| `Models.swift:272+` | One/ShareImportReceipt.swift, unchanged receipt identity and fields. |
| `OneAlarm.swift`, `Habits.swift`, `ChatThread.swift` | One model declarations. ChatThread needs Core ChatMessage/StoredCard and SwiftData PersistentIdentifier, never FeatureAsk. OneAlarm's encoded weekday/schedule fields and Habit stay unchanged. |
| `OneList.swift` | OneList and ReminderPalette in One for this pass. `OneList.color` uses the palette, and RemindersSync uses it to quantize imported colors and write EKCalendar.cgColor (lines 320/436/466). It is shared persistence-adapter presentation data, not a Reminders screen. Moving it to DesignSystem without also changing these calls leaves One dependent on UI styling. Keep color/symbol primitive stored fields unchanged; a later value-only palette representation can remove SwiftUI from model helpers. |
| `Ledger.swift:8–84` | One/LedgerModels.swift: LedgerEntry, its `legacyRow` mapping and AIGrant. The mapping names TodayData.LegacyLedgerRow, hence One explicitly imports Data. Do not move LegacyLedgerRow into the model file. |
| `Ledger.swift:85–377` | One: Ledger, LedgerMigration, GrantStore. Shared by mutations, settings, Activity, Ask and bootstrap. Keep snapshot/undo/import/prune/record behavior together. |
| `Ledger.swift:378+` | One/AutoPlan.swift. It reads One models, CalendarSync and Activity recording policy; it is not a FeatureToday screen dependency. Inject clock/calendar/calendar-reading instance instead of reaching into DayAgenda. |
| `TaskActions.swift:1–85` | One/UndoToast.swift: existing MainActor observable undo state, UndoManager behavior and timer cancellation token. This is action feedback, not a feature view model. |
| `TaskActions.swift:86…before UndoToastView` | One/TaskActions.swift. Keep remote-acceptance/local-save/reconciliation/Undo ordering intact. |
| `TaskActions.swift` (`UndoToastView`) | TodayPlannerUI: renderer consuming injected One.UndoToast. Shell supplies that same instance to rows, sheets and sidebar. |
| `ListActions.swift`, `CaptureUndo.swift`, `ChatAutoArchive.swift` | One shared model operations. CaptureUndo is used by Ask but operates on persisted model IDs and ledger; no FeatureAsk types in its exported signature. |
| `SettingsView.swift:7–15` (`SettingsKey`) | TodayCore, same six key strings. Stops TravelTimes, DayAgenda, Calendar, ChatAutoArchive and Health from importing Settings. Do not create replacement keys. |
| `DayAgenda.swift:384–398` (`TodayClock`) | Already extracted by root into TodayPlatform/TodayClock.swift. Delete this original when applying the root movement; use that single implementation, including `-uiTestingNow`. |
| `CalendarEntries.swift:6–124` | One/CalendarEntries.swift: CalEntry and shared merger used by Today, Calendar and widget operations. These carry OneTask/OneEvent/OneAlarm references and SwiftUI Color, so they do not belong in Core. `make` gains explicit `sync: CalendarSync` and `now: Date` arguments. |
| `CalendarEntries.swift:126–157` (`OpenedEntry`) | TodayShell/PlannerDestination.swift or One's small public destination value if feature callbacks need it. Prefer the latter for `.system`, `.editSystem`, `.local`, `.task`, `.alarm`, `.new(start:end:)`; **no stored view builders** inside it. |
| `CalendarEntries.swift:159+` (`EventTint`) | TodayDesignSystem; only adaptive SwiftUI/UIColor rendering, no models. |

### Rows and capture UI: do not move Rows.swift wholesale

| Chunk | Owner/API consequence |
| --- | --- |
| `Rows.swift:4–63`: TimeColumn, TitleDetail, TravelLine, CalendarBar | TodayDesignSystem; value inputs only. TitleDetail's generic view-builder initializer must be public. |
| `Rows.swift:64–143`: EventRow | TodayPlannerUI. Replace internal EventEditor sheet with required `open: (OneEvent) -> Void`; retain calendar entry deletion/dialog binding, travel and accessibility. |
| `Rows.swift:144–295`: TaskRow | TodayPlannerUI. Keep every option (`showsTime`, `time`, `showsList`, `compact`, `suggested`, `agendaDay`). Replace local editor sheet with required `open: (OneTask) -> Void`; actions use the supplied action handler/One mutation service and toast. Do not lose the completion-circle distinction or Plan Undo. |
| `Rows.swift:296–317`: AlarmMarkRow | TodayPlannerUI; model-bound display shared with Today; caller supplies opening action when needed. |
| `Rows.swift:318–332`: NowRow | TodayDesignSystem, Date only. |
| `Rows.swift:333–447` + `497+`: CaptureCard, DecidedCardLabel, CaptureTitleButton, CaptureTitleEditor | TodayDesignSystem. The private title editor travels with its public button; CaptureCard uses Core.Capture/CardStatus and callbacks only. |
| `CaptureStack.swift:210+`: CardFooter, ListMenu | TodayDesignSystem alongside CaptureCard, **in the same move**; otherwise Rows <-> CaptureStack becomes a cross-target cycle. |
| `CaptureStack.swift:5–209`: CaptureProposal, CaptureStack, CompactCaptureRow | FeatureAsk. CaptureProposal has strings/UUIDs/Core values and StoredCard conversion; it must not be pulled into One solely to compile CaptureCard. |
| `Rows.swift:448–496`: WeekStrip | TodayDesignSystem (Binding<Date>, Core CalendarMath, no persistence). |
| `CalendarSync.swift:428–483`: ExternalEventRow | TodayPlannerUI, with explicit calendar/travel/open action inputs. Adapter no longer imports row chrome or EntryActions. |

### Shared system/actions/intent closure in One

| Source/chunk | Owner/API consequence |
| --- | --- |
| `CalendarSync.swift:7–425`: ExternalEvent, SystemCalendar, CalendarSync | One for this bounded pass. Its save/delete/systemCopy/removedMirrors methods name OneEvent; Core year/calendar rules stay imported. ExternalEvent/SystemCalendar retain existing Color and TravelPlace inputs. Constructor accepts event store/preferences/arguments rather than features using `.shared`. |
| `CalendarSync.swift:486–740`: NativeEvents and ExistingCalendarEventEditor | One native-system editor bridge. ExistingCalendarEventEditor is a substantive system compatibility wrapper, not a feature's local EventEditor. Keep together because native deletion/presentation behavior depends on this wrapper. No feature/row import. |
| `CalendarSync.swift:742–790`: NativeEventSheet/NativeEventEditor | One native-system bridge, export the entry initializers. Multiple features/composition use it; it has no dependency on FeatureCalendar. |
| `CalendarSync.swift:792–825`: NativeCalendarChooser | FeatureCalendar presentation; receives the calendar adapter/store explicitly. Settings receives its destination from Shell. |
| `CalendarSync.swift:826+`: EventSpeech | TodayCore if it remains Foundation-only. CalEntry and system row both call it; never import FeatureCalendar from One. |
| `RemindersSync.swift:1–659` | One (EventKit <-> SwiftData synchronization and accepted completion state). Keep current conflict fence, delete cap and persistence semantics. |
| `RemindersSync.swift:660–762` DEBUG test operation extension | One DEBUG support initially: calls TaskActions, producing a real reverse edge if sync is moved below actions. May move to app test bootstrap only with an explicit command hook; not to production FeatureReminders. |
| `RemindersSync.swift:763+` SyncDumpProbe | TodayShell DEBUG UI probe with injected sync, preserving accessibility identifier. |
| `Reminders.swift` | One local notification bridge. Its delegate fetches/mutates persisted models, uses TaskActions and resyncs; the filename does not mean FeatureReminders owns it. Split Foundation-only ReminderOffset into Core if CaptureCard/editor consumers still need it. |
| `Ringer.swift`, `AlarmCenter.swift` | One AlarmKit/model reconciliation. AlarmCenter watches ModelContext and alarm records; Ringer's reconcile must retain timer IDs when canceling leftovers. |
| `TimerController.swift`, `TimerIntents.swift`, `AppIntents.swift` | One. Keep TimerEntity, schema intents, intent donation/support and controller together now; TimerController.configuration refers directly to TimerEntity and AlarmScheduler.Meta. All AppIntent declarations keep module One. |
| `Shared/AlarmActivity.swift` | Preserve app-side One.AlarmMeta and Pause/Resume/StopAlarmIntent declarations in One; preserve existing widget-side module ownership (TodayWidgets) and wire types. It is a separately compiled identity-sensitive source already, **not** permission to copy it into TodayShared. Do not link app-process persistence into extensions. |
| `AlarmSounds.swift` | TodayPlatform for AlarmSound/SoundPreview (no model reference); retain main-bundle CAF lookup and names. Main app still bundles Sounds. If moved to package resources later, explicitly change bundle access with playback/ringing evidence. |
| `TravelTimes.swift` | TodayPlatform with shared SettingsKey moved to Core; uses TravelPlace/TravelTime from Shared, no models. Preserve location request/cache policy. |
| `ActivityCenter.swift:1–153` | One activity process facade (it clears legacy LedgerEntry through ModelContext); Data stays model-independent. Expose store/recording/flush/prune/export entry points needed by features. |
| `ActivityCenter.swift:154+` ActivityFileSheet | FeatureActivity, real export sheet UI. |
| `WidgetFeed.swift` | One process/widget adapter. Used by Siri, background refresh and app lifecycle; depends on One models, CalendarSync/RemindersSync/TravelTimes, never on a feature. |
| `FirstRun.swift` | One permission coordination; views receive explicit async permission actions or instance access. It does not import screens. |
| `Appearance.swift` | TodayPlatform for the UIKit root/trait modifier and Appearance extensions; AppearanceSettingsRow moves FeatureSettings because it uses DesignSystem.MenuChoiceRow. This avoids adding a Platform -> DesignSystem edge. Core already owns AppearanceLogic. Do not leave `.appearanceRoot` in TodayShell if the entry uses it. |
| `AIResponseTrace.swift` | TodayPlatform for diagnostic trace/state/content probe; history View may travel with FeatureAsk or stay Platform if it is generic trace UI. No Ask state type in Platform signature. |
| `LaunchTimer.swift` | TodayPlatform; sanitize existing instrumentation, preserve cold-start hooks. |
| `HealthSampleSeries.swift` | Compare with extracted Core health series implementation; retain one authoritative implementation in Core, not a second app copy. |

### Features own complete journeys

| Feature | Exact source closure and splits |
| --- | --- |
| Today | DayAgenda excluding TodayClock; DayItems/DayEntry/TimelineItem stay feature-local; ReviewRequest/ReviewPeek and EveningReviewSheet stay together here. `DayAgenda.items` planning/ordering remains intact. TimerRows.swift splits: TimerLine + TodayTimerRows here, receiving One.TimerController and openTimer closure; timer swipe buttons can live in DesignSystem because they only take booleans/actions. TodayHealthLine: summary/model here, constructor-injected source/clock; HealthDetailSheet and HealthMetricsLink move to FeatureHealth or are replaced by Shell-supplied builders. Today does not import Clock for its timer rows. |
| Calendar | CalendarView including MonthView/MonthPage/YearView/MiniMonth/WeekView/WeekPage/SlotPressView/DraggableTaskBlock/DayTint/CalendarIDs; retain occupied geometry and hit testing as one unit. Editors.swift:205+ EventEditor. YearMarksView.swift split Year UI/key/settings from general style only if needed; Settings receives YearHolidaysSettingsView builder. CalendarsSheet stays here and uses the public NativeCalendarChooser. Replace task/alarm editor construction with open actions. |
| Reminders | RemindersView including smart-pill/list presentation, ReminderListScreen including inline NewReminderRow, QuickReminderSheet, Editors.swift:6–204 TaskEditor, ListEditor.swift. Split ListGlyph/reminderCountText into DesignSystem, and shared PendingListDeletion + delete alert into PlannerUI if reused outside Reminders. SmartList/ReminderTarget/SmartListLayout currently precede RemindersView: move SmartList identity/title/symbol and SmartListLayout (keys/decoding/ordering) to Core; move `SmartList.includes(_ task: OneTask, calendar:)` into a FeatureReminders extension because it names a persisted model; move `SmartList.color` into DesignSystem. ReminderTarget stays public in FeatureReminders (it carries PersistentIdentifier). Avoid a Settings -> Reminders edge for a handful of constants. |
| Ask | AskView (including MessageView/TidyRow/TidyCard/PlanCard/PendingChange/UndoRow/ChangeCard/ChoiceBar), remaining CaptureStack, AskSuggestionContext/List/Ranker, ChatResponse, EditCandidates, Understanding, AICapture, Editing, VoiceInput. EditCandidates needs injected CalendarSync audience reader. AICapture/Understanding/Editing/Ranker are model-inference implementations used by Ask, so keep here rather than manufacturing generic Platform services. Persisted ChatThread/CaptureUndo remain One. Editors opened from cards route via callbacks. Drawer.swift mechanics should be moved to DesignSystem (generic) or injected for Ask back gesture; never import Shell to obtain DrawerDrag. |
| Clock | Existing linked WorldClockView/StopwatchView; add AlarmsView and ClockSectionBar/SectionTitle/ItemAlarmRow; AlarmEditor.swift except AlarmActions and generic helpers; TimerSection/TimerPicker/TimerCard. AlarmEditor.swift:395+ AlarmActions moves One, `alarmTitle` at 387 is a shared model helper in One, `switchOnRowMargin` View extension at 4 and Card/Row/DayCircle presentation stay feature-private; `plainRow` is the private AlarmsView extension at line 216 and travels with it. SoundScreen is Clock UI. TimerSection receives controller and SoundPreview explicitly; One owns no screen. |
| Settings | SettingsView except SettingsKey/DataReset; SettingsRows.swift's five concrete sections; AutomaticChangesToggle/AutomaticChangesView/DeleteDataConfirmation stay here. DataReset.swift moves One (shared destructive mutation, unlink-first behavior). Inject destinations for calendar chooser, Year holidays, Health metrics and Activity data. Retain double confirmation in UI and same reset operation. Smart-list settings use extracted shared identities/order/display options, not RemindersView. |
| Activity | ActivityView including ActivityRow, ActivityDataView, ActivityFileSheet. Both screen and data page use injected ActivityCenter/Ledger actions, preserve cursor paging/150-row boundary and export path. ActivityDataView is no longer compiled into One. |
| Search | SearchView including ResultRow/Recents and scope/quick-search state. Replace `.sheet` switch at 148–154 with supplied open handler. Query scopes, limits and all-system-calendar search stay here. No Search enum/type may leak into TimerController: lexical `SearchView.swift` references from timer files can be comments/common names, not evidence for a real dependency. |

## Confirmed closures and cycle cuts

A lexical declaration/token graph over remaining `ios/One/*.swift` produces one very large apparent SCC. It over-approximates comments, strings, common names and DEBUG code, so it is **not a compiler-derived dependency graph**. The following smaller cycles were checked against actual call/type declarations and are the implementation blockers:

1. **Rows <-> CaptureStack:** CaptureStack builds CaptureCard; CaptureCard builds CardFooter/ListMenu. Move the latter value-only components together into DesignSystem. Keep CaptureProposal and Ask state out of shared row code.
2. **CalendarSync -> ExternalEventRow -> CalEntry/EntryActions -> CalendarSync:** one file combines adapter, row, native editor and chooser. Split the row and chooser; CalEntry/merger plus model-bound native bridge stay One. TodayPlannerUI depends downward on One only.
3. **Models -> Capture.insertRecorded -> Ledger -> SwiftData models:** One owns this complete model/action closure. Moving Capture persistence to Core creates Core -> One -> Core. Moving Ledger into FeatureActivity creates One -> Activity -> One. Neither is valid.
4. **TaskActions -> RemindersSync -> DEBUG runTestOperations -> TaskActions:** keep common operations together in One for this pass. Preserve remote accepted completion and failed local save reconciliation; do not hide the DEBUG edge by only checking Release.
5. **TimerController -> TimerEntity/TimerIntentSupport -> TimerController:** real API edge, not just donation: `EntityIdentifier(for: TimerEntity.self, identifier: timer.id)` is built in the AlarmKit configuration. Together with `AlarmScheduler.Meta` this closes the alarm/intent bridge in One. Do not put TimerController in FeatureClock or a Platform target that imports One.
6. **AppIntents -> OneStore.start -> app bootstrap -> HomeView -> every feature -> One:** split OneApp from OneStore. OneStore must not depend on HomeView, PreviewFixtures, HealthDebugSeed or feature assembly. It opens/configures common persisted services even for Siri-first process startup; app-only seeds/hooks run in app/Shell bootstrap.
7. **DayAgenda -> CalendarEntries.make -> TodayClock in DayAgenda**, plus **Ledger.AutoPlan -> TodayClock** and **AlarmEditor -> TodayClock**: use the already linked TodayPlatform clock; remove all lower -> FeatureToday edges.
8. **Settings -> Calendar/Reminders/Health/Activity** while those screens read SettingsKey: move six keys to Core; supply Settings destination builders and shared smart-list preference values. Settings owns actual option controls, not those feature implementations.
9. **Calendar/Ask/Search -> task and alarm editors** and **TaskRow -> TaskEditor**: remove editor construction from shared rows and unrelated features. Constructor actions let Shell present feature-owned editors. Event editing of Apple events remains the single native-system presenter because per-row sheets previously broke deletion and selected-event identity.
10. **FeatureHealth migration seam:** old TodayHealthLine calls `HealthView()` and `HealthSources.current()`, but linked Health requires `HealthView(model:)` with `HealthModel(source:store:timeout:)`. Shell constructs one real HealthModel/source, passes it to the sheet/metrics destination and injects the same source/selection/time into the summary loader. Do not restore removed factory globals or fake data to compile the old wrapper.

## Concrete constructor/action contracts

These are implementation signatures to introduce, not APIs claimed to exist today. Mark view initializers and `body` public; keep local subviews and implementation state private. All model references and closures below stay on MainActor. Do not make ModelContext Sendable or send PersistentModel instances to a background actor.

```swift
// One: model-bound route, used only as a value passed upward.
public enum PlannerDestination {
    case task(OneTask)
    case event(OneEvent)
    case alarm(OneAlarm)
    case systemEvent(identifier: String, occurrence: Date?, edit: Bool)
    case newEvent(start: Date, end: Date?)
}

// TodayPlannerUI: real shared row behavior, no editor import.
@MainActor public init(
    task: OneTask, showsTime: Bool = false, time: Date? = nil,
    showsList: Bool = true, compact: Bool = false,
    suggested: Date? = nil, agendaDay: Date? = nil,
    actions: TaskActionHandler, open: @escaping (OneTask) -> Void
)
// TaskActionHandler is a focused constructor-supplied value of closures,
// not a registry: toggleDone, delete, setPlanned and showUndo/showNotice.
// It captures the correct ModelContext/toast/RemindersSync/Ledger at assembly.

// FeatureCalendar retains its day/mode state contract.
@MainActor public init(
    day: Binding<Date>, mode: Binding<Mode>, calendar: CalendarSync,
    open: @escaping (PlannerDestination) -> Void,
    onOpenDay: @escaping (Date) -> Void
)
// Existing CalendarView.create resolves native versus local using calendar;
// local creation calls open(.newEvent(...)); no editor sheet in CalendarView.

// FeatureToday keeps actual day rendering and owns its local review state.
@MainActor public init(
    day: Binding<Date>, showsWeekStrip: Bool,
    calendar: CalendarSync, timers: TimerController,
    healthSource: any HealthSource, now: @escaping () -> Date,
    open: @escaping (PlannerDestination) -> Void,
    openHealth: @escaping () -> Void, openTimer: @escaping () -> Void
)

// FeatureSearch opens typed results through the same route value.
@MainActor public init(calendar: CalendarSync,
                      open: @escaping (PlannerDestination) -> Void)

// FeatureAsk: retain existing init(thread:) restoration and onAdded/onBack/
// onOpenDay semantics, add explicit adapters and item opening.
@MainActor public init(
    thread: ChatThread?, calendar: CalendarSync,
    now: @escaping () -> Date,
    open: @escaping (PlannerDestination) -> Void,
    onAdded: @escaping (Capture) -> Void,
    onBack: @escaping (Bool) -> Void,
    onOpenDay: @escaping (Date) -> Void
)
```

Complete the same seam for FeatureReminders (`init(isPushed:path:sync:actions:)`), FeatureClock (`init(section:alarms:timers:showUndo:)`) and editors (`TaskEditor(task:actions:)`, `EventEditor(event:day:start:end:calendar:)`, `AlarmEditor(alarm:actions:)`). Preserve existing defaulted editing values, and add explicit public initializers rather than relying on internal synthesized memberwise initializers. Existing `@Query` is valid inside package screens during this bridge; Shell supplies `.modelContainer` above every sheet and uses that container's main context for action closures.

Settings needs four typed ViewBuilder inputs: `calendars`, `holidays`, `healthMetrics`, `activityData`, plus explicit calendar/reminder permission actions and `reset: () -> Void`. Use generic destination parameters on the concrete SettingsView or small concrete destination factories at Shell; do not put AnyView factories in One or a global dictionary of services. Activity receives store/ledger access and `undo: (LedgerItem) -> Void`; Activity data receives clear/export actions. A destination closure does not substitute for moving the real destination implementation into its target.

NativeEvents receives its actual CalendarSync at construction (or on its explicit methods); CalendarSync no longer reads feature state. TimerController takes a timer-donation closure only if/when its intent identity coupling is separately removed; for this pass both stay One and the constructor can accept its AlarmKit client/store/preferences/clock. Do not introduce a static “configure all services” API masquerading as injection.

Closure propagation is finite: Shell -> DayAgenda -> TaskRow/EventRow/ExternalEventRow; Shell -> CalendarView -> Month/Week children; Shell -> Ask/Search result callbacks. Reminders and Clock may present their **own** editors directly. Shell also owns a unified editor presenter for callbacks from the other features and shared rows. Present over the current Ask/Search/Settings sheet, with originating presentation identity retained; dismissing Search/Ask merely to reach an editor would change the current journey. A concrete `PlannerEditorHost<Content>` in Shell can attach the sheet to each modal root while using the same typed destination state and factory. Native Apple-event presentation remains NativeEvents, including recurrence/delete behavior.

## HomeView, OneApp and lifecycle split

`HomeView.swift` currently mixes app-session work with UI composition. Split at these exact seams:

- HomeTab, AskRoute, NewItem, tab/calendar/clock restoration and route state: TodayShell. `CalendarView.Mode` and `ReminderTarget` must be public in their features; no feature reads HomeTab or NewItem.
- HomeView body/main/topBar/bottomBar/smart add, tab swipe, bindings, sidebar overlay and destination wiring: TodayShell, using real feature roots.
- TabPill stays Shell because it names HomeTab; CircleButton/PressScale/glassCapsule/glassCircle move DesignSystem. This cuts the apparent dependence of Calendar, Search, Reminders and Ask on HomeView.
- DrawerModel/DrawerDrag/DrawerLayout/slide modifiers: DesignSystem if Ask also uses the drag mechanics; otherwise Shell with Ask receiving back gesture behavior. Do not let FeatureAsk import TodayShell.
- `importShared()` (about 213–282), `dropDeletedMirrors`, `autoPlan`, `updateWidgets`, bootstrap `.task`, reminderSignature-driven resync, foreground/background and CalendarSync.version handling: concrete MainActor AppSession in TodayShell, injected OneStore/container/adapters/toast/clock. This is one lifecycle object justified by actual lifecycle responsibility, not a view model per screen.
- Keep signature debounce/cancellation, bootstrap ordering, save-before-inbox-ack, receipt survival through Undo, ledger migration before prune, outbox import, grant check and widget-ready gate. AppSession should return share-import probe values to the existing DEBUG UI; do not rewrite those semantics during movement.
- `ShareImportTestHook` at the bottom of HomeView belongs to DEBUG app support, not the shipping One library. TestDataset/DevImport/PreviewFixtures/HealthDebugSeed/CalendarDemoSeed stay app DEBUG support or existing TestSupport/Workbench according to their actual dependencies. SampleData production first-launch insertion remains app bootstrap; split `resetFlags` from store creation's testing configuration seam.
- QuickActions.swift splits QuickAction observable pending state (Shell) from AppDelegate/SceneDelegate (Xcode app). The delegates call explicit Shell pending-action methods and One.WidgetFeed background registration. OneStore must not depend on QuickAction or AppDelegate.
- OneApp.swift: @main entry moves to the app assembly source directory. OneStore becomes its own One source and opens the exact same schema/configuration/path; `start()` configures notification/sync/widget adapters once even when an AppIntent starts the process first. App-only Health seed/axe/preview branches move to entry bootstrap. Pass launch configuration explicitly to the store opener; preserve durable `-uiTestingStore` names and in-memory behavior.

Other remaining files are already assigned by the linked baseline: PerformanceTrace/PageResourceTrace/YearCacheTrace and HealthKitSource move only once to TodayPlatform; the existing root source files are authoritative. Keep Assets.xcassets, cities.json, Sounds and AppShortcuts.xcstrings in the main app bundle and preserve the shortcut extraction/localization inputs. No app asset, entitlement or signing movement is needed to extract screens.

The Xcode executable currently has `PRODUCT_MODULE_NAME = One` in both Today xcconfigs. Once a package library named One is linked, the executable **must use a different module name**, e.g. TodayApp. Keep its bundle identifier/product branding/resources/entitlements unchanged. Persistent declarations now compile only in package module One; do not also compile them in TodayApp. Widgets keep module TodayWidgets and the app-side AlarmMeta remains One.AlarmMeta. Root owns this configuration change and must check AppIntents metadata discovery, widget Live Activity generic identity and host-test imports; changing module names without preserving these declaration owners is not an acceptable shortcut.

## API visibility and already compiled paths

Existing cached evidence inspected without rebuilding:

- `/Users/yuanlu/code/one-app/tests/results/devtools/derived-data/45eb9437a45fb9f926ea/Build/Products/Debug-iphonesimulator/` contains TodayCore, TodayShared, TodayData, TodayPlatform, TodayDesignSystem, FeatureClock and FeatureHealth `.swiftmodule/arm64-apple-ios-simulator.swiftmodule` artifacts.
- Adjacent `Build/Intermediates.noindex/TodayModules.build/Debug-iphonesimulator/<Target>-t.build/Objects-normal/arm64/<Target>.SwiftFileList` points to the root checkout `t3-6ff3ffcb/ios/Sources/...`, including the five real Platform files and six real Data files. The app object directory still exposes One.swiftmodule. Cached artifacts are provenance pointers, not proof of this proposed graph or an API dump.
- Root's actual package has Swift 6 mode and real target paths. Current extracted sources explicitly export Core Capture/ChatMessage/StoredCard APIs and Data LedgerItem/LegacyLedgerRow. FeatureHealth exports `HealthView.init(model:)` and `HealthModel.init(source:store:timeout:)`. FeatureClock exports constructors with required `showUndo`; Shell must supply the existing toast closure, never an empty production closure. Platform exports TodayClock.now and performanceDestination/performanceAction APIs.

The next movement needs a narrow visibility pass, not `public` on every declaration. Export: nine @Model classes, persisted fields read by `@Query`/predicates and UI, required model initializers/computed methods, CalEntry/Source and its used fields/initializer, CalendarEntries methods, destination value, adapter methods/state, UndoToast, Task/List/Alarm actions, Ledger/GrantStore, OneStore and feature entry points. Public SwiftData models must keep macro-generated model identity/schema unchanged; visibility edits are not permission to rename fields/types. Public view `body`, UIViewRepresentable associated representable/coordinator types and public extensions need correct access levels. A public type alone does not export its memberwise initializer. Generic builders and returned nested enums (`CalendarView.Mode`, ReminderTarget) must also be public where composition names them.

Keep package internals hidden: private WeekPage/slot hit-test helpers, Ask turn state, Reminder inline editing state, search result implementation and Clock wheel internals. Make explicitly declared public API default expressions reference accessible declarations; otherwise move construction defaults into an initializer body. Swift 6 MainActor closures and observer callbacks need ownership checks at the actual errors; do not add broad Sendable/unsafe suppression. No compiled API visibility test was run in this research lane.

## Ordered next implementation and bounded bridge exit

1. Root applies its linked package baseline, then moves model-free split declarations (keys, chrome, capture footer/list menu, clock) to their actual existing modules. Remove original source membership once. This cuts false feature imports first.
2. Create real One library and move the model/system/action/intent closure above; split @main/OneStore and set executable module TodayApp in the same integration step. Preserve original declaration modules for app-side AlarmMeta/AppIntents and persisted models. Do not move intent/controller halves independently.
3. Create TodayPlannerUI from the listed real row/gesture implementations. Split EntryActions.swift: modifier/dialog/SwipeIfRows/extensions here; EntryDeletion.perform in One alongside CalEntry and common TaskActions/AlarmActions. Replace shared row editor sheets with required actions. Keep pendingDelete binding on the list/grid container.
4. Move each real feature closure, including its listed editor and concrete option controls. Add constructor/destination seams and public APIs. Today/Calendar/Reminders/Ask/Clock/Settings/Activity/Search all leave ios/One; no empty feature facades remain.
5. Move HomeView/Sidebar/Drawer/composition/session and thin entry. Bind the same model container/toast/adapters into all roots and modal editor hosts. Keep production and DEBUG hooks in the correct build graph. Workbench constructs concrete fake dependencies above features; One does not import TestSupport/Scenes.
6. Root validates the resulting imports/target source membership once, then performs the authorized store identity, integrated build and focused UI checks. This document itself requires only whitespace/source review. Suggested journey coverage for the integration owner: Today task completion/Undo and timer opening; Calendar alarm marker/editor and empty-slot/task drag; Ask Add/Undo/Open; Reminders remote completion/save failure; Settings reset/export and Siri-first store bootstrap. These are gate candidates to select proportionately, not a request to run all suites in this lane.

At the end of this pass One's screen count must be zero (native-system compatibility editor wrapper and intent snippet are explicitly identified system/intent UI). Shared model-bound operations remain listed, with no new feature-specific state or screen factories added. One -> Feature*/TodayShell/TodayPlannerUI/TodayTestSupport/TodayScenes must be absent in Debug **and** Release. `TodayPlatform -> One` must be absent; otherwise the already linked FeatureClock/Health graph can loop back through compatibility code.

Exit has two distinct gates:

- **Operational bridge slimming:** once all features use the constructor/actions above, split One's model declarations from adapter implementations without changing their module: move operations to a new concrete planner-services target that depends on One, Core/Data/Platform; move rows to depend on that service target. Remove model-to-service methods first (`Capture.insertRecorded`, LedgerEntry.legacyRow mapping can be external extensions). Intent/AlarmMeta identity declarations and their Siri-first transitive runtime closure remain One until their own identity proof allows movement. Do not move a service called directly by One.AppIntents into a target that itself imports One: that recreates a cycle. A lower, model-free operation protocol/value input can be constructor-injected where the caller already owns construction, but an app-only registration callback cannot initialize a Siri-first process and must not become a service locator. The TimerEntity/TimerController SCC requires a deliberate configuration/entity/donation seam before further slimming; its identity-bound closure may therefore remain One until the identity migration. Neither slimming nor identity retirement is a prerequisite for extracting every real screen now.
- **Identity bridge retirement:** an old-writer/new-reader disk harness verifies all nine model schema IDs/counts/fields/relationships/encoded blobs, receipt no-resurrection behavior and legacy Habit/LedgerEntry retention. Separately prove existing AlarmMeta Live Activities and AppIntents/Shortcuts/entity identities across app upgrade. Only a reviewed migration with those proofs can rename/remove One. Failure retains the store and bridge; it never deletes or silently recreates user data.

This is a finite, source-backed bridge: models and enumerated common process operations only; every requested feature has a concrete target and screen closure now. Future removal of One is conditional on identity proof, while completing the remaining screen modularization is the next implementation work.
