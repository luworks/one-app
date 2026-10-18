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

## Parent-only bounded Time Profiler plan (prepared, not executed)

Local read-only checks confirmed `xctrace version 27.1 (27A9275)`, the
`Time Profiler` template, `os_signpost` instrument, and simulator
`Today-Performance` (`3243BEDB-4F6A-4807-AE9E-30115C528377`). Installed
`xctrace help record` documents `--device`, `--time-limit 10s`,
`--launch -- <name|path> [arguments]` and `--target-stdout`. It even includes a
`.app` launch example. This establishes command syntax, **not successful
simulator app launch on this host**. Do not substitute a bundle identifier or
profile the `simctl` launcher as if it were the app. No boot, build, launch,
recording or settings change was performed while preparing this plan.

Apple's [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
list fixes for simulator-target `xctrace record` startup, supporting a bounded
attempt rather than a blanket claim that simulator recording is unavailable.
[Apple's Time Profiler tutorial](https://developer.apple.com/tutorials/instruments/determining-execution-frequency)
explains that sampling cannot determine invocation counts, and
[WWDC25 CPU profiling guidance](https://developer.apple.com/videos/play/wwdc2025/308/)
distinguishes running CPU work from blocked/waiting time. The latter may need
System Trace in a later authorized window; a sparse Time Profiler call tree is
not proof that the residual gap has no cost.

### Preconditions and single recording command

The parent must first own the host window, with compatibility work finished.
Use the already installed optimized Debug app and warm owned simulator; verify
its source/artifact identity and fixture SHA before attributing this trace to
baseline or candidate. If the simulator is shut down, return to the parent for
its normal owned-device setup; this plan does not authorize an automatic boot,
reinstall, build or use of another simulator. Ensure the app is stopped before
recording using the parent's normal process-only termination. No data reset.

The following is a **prepared command, not an executed measurement**. `PROFILE`
is a new directory per attempt, under canonical persistent results. A failed
attempt is kept under its own directory; never reuse/append/overwrite it.
`get_app_container` resolves the installed app rather than launching a build
product copy. Keep the existing baseline/candidate binary and matching symbols.

```sh
set -eu
PROFILE_ROOT=/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018
PROFILE="$PROFILE_ROOT/startup-time-profiler-$(uuidgen)"
mkdir "$PROFILE"
SIMULATOR_ID=3243BEDB-4F6A-4807-AE9E-30115C528377
FIXTURE=/Users/yuanlu/code/one-app/tests/fixtures/today-dataset.json
APP_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.luworks.one app)
test -d "$APP_PATH"
shasum -a 256 "$FIXTURE" > "$PROFILE/fixture.sha256"
xcrun dwarfdump --uuid "$APP_PATH/One" > "$PROFILE/installed-binary-uuid.txt"
python3 - "$PROFILE" "$SIMULATOR_ID" "$APP_PATH" "$FIXTURE" <<'PY'
import json, os, signal, subprocess, sys
from pathlib import Path
out, udid, app, fixture = sys.argv[1:]
out = Path(out)
command = ['xcrun', 'xctrace', 'record', '--device', udid,
           '--template', 'Time Profiler', '--instrument', 'os_signpost',
           '--time-limit', '10s', '--run-name', 'profiled-startup-diagnosis',
           '--output', str(out / 'startup.trace'),
           '--target-stdout', str(out / 'app-stdout.log'),
           '--launch', '--', app, '-uiTesting', '-dataset', fixture,
           '-uiTestingNow', '09:41', '-performanceTrace']
(out / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
status = {'recording_limit_seconds': 10, 'wall_watchdog_seconds': 45,
          'classification': 'profiled diagnosis; excluded from timing comparison'}
with (out / 'record.log').open('w') as log:
    p = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                         start_new_session=True)
    try:
        status['exit_code'] = p.wait(timeout=45)
    except subprocess.TimeoutExpired:
        status['wall_timeout'] = True
        os.killpg(p.pid, signal.SIGINT)
        try:
            status['exit_code'] = p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGTERM)
            try:
                status['exit_code'] = p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                status['exit_code'] = p.wait()
(out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
raise SystemExit(1 if status.get('wall_timeout') else status['exit_code'])
PY
```

Capture host load/context and the exact command through the existing QA command
recorder/journal when executing. The trace's capture duration is capped at 10 s;
preparation/finalization can take additional time, so the watchdog bounds a
stuck preparation attempt. SIGINT allows a save opportunity, but a timed-out or
killed trace is incomplete unless a later read verifies it. Stop after one failed
attempt, retain the exact error, and report simulator launch/template support as
unverified or rejected by this runtime. Do not silently switch to attaching
**after** launch (which loses the critical startup interval), run the simulator
executable directly on macOS, change privacy/profiling settings, or repeatedly
retry under another holder.

### Export and hotspot summary

Only after xctrace exits, inspect `status.json` and `record.log`; verify the trace
contains the intended One PID and actual startup frames/signposts. A successful
CLI exit with no target samples is not a useful profile. Preserve the untouched
`startup.trace`. If symbolication is required, use `xctrace symbolicate --input`
with `--output` pointing to a **new** `startup-symbolicated.trace` and the matching
dSYM, never the default in-place output. Confirm binary UUID/symbol match first.

Installed `xctrace help show` returns `Unknown command name: 'show'`; do not use
online examples of `xctrace show --calltree` on this version. The supported path
is XML export, inspecting the actual TOC before choosing a schema:

```sh
xcrun xctrace export --input "$PROFILE/startup.trace" --toc \
  --output "$PROFILE/toc.xml"
python3 - "$PROFILE/toc.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for run in root.findall('run'):
    for table in run.findall('./data/table'):
        print(run.attrib, table.attrib)
PY
```

Export only a table schema actually listed by that TOC. For example, **if** run 1
lists `time-profile`, the exact supported command is:

```sh
xcrun xctrace export --input "$PROFILE/startup.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output "$PROFILE/time-profile.xml"
```

If it instead lists `time-sample`, use that literal schema in the same XPath and
name the output accordingly. Inspect the exported column definitions and first
rows before writing a reducer; do not guess column order, backtrace direction,
weight units, thread/PID attributes or id/ref resolution. Export the actual
os_signpost table likewise. A schema-independent **automatic** hotspot reducer
cannot be certified before this first trace's TOC/rows exist; report that limit
rather than presenting guessed XML parsing as a verified summary command.

The parent then retains a compact `hotspots.json` or `hotspots.md` alongside the
raw XML: source UUID, trace/run/PID/main-thread identity, selected timestamp
intervals, schema/weight units, top 10 inclusive and self symbols (with system
frames visible), sampled weights/counts, and unresolved-symbol fraction. Resolve
XML id/ref references before aggregation and do not sum inclusive weights across
parent/child frames. Use captured signpost timestamps to split init→bootstrap,
bootstrap and post-bootstrap; inspect a whole-startup interval too. Keep idle
time outside the startup span out of the hotspot percentages. App uptime and
trace-relative time are different coordinate systems; align via the captured
signpost events rather than assuming identical zero points.

Finally, import/index the **completed** profile directory with
`journal.py import <PROFILE> --session performance-climb-20261018 --status
passed|failed --archive`, after all exporters stop writing. This retains raw
trace/XML/stdout/errors with paths and hashes. Put profiled durations in diagnosis
only, separate from the existing unprofiled n=3 optimized Debug timing baseline.
Neither recording a profile nor observing a hotspot establishes a 3x gain.

### Existing-log limits for the cancellation hypothesis

The existing baseline xcodebuild log contains no runtime `sync: <n> alarm` entry;
compiler source diagnostics mentioning Ringer are not execution evidence. There
are also no per-generation debounce/cancellation markers. Even an available
Ringer sync log would count reconciliation entries, not identify cancelled
parents. Time Profiler sample frequency is not invocation count. Read-only
xcresult console export may add diagnostics, but zero matching exported log
lines must be reported as missing evidence, not zero cancelled passes. Do not
modify indexed xcresult bundles or add probe/production markers in this lane.

Read-only console export from the completed baseline xcresult returned exit 1:
`Error: No console log available`. The command status and raw installed-help
outputs are retained under canonical `startup-profile-plan-20261018/`; this is
an evidence-availability failure, not a finding of zero reconciliation passes.

## Round 1 raw trace: read-only coverage audit

Source artifacts (unchanged) are under canonical
`tests/results/runs/performance-climb-20261018/startup-profile-round1/`.
`status.json` says passed for capture and TOC export; this is **not diagnostic
proof** of complete app initialization or a usable-content boundary. The parent
verified the installed One executable identity against its product. The trace
records iOS Simulator / Today-Performance, the expected fixture/pinned-clock/
performanceTrace arguments, Today PID 6261, and a nominal 10 s recording.

Read-only XML source identity:

- `time-sample.xml`: 2,228,193 bytes, SHA-256
  `622bf2017730ca8ea18a47dad9d7f5d19ad77d84557a952c42e1b9dadf5dcb69`.
- `toc.xml`: 7,770 bytes, SHA-256
  `4f2ccafa712a04e82b3bf4d69cd0cacf547379738110a589f0b46862e0a03067`.
- `app-stdout.log`: zero bytes. No stage endpoint can be recovered from it.
- Recorder warning: `This configuration of instruments creates 1 table without
  a known input source.` The warning does not identify that table; neither
  successful export nor this warning establishes which diagnostic data is absent.

The actual `time-sample` schema has seven columns, in order: `time`, `thread`,
`core-index`, `thread-state`, `cp-kernel-callstack`, `cp-user-callstack`,
`sample-type`. The parser indexed every XML element carrying `id`, recursively
resolved `ref`, and read nested thread → process → pid and thread → tid values.
There are 8,365 ids and 22,551 references, with zero unresolved references.
Sentinel fields remain missing data, not numeric zero or named symbols.

All 3,184 rows belong to PID 6261, across 11 distinct thread IDs. The first
sample is at trace-relative 0.534067041 s and the last at 10.600763500 s. The
TOC reports duration 10.685856 s; the last sample is about 85.093 ms before its
end. Main thread TID 13129958 (`0xc858e6`) has 2,354 rows: 2,352 Running and 2
Blocked. Those two Blocked rows resolve to the **same** initial timestamp and
stackshot; they are not evidence of two distinct waits. The remaining ten
threads have 830 Running rows. Overall sample kinds are 3,182 Timer Fired and
2 Stackshot. Do not treat these row counts as call counts, CPU percentages or
measured durations, and do not sum stackshot and timer samples as equal weights.

Raw rows by integer trace second, retaining duplicates: second 0 has 280 Running
plus 2 Blocked; seconds 1/2/3/4/5/6/7 have 801/480/14/168/329/789/318 Running
rows respectively. Seconds 8 and 9 have no rows. The final three Running samples
are on the main thread at 10.598766291, 10.599764625 and 10.600763500 s. This
shows the target was sampled near recording end; a sparse interval alone is
not proof of app death. The TOC end reason is `Time limit reached`; its launched
process reports `return-exit-status=0`, `termination-reason=exit(0)` without an
exit timestamp. It cannot establish an early app exit or natural lifetime.

The exported `kperf-bt` records contain raw PCs, numeric address sequences and
register values, not resolved function/image names. No address is assigned to
SwiftUI, dyld, One, Ringer or any other image in this audit. There is **no standalone
binary-image/load-address table in the actual TOC**. The raw table does not
certify `OneApp.init`, bootstrap completion, first usable content or the layout
proxy endpoint; empty stdout could have several causes and is not proof the
flag was ignored or initialization failed. No app-stage durations, cancelled
reconciliation counts, named hotspots or startup optimization are justified yet.
The dense-Year component result and UI-level result remain separate evidence;
neither supplies the missing startup attribution.

### Next parent-only bounded union export (prepared, not executed)

The actual TOC lists `time-profile`, `process-info`, `thread-info`,
`life-cycle-period`, and an unfiltered SINGLE-target `os-signpost` table plus
its unfiltered `os-signpost-arg` table. Other signpost tables filter categories
such as PointsOfInterest; this app uses category PerformanceTrace. The query
below therefore includes only the signpost tables without category/subsystem
filters, along with the four relevant tables. `time-profile` may contain modeled
frames/image metadata; inspect its actual schema/rows before claiming symbols
or image mappings. Empty tables remain explicit evidence gaps.

Run only after the parent's global handoff. This command **only exports** the
existing immutable trace and writes to a new sibling results directory, outside
`startup-profile-round1`. It does not record, boot, build, install or modify
source/probe settings. Each attempt gets a new directory; never overwrite a
partial export or place new artifacts inside the raw profile directory.

```sh
python3 - <<'PY'
from pathlib import Path
import json, os, signal, subprocess, time, uuid
root = Path('/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018')
trace = root / 'startup-profile-round1/startup.trace'
out = root / ('startup-profile-round1-export-' + uuid.uuid4().hex)
out.mkdir(exist_ok=False)
xpath = ("/trace-toc/run[@number='1']/data/table["
         "@schema='time-profile' or @schema='process-info' or "
         "@schema='thread-info' or @schema='life-cycle-period' or "
         "((@schema='os-signpost' or @schema='os-signpost-arg') "
         "and not(@category) and not(@subsystem))]")
command = ['xcrun', 'xctrace', 'export', '--input', str(trace),
           '--xpath', xpath, '--output', str(out / 'startup-union.xml')]
(out / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
status = {'status': 'running', 'export_timeout_seconds': 15,
          'classification': 'read-only diagnostic export; not a timing sample',
          'source_trace': str(trace)}
started = time.monotonic()
with (out / 'export.stdout.log').open('x') as stdout, \
        (out / 'export.stderr.log').open('x') as stderr:
    p = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
    try:
        status['exit_code'] = p.wait(timeout=15)
        status['status'] = 'passed' if p.returncode == 0 else 'failed'
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        status['status'] = 'interrupted-or-timeout'
        for sig, grace in [(signal.SIGTERM, 3), (signal.SIGKILL, 2)]:
            if p.poll() is not None:
                break
            try:
                os.killpg(p.pid, sig)
            except ProcessLookupError:
                break
            try:
                p.wait(timeout=grace)
                break
            except subprocess.TimeoutExpired:
                pass
        status['exit_code'] = p.poll()
        if p.poll() is None:
            status['unreaped_pid'] = p.pid
status['elapsed_seconds'] = time.monotonic() - started
(out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
print(json.dumps({'output': str(out), **status}))
raise SystemExit(0 if status['status'] == 'passed' else 1)
PY
```

This bounds exporter wait plus termination grace to 20 s; a partial XML on
failure is retained and not parsed as complete. No retry or fallback schema
export runs automatically. Parent records the command/host window through the
QA journal and indexes the new export directory only after writers exit, while
preserving the original trace. A zero exit establishes export success only;
the reducer must next validate table identity, PID/thread attribution, id/ref
scope and interval coverage against actual rows.

If the union includes usable frame/binary-image records, require image UUID,
architecture, runtime load address/slide and correct image path before an
`atos` lookup. One launcher UUID alone does not identify a separate
`One.debug.dylib`, if present. Never assume the raw `0x102...` addresses belong
to the main image or reuse a slide from another process. If image metadata or
symbol names are absent, the next possible command is a separately bounded
`xctrace symbolicate --input <original.trace> --output <NEW-symbolicated.trace>
--dsym <matching-symbol-directory>` using verified matching UUIDs; no in-place
symbolication, guessed load bias or new recording is part of this export plan.
Until those requirements are met, keep address-only results as address-only
results and do not select a production startup candidate.


## Round 1 modeled union: phases and sampled hotspots

The new modeled export supersedes the earlier **raw-table diagnostic limit**:
there are now resolved frames and all six app endpoint signposts, so this
recording did reach init, store, bootstrap completion and the layout proxy.
Empty stdout did not mean those operations were absent. This remains a profiled
simulator diagnosis, not shipping usable-content timing or a 3x comparison.

Source (read-only): `startup-profile-round1-export-710a864cb0864d88a45154845aef93d0/startup-union.xml`,
7,487,241 bytes, SHA-256
`8305050a9087956fa997fac82b8cddc7484479abbce70d747dfec02d66ec334d`.
Independent reducer/results are in canonical
`tests/results/runs/performance-climb-20261018/startup-profile-round1-analysis-20261018-v1/`:
`reduce_union.py`, `analysis.json`, `reduction.log`, and
`main-conformance-stacks.json`. Original trace/export files were not modified.
Only local Python XML parsing and source/document reads ran in this lane.

The document has 39,730 unique ids and 220,234 refs, all resolved globally across
nodes (later nodes reference ids defined in earlier nodes). The actual TOC
binds the six node XPaths to lifecycle/signpost/process/thread/signpost-arg/
time-profile tables with respectively 0/201/1125/8800/192/3182 rows. Only the
empty lifecycle table repeats inline schema; typed row tags plus the actual
TOC establish the other table identities. Process/thread metadata also includes
other host processes; modeled CPU rows are filtered/validated as PID 6261.
All 3,182 modeled rows are Running with explicit weight `1000000`, formatted
`1.00 ms`; they exclude the raw table's duplicate initial Blocked stackshots.
Two modeled rows have sentinel backtraces, retained as missing (2 ms), not
invented zero-cost samples. The main thread is TID 13129958.

There are 83 actual frame-associated image records. One is arm64,
UUID `B9F46924-D104-30AB-90CA-4CA5A4B47A0E`, load address `0x100e0c000`;
its path ends in installed `One.app/One`, matching the parent's verified product
identity. No One.debug.dylib is present, consistent with the parent's product
inspection. dyld_sim is UUID `6FAE6738-0877-3F55-80B9-6AE42FCB8606`,
load `0x102338000`; dyld is UUID `DF42DD9D-AD11-33A7-8849-9AD5DF30A274`,
load `0x1021e0000`. These are exported mappings, not guessed load biases.
Raw address and `<deduplicated_symbol>` frames remain unresolved/ambiguous;
placeholder frames are keyed by actual image UUID **and address**, never merged
as if they named one function. No atos or symbolication was needed or run.

### Real phase alignment

PerformanceTrace events occur at trace-relative seconds:
`4.083156500` begin launch; `4.094018125` store_start;
`4.644169958` store_ready; `5.984589541` bootstrap_start;
`6.073906166` bootstrap_complete; `6.479088666` PerformanceSample.
The final signpost contains the app's monotonic report:
`ms=2396.860334; init_to_store_ms=11.024792; store_ms=550.936833;
bootstrap_ms=89.308917; post_bootstrap_layout_ms=405.16475`.
These are **profiled diagnostic values only**; retain the unprofiled baseline.

The reducer bins samples using the captured trace-event boundaries, not an
assumed shared zero between app uptime and trace time. Signpost event times
and embedded app-clock values differ slightly because timestamp capture,
logging and scheduling are separate operations; no sub-millisecond phase
precision is claimed. Before-launch-marker is not strictly before OneApp.init:
probe singleton/metadata initialization can precede its begin event.

Main-thread sampled weights by captured phase are 1,589 ms before launch
marker, 3 ms init-overrides, 90 ms store, 287 ms store→bootstrap, 31 ms bootstrap,
210 ms post-bootstrap, and 142 ms after endpoint. App-init→endpoint totals
621 ms on the main thread / 805 ms over all target threads. Sample weights
are statistical CPU attribution, **not** wall durations, continuous occupancy,
call counts or proof of why the rest of a wall interval was unsampled.

### Top 10 in the target interval

Scope is main thread, begin-launch signpost through PerformanceSample. Self is
the first modeled leaf frame; inclusive weights de-duplicate recursive visits
to the same image+symbol within each sample. Inclusive rows overlap and must not
be summed. Ties are ordered deterministically by image UUID and symbol key.
Full symbol signatures, per-phase/all-thread lists and addresses are in JSON.
`swift_conforms…` below denotes the complete exported
`swift_conformsToProtocolMaybeInstantiateSuperclasses` signature there.

| Rank | Self symbol (image), sampled ms | Inclusive symbol (image), sampled ms |
| --- | --- | --- |
| 1 | swift_conforms… (libswiftCore), 214 | static App.main() (SwiftUI), 558 |
| 2 | __open (libsystem_kernel), 15 | start_sim (dyld_sim), 558 |
| 3 | __openat (libsystem_kernel), 12 | main (One), 558 |
| 4 | pthread_setspecific (libsystem_pthread), 6 | static OneApp.$main() (One), 558 |
| 5 | madvise (libsystem_kernel), 6 | start (dyld), 558 |
| 6 | getMethodFromRelativeList (libobjc), 6 | runApp (SwiftUI), 465 |
| 7 | unresolved deduplicated symbol at 0x102230a89 (dyld), 6 | closure #1 in KitRendererCommon (SwiftUI), 457 |
| 8 | _xzm_malloc_tc (libsystem_malloc), 5 | UIApplicationMain (UIKitCore), 457 |
| 9 | objc_msgSend (libobjcMsgSend), 5 | GSEventRunModal (GraphicsServices), 443 |
| 10 | _swift_class_getSuperclass (libswiftCore), 5 | _CFRunLoopRunSpecificWithOptions (CoreFoundation), 443 |

The target interval's main-thread unresolved/ambiguous leaf weight is 54/621 ms
(8.70%); none of its main-thread backtraces is missing. Whole-recording main
weight is 2,352 ms, including 1,349 ms unresolved/ambiguous leaves and 1 ms missing
backtrace, mostly before the launch marker. That earlier segment is dominated
by dyld/dyld_sim stacks; it is **outside this app-init denominator** and cannot
be credited as an improvement to it.

### Decision: no app-owned candidate justified yet

The conformance leaf accounts for 214/621 ms (34.46%) sampled self weight in the
target interval: 63 ms store, 105 ms store→bootstrap, 12 ms bootstrap, 34 ms
post-bootstrap. Exact main-thread stacks show 63 ms via SwiftData setup in
`OneStore.container`; 131 ms have no One frame beyond entry points. Among first
non-swiftCore callers are SwiftUICore DynamicPropertyCache.fields (63 ms) and
BodyAccessor.makeBody (17 ms). These are concrete runtime/framework costs, but
the export does not identify one safely removable app model/property/view.
Removing schema models or postponing required store initialization would break
migration/first-content constraints and is not an accepted candidate.

The earlier cancellation hypothesis is now **deprioritized as a dominant startup
candidate**, not proven false: post-bootstrap Ringer.sync/AlarmScheduler.reconcile
has 9 ms inclusive main-thread weight; DayAgenda.items has 7 ms. Neither sample
count reveals repeated cancelled invocations. The data does not support a
credible >5% startup wall-time gain from changing that debounce. Do not infer a
speedup from avoiding those sampled milliseconds, or treat async waiting as CPU.

No production startup optimization is selected. This is an attribution limit,
**not a plateau conclusion**. The next evidence needed is concrete ownership of
the dominant metadata/graph cost (which app view/property causes repeated cold
metadata/conformance work), or scheduler/wait attribution for the residual wall
intervals, under a separately granted host window. Until that maps to a narrow
behavior-preserving change, keep required work and endpoint semantics intact.
The new package ZIP-only increment and dense-Year component speedup are separate
tracks; the overall app-level 3x startup target remains unmet.
