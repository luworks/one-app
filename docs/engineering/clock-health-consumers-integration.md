# Clock and Health consumer integration

Base: `808be87f59136fbddd54edaa5dd9e8627fe6cee2`. This lane owns only FeatureClock, FeatureHealth and this handoff. Root owns Scene/App/Development/SnapshotTests integration and all build/runtime acceptance. No protocol, persistent model, Core, Platform, DesignSystem or configuration edits are included.

## Required composition and exact APIs

Install the same root-owned `PlannerActions`, `PlannerPresentation` and `UndoToast` in every Clock entry and its sheets/hosting roots. Presentation must use the same runtime/defaults passed to the constructors below. Install the runtime calendar, locale and time zone in SwiftUI's corresponding environment values, including standalone World Clock and CityPicker presentations. `PlannerPresentation` remains display/preferences only; no adapter lookup was added.

```swift
// package APIs (iOS)
AlarmsView(
    section: Binding<ClockSection>, alarms: any AlarmService, timers: any TimerService,
    notifications: any NotificationService, soundPreview: any SoundPreviewing,
    worldClock: WorldClockStore, stopwatch: StopwatchModel, now: @escaping () -> Date,
    defaults: UserDefaults, arguments: [String],
    onAlarmCreated: @escaping (OneAlarm, ModelContext) -> Void,
    showUndo: @escaping (String, @escaping () -> Void) -> Void
)
AlarmEditor(
    alarm: OneAlarm? = nil, alarms: any AlarmService, soundPreview: any SoundPreviewing,
    runtime: PlannerRuntime, defaults: UserDefaults,
    onCreated: @escaping (OneAlarm, ModelContext) -> Void
)
TimerSection(controller: any TimerService, alarms: any AlarmService, soundPreview: any SoundPreviewing)
SoundScreen(sound: Binding<String>, preview: any SoundPreviewing)

// public APIs (iOS)
StopwatchModel(defaults: UserDefaults, now: @escaping () -> Date,
               initialState: StopwatchState? = nil, initialPage: StopwatchPage? = nil)
StopwatchView(model: StopwatchModel)
WorldClockStore(database: CityDatabase, defaults: UserDefaults, homeZoneIdentifier: String,
                homeCity: CityRecord? = nil, initialKeys: [String]? = nil)
WorldClockView(store: WorldClockStore, now: @escaping () -> Date,
               showUndo: @escaping (String, @escaping () -> Void) -> Void)
CityPicker(store: WorldClockStore, now: @escaping () -> Date)
HealthModel(source: any HealthSource, store: HealthSelectionStore, runtime: PlannerRuntime,
            gate: HealthAccessGate, timeout: Double = HealthTimeout.seconds)
HealthLineModel(source: any HealthSource, store: HealthSelectionStore, defaults: UserDefaults,
                runtime: PlannerRuntime, gate: HealthAccessGate)
HealthMetricDetail(metric: HealthMetric, series: HealthSeries, now: Date,
                   units: HealthUnits, calendar: Calendar, locale: Locale)
```

`HealthView(model:)` is unchanged. HealthModel exposes its immutable `runtime` for row/detail formatting. Construct one HealthSelectionStore with explicit session defaults/arguments, and one HealthAccessGate shared by that session's HealthModel/HealthLineModel. Separate sessions need separate gates, stores and sources; no consumer uses their `.shared` defaults. HealthSelectionStore itself remains outside this lane and still posts a process-wide notification with nil object; HealthLineModel reads only its injected store/defaults when it receives that notification. This can trigger a redundant refresh in another session, but does not read the other session's selection. Root/Core may scope the notification separately if strict refresh isolation is required.

`onAlarmCreated`/`onCreated` is required because the actual PlannerActions contract has delete but no alarm-create recording operation. Root must supply the retained session Ledger, for example:

```swift
{ alarm, context in
    ledger.record(.created, kind: "alarm", title: alarmTitle(alarm, runtime: runtime), context: context)
}
```

Do not supply an empty live callback. It runs only after the editor saves a newly inserted alarm successfully. Existing-alarm edits keep the previous no-extra-create-entry behavior. Failed save keeps the editor open and removes a newly inserted draft before retry; it neither records creation nor schedules the alarm. Deletion routes through the environment PlannerActions and UndoToast, preserving actual Activity/Undo. Stop/toggle/save/sync use the supplied AlarmService. Sound selection updates its original binding, previews on the supplied SoundPreviewing, and stops that same preview when leaving the screen. The timer sound binding updates the retained TimerService.

AlarmsView calls the actual `FirstRun.alarms(_:notifications:arguments:)`; the actual API has no defaults argument. Its explicit defaults are used for new-alarm preferences. Root supplies arguments, including `-uiTesting` to suppress first-run permission requests in development. Permission status and Allow dispatch to the same injected notification/alarm capabilities. No Ringer/static service calls remain in these consumers. Existing PerformanceTrace instrumentation remains.

Root retains one WorldClockStore and one StopwatchModel and supplies those exact instances to AlarmsView, standalone routes and CityPicker. The tab switch never creates a live default store/model. Root loads `cities.json` using `CityDatabase.decode`; the former FeatureClock bundle-backed `CityDatabase.shared` extension was removed. Supply the selected home zone explicitly; malformed city time zones now use a deterministic GMT fallback instead of reading the device zone.

