# Development scene registry and Workbench

`TodayScenes` is Foundation-only configuration data. `TodaySceneID` is the stable
launch/screenshot contract, with an exhaustive native factory in
`ios/Development/SceneCatalog.swift`. There are no screenshot, HTML or replacement
implementations of feature screens. `SceneConfiguration` validates both explicit
construction and decoding. It carries a fixed date, UUID seed, Gregorian calendar,
time zone, locale and scenario; its UUID byte algorithm does not use `Hasher`.

## Assembly contract

Root owns Package.swift, Xcode configuration, production source edits and all
legacy system-service isolation. This lane adds only TodayScenes, the two
Development files, SceneRegistryTests and this document.

- Add the `TodayScenes` library target with path `Sources/TodayScenes` and a
  `SceneRegistryTests` Swift Testing target depending on it. Swift 6 parse was
  checked; neither target has been built or its tests executed by this lane.
- Workbench compiles the app-only original sources, excluding `OneApp.swift`'s
  `@main`, plus `Development/SceneCatalog.swift` and `Development/WorkbenchApp.swift`.
  Use module name **One** for the existing SwiftData identity. Root splits
  `OneStore` out of OneApp for app-only helper compilation. Link TodayCore,
  TodayShared, TodayData, TodayPlatform, TodayDesignSystem, FeatureClock,
  FeatureHealth, TodayTestSupport and TodayScenes. Preserve root's exclusions of
  already-extracted original files; do not compile duplicate declarations.
- Set `DEBUG` and `TODAY_WORKBENCH` only in Workbench. `WorkbenchApp` is its sole
  entry point. Include SceneCatalog in the Mock app only; exclude both development
  files and TodayTestSupport/TodayScenes dependencies from production Live.
- Copy the existing `tests/fixtures/today-dataset.json` and `ios/One/cities.json`
  into the development bundle. The dataset's local source-path fallback exists
  for local previews, not a deployed resource substitute. Missing data throws an
  explicit error; a missing city resource remains the production CityDatabase's
  empty database behavior and must be checked during integration.
- App model types remain internal because the development files compile in One.
  The registry library never imports One, SwiftUI or SwiftData.

The default Workbench init parses configuration only. It never starts OneStore,
AppDelegate, account access, notifications, background refresh or HomeView.
`SceneSession` creates the owned in-memory container on the main actor with
SwiftData autosave disabled, plus a new disposable defaults suite. The session
loads the **existing TestDataset** with its fixed `now` and calendar. It does not
call SampleData, whose first-run flag writes standard defaults. Generated UUIDs
are used for synthetic alarm/chat identities; SwiftData PersistentIdentifiers
remain framework-assigned and are not claimed reproducible across stores.

## Root integration APIs and blockers

The root can construct:

```swift
let runtime = SceneCatalogRuntime(
    prepareLegacyEnvironment: { configuration, container, defaults in
        // Root's actual mock environment: memory Activity, fake EventKit/AlarmKit,
        // isolated static defaults readers, fixed TodayClock, no widget/share writes.
    },
    applyChange: { change, context, toast in /* expose the actual Ask handler */ },
    applyAlways: { plan, context, toast in /* expose applyPlanAlways */ },
    applyTidy: { rows, context, toast in /* expose applyTidy */ }
)
let session = try SceneSession(configuration: configuration, runtime: runtime)
SceneCatalog(session: session)
```

Replace `WorkbenchApp.init`'s `runtime = .isolatedFeatures` with this root-owned
assembly when ready. `WorkbenchRoot(launch:runtime:)` is also directly constructible
by Mock assembly. `SceneSession.bundledDataset` can be overridden with an explicit
versioned dataset URL; it never reads a user's store.

The empty comments above are integration signatures, not an implementation of
isolation. Until supplied, scenes tagged `legacyEnvironment` **throw before
constructing their views**. The default Workbench exposes the rejection, not a
pretend rendered screen. This restriction is intentional and is not runtime
acceptance of the whole catalog. Existing blockers require production edits outside
this lane:

| Existing API | Required root seam |
| --- | --- |
| `ActivityCenter.shared`, private init | In-memory Activity store/recorder; no user's SQLite, outbox or retention tasks |
| `CalendarSync.shared`, `RemindersSync.shared`, `AlarmCenter.shared`, `Ringer`, `TimerController.shared` | Mock services, isolated preferences and no account/OS requests or writes |
| `TodayClock.now`, model `Date.now` / `Calendar.current` uses | Fixed clock/calendar hooks for complete deterministic Today/Calendar/Reminders/Health-list behavior; SwiftUI environment alone cannot override static readers |
| `SettingsView.smartListsSection` | Expose the real private section |
| Settings inline Apple / Today / AI / About sections, `AutomaticChangesToggle` | Extract the complete native sections; the timeline/suggestions components alone do not constitute the whole subsection |
| `AskView.applyPlanAlways`, private change/tidy handlers | Expose the existing action ownership through runtime closures; no copied policy/approval logic |
| `DataReset.run`, ShareInbox and widget helpers | Keep mock Delete All Data and edits confined to the development environment |

Five private Settings subsection IDs reject every attempted rendering until these
real sections are exposed. They are still inventoried and configuration-valid;
configuration validity and factory readiness are distinct. Ask Plan/Change/Tidy
also reject when their required action closure is missing. Registry tests verify
configuration data; they do not assert these app-only integration seams exist.

