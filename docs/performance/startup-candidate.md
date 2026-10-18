# Startup and navigation measurement lane

## Measurement-only revision

Base checkout: `abd7312`; historical measurement source: `fc683a7`.
This first commit changes no store, migration, import, tab lifetime, scheduling,
animation, Add/Apply/Undo or EventKit semantics. Every new trace is opt-in through
`-performanceTrace`; the content background probe and accessibility label exist
only with that flag. No user titles, paths, counts or other personal content are
included in trace records. Existing `coldStartMs` remains a legacy diagnostic.

Use **optimized Debug**, `SWIFT_OPTIMIZATION_LEVEL=-O`, for both frozen baseline
and candidate. Keep `DEBUG` defined: `TestDataset` and its HomeView path are
DEBUG-only. Do not call this a shipping Release launch measurement. Pure Release
package measurements remain separate. No new compilation condition is required.

The parent reconstructs frozen source with `git archive fc683a7`, then applies
only this lane's measurement file diff, not other lanes' ancestor commits:

```sh
git diff fc683a7 <measurement-sha> -- ios/One/HomeView.swift \
  ios/One/OneApp.swift ios/One/LaunchTimer.swift ios/One/PerformanceTrace.swift \
  ios/OneUITests/PerformanceClimbTests.swift docs/performance/startup-candidate.md
```

The current project uses file-system synchronized `One` and `OneUITests` groups,
so these new files need no project edit. Verify identical source membership in
the reconstructed baseline and candidate; project changes belong to packaging.

## Endpoint contract and limitations

`PERF_TRACE v=1` breadcrumbs and `PERF_SAMPLE_APP v=1` samples use
`DispatchTime.now().uptimeNanoseconds` from the app process, on the main actor.
Each completed sample has sequence, name, route, start/end nanoseconds and elapsed
milliseconds. The same strings are os_signpost events under subsystem
`com.luworks.one`, category `PerformanceTrace`. The latest completed sample is
available as `performance.trace` for XCTest attachment and raw-log retention.
Superseded operations emit `cancel.<name>` and never become successful samples.

- `app_init_to_content_layout`: begins at the first explicit statement in
  `OneApp.init`, **after** Swift runtime/property-wrapper work before that point.
  It excludes process start/dyld/pre-init. `store_start` and `store_ready` bound
  `OneStore.start`, including its configuration hooks. `bootstrap_start` and
  `bootstrap_complete` bound HomeView's existing task through fixture/sample
  loading, lists, share import, Ledger migration/prune, Activity outbox, auto-plan
  and awaited first-run Calendar handling. A private-export early return never
  emits bootstrap completion and deliberately produces no successful sample.
- Tab and Calendar-mode names are `<source>_to_<destination>`; routes are `today`,
  `calendar.week|month|year`, `tasks`, `clock`. Begin is inside the pill/swipe action
  or Calendar mode Binding setter **before** the existing state mutation.
  This excludes XCTest tap delivery and physical touch processing before the
  action; it includes the app's subsequent state propagation and layout opportunity.
- `resume_to_content_layout`: begins on HomeView's `.active` scene callback after
  a completed launch, before its existing foreground import/refresh work. It
  excludes earlier OS activation work and does not await the unstructured
  Reminders resync task. No process-launch sample is emitted as a resume.
- Every end requires completed bootstrap, a matching route, a nonzero content
  background UIView attached to a foreground-active window, and two display-link
  callbacks. There is a display opportunity between callbacks. No artificial
  ready/skeleton replaces content and no required launch work is deferred.
  **This is a content geometry/display-opportunity proxy**, not compositor
  presentation, animation completion, first usable content, finished async
  EventKit/Health refresh or touch-to-photon. SwiftUI asynchronous updates and
  scroll-to-now may continue. Tests separately require actual destination
  content and hittable launch actions. Never populate the real usable-content
  acceptance rows from this proxy or infer hitch/FPS from it.

The callback granularity introduces roughly one frame interval of observation
floor plus normal scheduling. Do not subtract a guessed floor. Quantify any
small gains against variability. Trace overhead includes two callbacks, bounded
latest-report state, signposts, stdout and an accessibility-only label; apply it
identically to both artifacts. The probe observes ordinary geometry and never
forces content layout or waits for a guessed fixed duration.

## Intended focused checks (parent owns host lane)

Exactly three methods in `PerformanceClimbTests`:

1. `testLaunchAndResumeEndpoints`: three process relaunches and warm resumes;
   validates monotonic fields and actual Today/date/New/Ask shell controls.
2. `testNavigationEndpointsAndKeptState`: three full tab/mode cycles with
   destination identifiers, then verifies retained Reminders list and Month.
3. `testYearScrollMemory`: app-scoped `XCTMemoryMetric(application: app)` and
   scrolling/deceleration metric, three up/down iterations. Keep complete
   xcresult metric names/units/raw values. Duration does not establish hitch rate.

Build once per comparable source, same optimized Debug flags, simulator, fixture,
pinned clock, cache state and quiet host. Run only those three methods through
`ios/Eval/run-e2e.py`, with durable output and a shared named runner/cache owned
by the parent. Preserve raw app stdout/signposts, test attachments and xcresult.
New optimized Debug memory is a fresh baseline; legacy Debug memory is not its
denominator. The footprint acceptance ceiling is 49% of its comparable baseline.

Static-only delivery: no Swift compiler, build, simulator UI, profiling or phone
commands ran in this implementation lane. The parent must establish compilation,
source membership, endpoint arrival, real destination content and metric support.
The existing Debug process/onAppear median (2323 ms, mostly pre-init) does not
identify a shipping startup bottleneck or justify moving required work.

## Optimization decision

No production candidate is included before a comparable optimized baseline.
Source inspection alone does not defend skipping or postponing migration,
Share import, auto-plan, widgets or first content. The dominant historical
pre-init Debug time is outside these owned statements. After the parent captures
stage samples/profiling, optimize only a measured dominant cost with preserved
end semantics; keep such a candidate in a second separable commit.
