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

## Optimized Debug baseline: source/stage diagnosis (2026-10-18)

The parent ran the frozen-source optimized Debug launch method successfully.
Read-only verification used canonical raw log
`tests/results/runs/performance-climb-20261018/baseline-optimized-ui-d436a759.log`,
launch method lines 2435–2532. These are three ordered app-side proxy samples,
not shipping Release, real usable-content or touch-to-photon results. This lane
ran no compiler, build, UI or profiling during diagnosis.

Raw launch proxy milliseconds: `[2299.458791, 1562.401, 1576.318375]`;
median `1576.318375`, range `1562.401–2299.458791`, n=3.
Store: `[139.081166, 69.886625, 73.906333]`;
bootstrap: `[69.33575, 55.847542, 56.500167]`;
post-bootstrap endpoint: `[817.770375, 609.52975, 587.674917]`.
Raw warm-resume proxy: `[73.626084, 47.012667, 37.815708]` ms;
median `47.012667`, range `37.815708–73.626084`, n=3.
The first sample is slower, but cache warming is only a hypothesis; retain all
three and do not discard it as an outlier.

The report also supplies init-to-store values
`[7.474750, 6.217333, 6.030375]` ms. Arithmetic on corresponding samples gives:

- Init → bootstrap_start: `[1412.352666, 897.023708, 932.143291]` ms.
  This includes the measured init overrides and store interval.
- Store_ready → bootstrap_start:
  `[1265.796750, 820.919750, 852.206583]` ms, derived as total minus
  init-to-store, store, bootstrap and post-bootstrap intervals.
- Store_ready → bootstrap_start plus post-bootstrap endpoint accounts for
  `[90.61%, 91.55%, 91.34%]` of the corresponding total proxy durations.
  Even a hypothetical zero-cost store/bootstrap would leave most of the proxy
  unchanged; their measured durations alone cannot explain a 3x opportunity.
  Required store/import/migration work must remain intact.

### What the gaps contain, and what remains unknown

The first gap is **after** `OneStore.start` returns and **before** the existing
HomeView bootstrap `.task` starts. It can include the rest of App initialization,
app/scene delegate work (`QuickActions.swift` registers background refresh and
sets up the scene), WindowGroup/model-context attachment, HomeView/DayAgenda
state and @Query initialization, SwiftUI graph/body construction, initial List
and controls, appearance/window work and task scheduling. The `.task` is not
invoked synchronously from `OneApp.init`; this gap is not extra fixture loading,
which is inside the measured bootstrap. The available marks cannot divide app
CPU, SwiftUI/UIKit/framework initialization, query work and scheduler waiting.
The historical pre-init Debug duration is excluded by this new endpoint and
cannot explain this residual by definition.

After bootstrap, inserted fixture objects can invalidate HomeView's three
queries and DayAgenda's three queries, rebuilding the agenda/List with real
content. DayAgenda computes today's items and tomorrow's preview, observes the
Health line, and starts scroll-to-now on appearance. HomeView also observes
`reminderSignature` and starts its existing 300 ms debounce task. The probe must
receive `bootstrapComplete` through SwiftUI, be updated/armed, acquire nonzero
geometry and an active foreground window, then receive two eligible display-link
callbacks. Thus the post-bootstrap span can include content/graph/layout work,
other main-actor tasks, scene activation gating and probe observation delay.
It does **not** establish 588–818 ms of drawing CPU or a finished animation.

The 250 ms scroll-to-now sleep, 300 ms resync debounce and 1.5 s sidebar sleep
are asynchronous waits, not additive blocking startup costs. Their work may
interleave if their deadlines fall inside a gap, but current marks do not show
that ordering. Do not remove them or attribute their full nominal duration to
this measurement. Bootstrap completion is still not a barrier for Health,
notification/AlarmKit reconciliation, EventKit refresh or scroll completion.

### One next narrow hypothesis: cancelled debounce tasks still reconcile

Source evidence: `HomeView.main` uses `.task(id: reminderSignature)` followed by
`try? await Task.sleep(for: .milliseconds(300))`, then alarm retirement,
`Reminders.shared.resync()`, `Ringer.sync(context)` and widget update. When a new
signature cancels an older sleeping task, `try?` swallows CancellationError and
the older task can proceed immediately. Fixture insertion changes the queried
signature; alarm reconciliation can also mutate alarm fields. Consequently a
superseded task **may** perform a redundant pass during startup instead of being
coalesced into the latest pass. This is a concrete cancellation path, not yet a
measured frequency or dominant-cost finding.

The simulator does not make the path automatically free:
`Reminders.resync` first awaits notification authorization status;
`AlarmScheduler.reconcile` fetches alarms/tasks/events and assigns missing alarm
IDs before its authorization guard. `WidgetFeed.update` does skip UI-test writes.
Do not infer notification permission or actual AlarmKit work from source alone.

The next diagnostic should count debounce generations, cancellation exits and
actual reconciliation entries, and locate their main-thread stacks against the
two residual intervals. Profile only when the parent grants the host lane.
If repeated cancelled generations actually reconcile inside a dominant interval,
the single candidate is a cancellation-aware exit **at the existing debounce
sleep boundary**, leaving the newest generation's same 300 ms delay and full
retirement/resync/AlarmKit/widget pass unchanged. Do not abort a partially started
reconciliation, delete a pass that has no successor, defer required data import,
change tab state or move the endpoint earlier. Verify that final scheduling
still reflects the newest model state before accepting the candidate.

Reject this startup hypothesis if there are no superseded passes, if they finish
outside the measured gaps, or if measured cost cannot credibly clear 5%. Then
profile the residual framework/List/graph versus main-actor wait costs before
selecting a different candidate; do not guess a cache or remove content. No
production edit or speedup acceptance is authorized by this diagnosis alone.
