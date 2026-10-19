# Workbench linked-module assembly handoff

Base: `9183e90942e817c499ea3c3d5a7f04fee6ec1494`.
This lane owns only SceneCatalog, WorkbenchApp, TodayScenes registry, existing
SceneRegistryTests and this document. Production services, models, manifests,
project configuration and the standalone TodayWorkbench consumer remain root-owned.

## Actual consumer and access identity

Compile `Development/SceneCatalog.swift`, `Development/WorkbenchApp.swift` and
`Development/Support/TestDataset.swift` in the separate TodayWorkbench executable.
Set `DEBUG`, `TODAY_WORKBENCH`, Swift 6 and **`-package-name ios`** on that consumer.
The manifest's display name `TodayModules` is not the package access identity.
The executable must **import One**, rather than compile model declarations again
or rename its own Swift module to One. Link TodayCore, TodayData, TodayPlatform,
TodayDesignSystem, TodayPlannerUI, TodayTestSupport, TodayScenes and the actual
FeatureToday, FeatureCalendar, FeatureReminders, FeatureClock, FeatureAsk,
FeatureSettings, FeatureActivity, FeatureSearch and FeatureHealth products.
Root must keep development sources and fake dependencies out of the Live graph.
Bundle `tests/fixtures/today-dataset.json`, the city database and existing feature
resources. The source-path dataset fallback is for local development only.

The catalog now uses the source constructors in `Sources/`: DayAgenda's task,
event and timer actions; CalendarView's concrete calendar plus task/alarm/day
actions; EventEditor(calendar:); RemindersView(sync:requestAccess:);
AlarmsView(alarms:timers:showUndo:), AlarmEditor(showUndo:) and
TimerSection(controller:alarms:); AskView(calendar:now:...); ActivityView's
activity/flush/undo callbacks; ActivityDataView's summary/clear/export/count
callbacks; and SearchView's real editor builder. Callbacks present the actual
TaskEditor, EventEditor, AlarmEditor, NativeEventSheet or TimerSection.

Settings sections use **`SettingsView.Selection`** (the current typed API, not a
new SettingsSection type). All formerly blocked Apple/Today/AI/Smart Lists/About
IDs now construct the complete production SettingsView with `selection:` and its
required services and destination builders. Appearance, Calendar, Reminders and
Alarms also use that same view. Delete selects `.data`, retaining the real
production two-confirmation journey. Automatic Changes, Activity data and
Holidays use their real native destinations. The obsolete private-Settings
integration blockers are removed; service isolation remains required.

### Remaining constructor gap

`FeatureCalendar/YearMarksView.swift` still declares `YearKeySheet` and its body
internal, with no package initializer. Root must expose the **existing** type,
`package init()` and `package var body`. The factory intentionally references this
real screen; it cannot type-check as a cross-module consumer until root makes that
change. No private substitute key screen is introduced. No complete iOS module
type-check was run, so further cross-module diagnostics remain a root build gate.

## Fail-closed sandbox contract

The default `.isolatedFeatures` runtime does not authorize legacy services.
Every `legacyEnvironment` scene throws before its feature view or concrete
services are constructed unless **all three** callbacks below exist:

```swift
SceneCatalogRuntime(
    prepareLegacyEnvironment: { configuration, container, defaults in
        // Install actual root-owned sandbox boundaries before any service construction.
    },
    makeServices: { configuration, container, defaults in
        // Return SceneCatalogServices using that installed sandbox.
    },
    disposeLegacyEnvironment: {
        // Restore global hooks and stop sandbox-owned tasks/services.
    }
)
```

The preserved preparation signature is
`@MainActor (SceneConfiguration, ModelContainer, UserDefaults) throws -> Void`.
`makeServices` has those same arguments and throws -> `SceneCatalogServices`.
Disposal is `@MainActor () -> Void`, idempotent at SceneSession level, including
initialization failure. Root should return closures belonging to one owned
sandbox lease; overlapping sessions must be rejected or scoped safely when static
hooks cannot coexist. A no-op preparation callback does not establish isolation.

`SceneCatalogServices` requires exactly:

- `CalendarSync`, `RemindersSync`, `Reminders`, `AlarmCenter`, `TimerController`,
  `ActivityCenter`, `LocalDiagnostics` concrete instances;
- `requestReminderAccess: @MainActor () async -> Void`;
- `activitySummary: @MainActor () -> ActivityCenter.Summary`;
- `clearActivity: @MainActor () -> Void`;
- `exportActivity: @MainActor (ActivityExportFormat) async throws -> URL`;
- `shareDiagnostics: @MainActor (URL) -> AnyView`;
- `reset: @MainActor (ModelContext) -> Void`.

