# Native snapshot harness integration

Base: `6e6033046d83b0a743b39cd890ff930de5c9f43d`. This lane owns only
`ios/TodaySnapshotTests/NativeSnapshotTests.swift` and this handoff. Root owns
integrated compilation, runtime verification and PNG baseline review. No feature,
configuration, project or baseline changes are included.

## Mounted-window capture

The old harness first installed a UIHostingController in a visible UIWindow, then
passed that same controller to SnapshotTesting's UIViewController image strategy.
That strategy mounts the controller in another hierarchy. Reparenting a live
SwiftUI navigation hierarchy is the harness defect behind the reported unbalanced
appearance transitions and missing dark/large Health Done control.

The harness now keeps one containment tree: UIWindow → UIViewController container
→ UIHostingController. The container supplies explicit phone traits to its child;
UIKit owns appearance transitions. The window becomes key while rendering and the
previous key window is restored during cleanup. The host's additional safe-area
insets normalize the intended 59/34 pt top/bottom area. The real NavigationStack,
toolbar, Charts and accessibility-size facts remain production SwiftUI views.
After the existing 200 ms settling interval for the Stopwatch pager, UIKit's
`drawHierarchy(in:afterScreenUpdates:)` captures that mounted window directly with
a 393 × 852 pt, 3× UIGraphicsImageRenderer. No second snapshot-strategy window,
offscreen SwiftUI ImageRenderer, copied screen or layer-only render is involved.
An unsuccessful hierarchy draw fails the test.

The supplied native Workbench reference
`/Users/yuanlu/code/one-app/tests/results/reconstruction/workbench-health-large-20261018-2110.png`
was visually inspected: it contains Done and vertically stacked Average/Low/High
facts. It supports diagnosing the harness; it is not a snapshot baseline or a
runtime result of this change. Status bar and Workbench Scenes controls are outside
this component harness's capture contract.

## Explicit dependencies

The tests construct a frozen PlannerRuntime with the existing UTC Gregorian
calendar and POSIX English locale. HealthMetricDetail receives explicit now,
calendar, locale and metric units. StopwatchModel receives explicit now,
initialState and initialPage; the removed `arguments:` constructor is no longer
used, and setup does not seed preferences merely to reload them into the model.
Every test retains a fresh isolated defaults suite.

The current five baseline variants contain Health detail, Stopwatch and
PillSwitcher only. They do not construct HealthModel, HealthLineModel,
WorldClockStore or WorldClockView. No unused gate/selection/world objects or new
baseline variants were added. When root integrates broader registered scenes,
use the explicit APIs from [Clock/Health consumer integration](clock-health-consumers-integration.md):

```swift
let selection = HealthSelectionStore(defaults: defaults, arguments: [])
let gate = HealthAccessGate()
let health = HealthModel(source: source, store: selection, runtime: runtime, gate: gate)
let line = HealthLineModel(source: source, store: selection, defaults: defaults,
                           runtime: runtime, gate: gate)
let world = WorldClockStore(database: database, defaults: defaults,
                           homeZoneIdentifier: "America/Los_Angeles",
                           homeCity: homeCity, initialKeys: cityKeys)
let worldView = WorldClockView(store: world, now: runtime.now, showUndo: showUndo)
let picker = CityPicker(store: world, now: runtime.now)
```

Here source/database/homeCity/cityKeys/showUndo are root-owned explicit scenario
inputs, not live singleton lookups. Share the gate, selection, source and runtime
between both Health consumers within one session. Retain the same world store and
stopwatch model across entries. Keep separate sessions isolated. This illustrative
composition is not an additional compiled test or proof of scene coverage.

## Strict recording and acceptance

Both comparison and perturbation diffing retain `precision: 1` and
`perceptualPrecision: 1`. `testHealthDataPerturbationChangesPixels` still renders
identical frozen populated inputs twice and requires an exact match, then removes
real Health samples and requires a pixel difference. It never records baselines.

Baseline recording requires explicit local `TODAY_RECORD_SNAPSHOTS=1`. Presence
of `CI` or a `CI_`-prefixed environment key, case-insensitively and regardless of
its value (including empty, 0 or false), forces `.never`. Without the local opt-in,
recording is `.never`; missing references remain failures. No PNG was written or
changed by this lane. Root must review any new pixels before adopting references;
do not relax precision to absorb layout or rendering differences.

## Evidence and remaining gates

Source-only evidence lives at
`/Users/yuanlu/code/one-app/tests/results/snapshot-harness-20261019T042131Z/`:
`syntax.log` and `source-audit.json`, indexed in QA journal session
`snapshot-harness-20261018`. These are synthetic development/source checks, not
app user Activity or rendered-image evidence.

Swift frontend parsing and `git diff --check` passed. Parsing does not resolve
imports or type-check UIKit/feature APIs. No build, SwiftPM test, snapshot test,
simulator, UI audit, recording/comparison or physical-device run was performed.

Root's focused runtime gate is the existing five snapshot variants plus the
determinism/perturbation method, serially in the same pinned host/runtime/locale.
Inspect actual dark/accessibility3 output for Done and stacked facts, verify both
Stopwatch pages and absence of appearance warnings, and check safe-area geometry
and exact 1179 × 2556 pixel output. Record locally only after that review, then
compare with recording disabled. The 200 ms settling interval and mounted-window
trait/safe-area propagation still require that runtime check. See
[visual-testing.md](visual-testing.md) for target integration and baseline lifecycle;
this handoff supersedes its old capture implementation description.
