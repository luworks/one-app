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
No product fix is included in the final infrastructure delivery.

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

Issue #62 remains open. The ForEach insertion-index candidate (`7de52de`) was
built and failed the unchanged 1.5 s regression in the integrated small-screen
batch. The final PR restores `RemindersView.swift` to main; it delivers the reusable
runner, matrix, strict test diagnostics and evidence, without an unproven fix.

## Integrated follow-up evidence

The same source path and incremental build cache were retained. Separate copied
Products and output directories identify each frozen revision:

| Revision / run | Device | Selected results |
| --- | --- | --- |
| `dc51a26`, header-integrated/small | SE 3 | Smart-list back/count/scroll passed; reorder and native edge-back failed (1/3 passed) |
| `dc51a26`, header-integrated/standard-ai | iPhone 16 | Old title-editing source `05ea0d9`: 3/3 passed |
| `dc51a26`, header-isolated | SE 3 | Original TabMemory edge-back failed alone at low preboot load (42.523 s) |
| `73b7565`, ai-final-integrated/header-A | SE 3 | Drawer gesture candidate A: same edge-back failed (43.655 s) |
| `73b7565`, ai-final-integrated/ai-core | iPhone 16 | Final title source `3881c77`: 2 passed; context `7f47288`: 3 shared locator failures |

The original header failure persisted without the earlier load-106 confounder.
Exported AX and final frame show the Home detail still visible after native edge
swipe. Candidate A is insufficient; neither a recognizer root cause nor a fix is
established. PR #63 remains unaccepted. Its later diagnostic probe was not built
or executed in this batch.

The final integrated app built successfully once (`73b7565`). Its targeted Swift
ConversationJourneyTests passed 2 methods / 13 fixture journeys. The two title UI
checks passed the Chinese title/time and actual alarm Add, title Save/Cancel,
stored-card reopening and Undo. These results apply to final production behavior
`9b6ea3c`, not just the earlier `05ea0d9` acceptance.

All three context UI checks stopped at their first title locator. One existing
Chinese failure AX proves `capture-stack` exists, with a `capture-title` **Button**
labelled `一定不能再吃饭了`, `New reminder`, `Today 18:00` and Add. The helper
queried StaticText. This is a shared harness mismatch, not evidence of missing
capture/title content; later context/time/confirmation assertions did not execute.
The author owns the narrow selector correction. No equivalent UI retries followed.
PRs #65/#69 are not jointly accepted on this evidence.

At approximately 11:02 PDT, both final runners had shutdown exit 0 and no journal
errors; live booted devices and heavy runner checks were empty. The performance
thread received the next quiet window. No further matrix or Pro Max run is planned.

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
- `runs/compatibility-header-{build,integrated,isolated}-20261018/`: frozen old
  title/header integration and unchanged isolated edge-back evidence.
- `runs/ai-final-conversation-logic-20261018/` and `runs/ai-final-build-20261018/`:
  final targeted logic and incremental build logs.
- `runs/ai-final-integrated-20261018/`: final frozen Products identity, Header A
  and AI-core logs, summaries, attachments and complete xcresult bundles.
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