## Native destinations

| Journey | Registry handles | Existing native implementation |
| --- | --- | --- |
| Today | `today`, `today.review` | DayAgenda, EveningReviewSheet |
| Calendar | `calendar.week`, `.month`, `.year`, `.year.key`, `.sources`, `.event.editor` | CalendarView with real mode binding, YearKeySheet, CalendarsSheet, EventEditor |
| Reminders | `reminders`, `.today`, `.scheduled`, `.all`, `.flagged`, `.completed`, `.list`, `.editor`, `.quickAdd`, `.listEditor` | RemindersView, ReminderListScreen, TaskEditor, QuickReminderSheet, ListEditor |
| Clock | `clock.alarms`, `.alarm.editor`, `.alarm.sound`, `.world`, `.world.cityPicker`, `.stopwatch`, `.timer` | AlarmsView, AlarmEditor, SoundScreen, WorldClockView, CityPicker, StopwatchView, TimerSection |
| Ask | `ask`, `ask.card.capture`, `.stack`, `.plan`, `.change`, `.tidy` | AskView, CaptureCard, CaptureStack, PlanCard, ChangeCard, TidyCard |
| Activity / search | `activity`, `search` | ActivityView, SearchView |
| Settings | `settings`, `.appearance`, `.apple`, `.today`, `.calendar`, `.reminders`, `.smartLists`, `.alarms`, `.ai`, `.ai.automaticChanges`, `.activity`, `.calendar.holidays`, `.about`, `.delete` | SettingsView and existing sections/screens; five private subsections explicitly blocked as above |
| Health | `health`, `.detail`, `.picker` | HealthView, HealthMetricDetail (Steps), HealthMetricPicker |

Direct cards use native bindings and existing Capture.insertRecorded,
TaskActions.setPlanned and Ledger.undo APIs. Add/Open opens the real model editor;
Undo uses the real ledger API. Plan keeps deadlines unchanged. Grant/change/tidy
execution remains injected from the existing app handlers. The complete Ask page
is also reachable; card fixtures do not replace its conversation journey.

## Scenarios and deterministic limits

The scenario enum inventories normal, empty, loading, error, denied, revoked and
dense. The descriptor's explicit scenario set is authoritative. A configuration
outside that set throws; it never silently renders normal.

- Today/review, Calendar modes and Reminders list destinations have normal, empty
  and dense data. Dense loads the same durable dataset at six nearby offsets.
  The empty named-list destination preserves the fixture lists but clears items.
- World Clock/City Picker have normal, empty and dense city selections. Empty
  means no added cities; the real home card still exists. City Picker's database
  itself stays populated. Stopwatch has normal, empty/reset and dense/lap data.
- Health list/detail have normal and empty series, using the existing
  HealthSampleSeries generator and a source with a no-op mock authorization call.
  Selection storage is injected. Detail receives the fixed date/calendar/units;
  list labels and pushed detail still require root's TodayClock integration.
- Other destinations currently support normal only. Empty/loading/error states
  for timers, Activity or editors require their real state injection seams.
- Loading/error/denied/revoked are explicitly rejected everywhere at this revision.
  HealthKit intentionally does not reveal read denial, so empty series is not
  labeled proof of denied or revoked permission. The HealthSource protocol cannot
  inject distinct failures, and a transient first-frame spinner is not a stable
  loading fixture. Root can add supported cases after genuine state hooks exist.

`SceneCapability.injectedClock` appears only where the existing public constructor
actually accepts a clock. No deterministic screenshot claim is made for remaining
legacy static-clock readers, locale-sensitive static formatters or system services.

## Launch, interaction and preview

```text
-scene calendar.week -scenario dense
-scene clock.world -scenario empty -sceneTimeZone Asia/Shanghai -sceneLocale zh_CN
-scene health.detail -scenario normal
```

Invalid handles, states, zones, locales and missing argument values yield an
accessible `scene.rejected` error. Workbench provides direct scene/scenario choice,
System/Light/Dark, every Dynamic Type size and representative locales. Changing
configuration creates a new session and resets the real view's state. The native
Scenes control opens the configuration sheet; all feature gestures remain native.
The disposable defaults domain is cleared when the session is replaced/closed.

The `#Preview` entry uses the same SceneSession + SceneCatalog factory. Screenshot
clients should construct these same types with validated configuration instead of
adding parallel view switches. Continue following `docs/swiftui-preview-workflow.md`
for axe ownership, resource windows and evidence retention; the existing POC runner
has not been changed or run by this lane.

## Validation at this lane

Base: `3b3a9bfaed35fbbfa6fc425b13690c2966cfe165`.
Swift compiler: Apple Swift 6.4, parsed in **Swift 6 language mode** with DEBUG and
TODAY_WORKBENCH enabled. Source parsing is not module resolution, type checking,
Swift Testing execution, Xcode build, axe rendering, simulator interaction,
physical-device proof or production exclusion proof. All of those gates remain
root-owned and unexecuted here, as explicitly requested. The Swift Testing cases
cover saved launch handles, all scenario acceptance/rejection combinations,
unique handles, deterministic identity, coding validation and malformed arguments.