Root must implement the real production injection boundaries backing these
instances and callbacks. In particular, existing static readers and transitive
screens still reach Ledger/ActivityCenter, CalendarSync/RemindersSync,
AlarmCenter/Ringer, TimerController, notification APIs, standard defaults,
WidgetFeed, share inbox/outbox, diagnostics export and DataReset. Their writes,
permission requests, disk paths and background tasks must stay inside the
sandbox. `ActivityCenter` currently has a private live initializer; passing its
shared live instance is not a sandbox. Settings export/share/reset and Search's
native system-event destination require the same boundaries as the initial page.
Switching Clock sections must also remain sandboxed. `defaultAppStorage` only
changes SwiftUI AppStorage; it does not redirect static standard-default readers.

Preparation must install the configured clock/calendar/time zone and defaults
before fixture load and before HealthLineModel's observer is created. Today,
Calendar, Reminder rows and Health list still contain static clock/calendar
readers; environment values cannot replace them. Root must audit those readers
before claiming deterministic screenshots. The factory provides a fixed clock
where constructors actually accept it and seeded proposal/alarm/chat IDs.
Framework PersistentIdentifiers and tied fixture sort order are not claimed
reproducible across stores. Dense reuses the versioned dataset at six nearby
minute offsets; empty named-list preserves lists while removing items.

The only `-uiTesting` argument created here seeds the existing StopwatchModel's
reset/lap fixture. It is **not** the sandbox or evidence of system-write isolation.
WorkbenchApp deliberately keeps `.isolatedFeatures` until root's actual assembly
is available. WorkbenchRoot(launch:runtime:) is the explicit injection entry.

## Ask mutation ownership

Direct cards now call real `AskNativeActions.applyPlan`, `.applyPlanAlways`,
`.applyChange` and `.applyTidy`, including their returned native UndoRow. They do
not copy policy, grant or tidy mutation logic. Optional runtime applyChange,
applyAlways and applyTidy overrides retain the existing context/toast signatures
for an assembly-owned feedback host. Capture Add/Undo continues to use the native
Capture.insertRecorded/Ledger APIs. All actions remain behind explicit Add/Apply
or Always taps; a sandbox must cover their transitive service writes too.
The complete AskView also receives the real editor callbacks and fixed `now`.
Workbench intentionally has no product tab-selection side effect after Add.

## Scenario applicability

Registry metadata remains Foundation-only. Unsupported scene/scenario pairs fail
validation both on launch and decode. Workbench offers only the selected scene's
supported cases and resets an incompatible choice when switching scenes.

- Today/review, Calendar modes and Reminders lists: normal/empty/dense model data.
- World Clock and City Picker: normal/empty/dense selected cities; empty keeps the
  real home card and does not erase the city database. Stopwatch: normal/reset/laps.
- Health list: normal/empty plus **error** and **unavailable**. Error wraps the
  deterministic source with existing ScriptedHealthSource, stalling the default
  metrics' queries; HealthModel's real timeout is shortened to 50 ms so it reaches
  `.failed(.stalled)` without a long wait. This is a query-timeout case, not an
  invented generic error. Unavailable sets HealthSource.isAvailable false and
  reaches HealthView's actual unavailable branch.
- Health detail: normal/empty series only; its constructor accepts series, not a
  loading/error/availability state machine. Picker: normal only, since it edits
  selection rather than fetch state.
- Loading remains unsupported: HealthModel's spinner is transient and its timeout
  bounds stalled queries. Denied/revoked remain unsupported: HealthKit read access
  cannot distinguish those from an empty series. Other destinations support normal
  unless explicitly listed above; no screenshot substitutes manufacture states.

HealthLineModel is created only after the legacy gate succeeds. Health detail,
picker, World Clock and Stopwatch can use the default runtime without constructing
that standard-defaults observer. Health selection storage and environment are
injected for Settings and its native Health destinations.

## Validation

Swift 6 frontend parsing with `-package-name ios`, DEBUG and TODAY_WORKBENCH passed.
Registry host compilation and focused test execution use an isolated direct
swiftc harness, not SwiftPM's entire product graph or its shared lock. Raw logs
are retained under the primary checkout's `tests/results/runs/` and indexed by
QA session `workbench-api-20261018`. The first host compile missed the toolchain
TestingMacros plugin; the corrected invocation supplies its explicit plugin path.
The direct harness also needed an explicit SDK and typed Testing entry point.
The first executed run found that Foundation inventories `zh_Hans_CN` instead of
`zh_CN` on this host. Locale validation now accepts equivalent maximized language
identities while preserving saved configuration values and rejecting invalid locales.
The final focused run passed all seven existing SceneRegistryTests.

No Xcode build, simulator, axe, physical-device or production archive exclusion
check ran in this lane, as requested. Root must build its standalone consumer,
resolve YearKeySheet visibility, implement the sandbox and run the affected native
journeys before claiming runtime acceptance. The older `scenes.md` describes the
pre-extraction assembly and is superseded by this document where APIs differ.