## Development seeds root must reproduce

Feature model initializers no longer inspect ProcessInfo, clear preferences or parse test arguments. Root's Mock assembly must translate the existing flags before constructing models. Explicit initial values override loading but do not clear or immediately persist state; later real edits continue saving through the existing preference keys. For exact previous reset semantics, clear the keys in development assembly first. Production passes nil initial values and loads/migrates the selected defaults.

- Stopwatch: under `-uiTesting`, remove `StopwatchState.defaultsKey` and `StopwatchPage.defaultsKey`, start with `StopwatchState()` and `.analog`. For valid `-uiTestingStopwatch <seconds>`, parse `-uiTestingStopwatchLaps <comma-separated doubles>` and create `StopwatchState(startedAt: nil, accumulated: seconds + laps.reduce(0, +), laps: laps)`. Without a valid seconds flag, ignore laps. A valid `-uiTestingStopwatchPage <raw value>` overrides the page. Existing references include 5.75 seconds, laps `[4.2]` and `[4.2, 6.5, 5.1]`. StopwatchState's own unchanged serialization key and `today.stopwatch.page` must stay. Supply a live advancing clock for interaction journeys; a frozen screenshot seed is stopped. Stopwatch actions, both faces and current lap all read its supplied clock.
- World Clock: under `-uiTesting`, remove `today.worldClock.cities`, then pass `initialKeys: []` unless `-uiTestingCities <comma-separated city keys or legacy zone IDs>` supplies keys. WorldClockStore still runs `database.migrate` so zones and GeoNames IDs retain their original migration/order. `-uiTestingHomeZone` overrides the chosen home zone; `-uiTestingHomeCity` resolves through that same database and overrides the displayed home. Graph starts false. Root preserves the same injected now in cards, graph and picker.
- Preserve ClockTests' world-clock reference IDs: home `g5392171`; ordered cities `g4684888,g4930956,g2353151,g1816670`; reference `-uiTestingNow 18:20`. Other existing journeys use London/Tokyo with Los Angeles home and `12:50`, London/New York, and New York/London/Kolkata/Tokyo. Keep the original fixture database and its GeoNames IDs, rather than substituting similarly named cities.
- TimerService development implementation remains root-owned. Preserve `-uiTestingTimers` (for example `600:Pasta,1500,300:Tea:paused`), `-uiTestingRecents`, `-pomodoroRounds`, stable timer/recents IDs, paused/ringing states, starts/recents/sound/log behavior and the original accessibility IDs. FeatureClock no longer constructs any concrete timer/alarm adapter.
- HealthSource DI already exists and stays in place. Preserve root's sample/empty/HealthKit selection, `-uiTestingHealthStall`, `-uiTestingHealthAuthStall`, `-uiTestingHealthMetrics`, `-uiTestingKeepHealthMetrics`, and deterministic now. HealthSelectionStore's existing explicit arguments still implement selection reset/keep behavior; this lane does not change Core. Both Health consumers must use the same gate/source/store and runtime in a session. Keep query timeout, late access retry, per-row loading, stale-result fencing, cancellation checks and previous data on a stall. Empty data never claims access was denied. Health remains read-only.

All existing feature accessibility identifier expressions are retained. In particular keep `alarm.*`, `alarms.*`, `clock.*`, `worldClock.*`, `stopwatch.*`, `timer.*`, `pomodoro.rounds`, `health.*`, and `settings.healthMetrics`; root must retain the launch scenarios that expose them.

## Preserved fixes and verification boundary

The existing `790c236` fix remains: RoundButton.adaptive is nonisolated, with its pure dynamic UIColor factory safe for SwiftUI's asynchronous renderer. The existing `c7d08d7` fix remains: Health facts use an accessibility-size VStack via AnyLayout and retain their individual fact identifiers/labels. No blanket actor annotation or unsafe Sendable conformance was introduced. The existing HealthLineModel observer lifetime annotation is unchanged.

Validation in this lane is Swift frontend syntax parsing of all 13 Clock/Health Swift files, `git diff --check`, and a source audit for ownership, unchanged accessibility IDs, removed ambient service/time/defaults/test-fake resolution, and preservation of those two fixes. Raw parser output and source-audit JSON are retained under the primary checkout's `tests/results/` and indexed by `tests/qa/journal.py`.

Evidence: `/Users/yuanlu/code/one-app/tests/results/clock-health-consumers-20261019T041657Z/{syntax.log,source-audit.json}`; QA journal session `clock-health-consumers-20261019T041657Z`. The parser exited 0 with only the host macOS-sysroot/iOS-target warning.

Syntax parsing does not resolve imports or type-check the cross-module APIs. No SwiftPM tests, Xcode build, simulator or device run was performed, as explicitly assigned to root. Root must adapt Scene/App/Development/SnapshotTests call sites to these signatures before integrated validation. Focus that validation on switching Clock sections without losing model identity, World Clock remove/reorder/Undo and picker identity, Stopwatch start/lap/stop/reset/page persistence, alarm save/toggle/stop/delete/Undo and creation Activity, timer sound/recents/pause/resume, Health stalled/late/cancelled loads and 7/30/90-day detail including accessibility facts. Real AlarmKit playback/authorization and HealthKit/device behavior remain separate acceptance gates.
