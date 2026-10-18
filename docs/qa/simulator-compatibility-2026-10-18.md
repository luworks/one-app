# Simulator screen compatibility — 2026-10-18

## Scope and support

Base/build app source: `c42b88e6712882f1d627d68d5769913d959bc72c`.
Read AGENTS.md, CLAUDE.md, ios/README.md and issue #32 before execution.
Project deployment target: iOS 27.0. All configured targets use
`TARGETED_DEVICE_FAMILY = 1` (iPhone). iPad is outside the project's device family.
Only iOS 27.0 (24A434) is installed. The SDK's generated xctestrun filename says
27.1; that is not evidence of running an iOS 27.1 simulator.
Runtime `supportedDeviceTypes`, not the global historical device-type catalog,
is used to validate matrix eligibility. Model availability here means simulator
support; it does not establish real hardware's OS eligibility or capabilities.

| Lane | Simulator model | Logical portrait size | Display | Evidence |
| --- | --- | --- | --- | --- |
| small | iPhone SE (3rd generation) | 375 × 667 | light, Large | 4 passed / 1 reorder failure |
| standard | iPhone 16 | 393 × 852 | light, Large | 4 passed / 1 reorder failure |
| mini | iPhone 13 mini | 375 × 812 | dark, XXXL | 5 passed; 0.5 s pickup variant |
| baseline | iPhone 18 Pro Max, Today-Codex | 440 × 956 | baseline settings | Inherited same-code evidence from issue #32 |

Pro Max evidence is inherited from the owner's previous integration batches on
`8770937`, whose app tree was delivered at `c42b88e` (14 distinct selected methods
with passing latest evidence across batches, not a full final-revision suite).
No duplicate Pro Max UI batch is required for infrastructure-only changes.

## Execution and assertions

Owner explicitly superseded the initial single-runner rule for this task:
start two distinct-device runners, allow at most three if host load permits.
A single `build-for-testing -jobs 2` completed successfully. Its finished Products
were copied intact to lane-owned caches; two `test-without-building` processes
use different UDIDs, caches and output directories. No concurrent compilation.
Fresh dual boots caused substantial first-run system migration/Metal work;
therefore no third concurrent device was added.

Each new lane selects five existing methods: Health visibility toggles and
persistence; exact Year day → Month selected day and matching items; My Lists
rename/navigation; My Lists drag reorder; World Clock both scrub directions and
NOW reset. The assertions are retained. Existing fixed bottom-clearance/edge
coordinates were inspected before running; future failures must be diagnosed
against actual control frames before changes.

Reusable entrypoint: `tests/qa/compatibility.py`, with permanent matrix in
`tests/qa/compatibility.json`. No new dataset is required; existing canonical and
Year agenda fixtures remain under `tests/fixtures/`. Runner reference and build
commands are in `tests/qa/README.md`.

One focused infrastructure review identified and resolved parent signal
forwarding, actual model/runtime validation and relative-path relocation issues.
Host checks: 12 runner contracts and 3 product-relocation/command checks pass.
No package logic changed, so no duplicate pure Swift run was required.
The list-drop product candidate below is awaiting simulator regression.

## Reorder diagnosis and handoff checkpoint

The initial two devices each ran five methods: 4 passed, 1 failed (My Lists drag).
The exact original method failed again alone on SE 3, excluding parallelism as a
necessary cause. Frame/event evidence places both points inside the visible
cards and clear of the sidebar edge. Original 1.5 s pickup leaves a menu covering
the target and incurs the XCTest 60 s animation-idle wait. A NavigationLink
candidate failed and was reverted. A 0.5 s pickup removed that idle wait but still
failed on SE 3; it passed on Mini. This is not a proven cross-screen harness fix.
The original 1.5 s real drag and strict final order assertion are restored in source,
with added full-visibility/frame diagnostics. No assertion was weakened.

Issue #62 tracks the reproduced failure. The next candidate (`7de52de`) moves
String drops from individual View rows to the native ForEach insertion-index
API, keeping native onMove, card styling and existing persistence/Activity paths.
Local SDK confirms DynamicViewContent's `([String], Int) -> Void` overload. This
candidate is **not built or runtime-accepted at this checkpoint**. It must pass
the original regression before being called a fix.

At 10:23:53 PDT, Mini's 5/5 batch was complete, all compatibility simulators were
Shutdown and host checks found no xcodebuild/Swift-test/UI runner. The performance
thread received the quiet window, so no new heavy work starts until it returns it.
PR #63's inline reminder header will then integrate on this same source path and
incremental cache. The small-screen batch will select reorder plus smart-list
back/count/scroll and tab-memory/More/native-edge-back journeys (three methods).
No hardware-matrix expansion or repeated Pro Max baseline is planned.

## Durable evidence

Canonical root: `/Users/yuanlu/code/one-app/tests/results/`.
Commands, observed XCTest UI operations, lifecycle/results and hashes are indexed
in the separate QA `activity.sqlite`, never the app's user Activity database.

- `runs/compatibility-build-20261018/`: complete build log and result.
- `runs/compatibility-discovery-20261018/`: actual installed runtimes/device types,
  devices, Xcode version and project settings.
- `runs/compatibility-pair-20261018/`: per-device logs, summary/progress and complete
  `ui.xcresult`; separate `*-cache` directories hold copied build products.
- `runs/compatibility-reorder-isolated-20261018/`: unchanged isolated failure.
- `runs/compatibility-reorder-{build,fixed}-20261018/`: rejected NavigationLink candidate.
- `runs/compatibility-gesture-build-20261018/` and `runs/compatibility-gesture-20261018/`:
  pickup timing diagnostic.
- `runs/compatibility-mini-20261018/`: complete dark/XXXL 5/5 batch on `ed3a2da`.
- Exported failure movies, accessibility snapshots, synthesized event coordinates
  and filmstrips are retained beside their completed bundles and indexed separately.

No live xcresult was archived or moved. Completed bundles remain in canonical
storage indexed by path/hash. Display settings are explicit in lane summaries.

## Limits and remaining work

Simulators exercise layout, accessible controls, gestures, mocked Health data and
app state. They cannot validate actual RAM/GPU/thermal/radio/sensors, real
HealthKit permission/data/performance or physical AlarmKit ringing. No phone
build, install, signing or physical-device acceptance belongs to this task.
Cross-OS verification is unavailable because only one runtime is installed.
Dark/XXXL selections are behavior smokes, not comprehensive visual/a11y sign-off.
