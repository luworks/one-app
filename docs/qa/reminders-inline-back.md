# Reminders inline back header

## Change

`ReminderListScreen` hides its native navigation bar and places a plain, adaptive
chevron in the existing title/count row. It uses the current dismiss action and
NavigationStack; no custom pan gesture or global navigation change is introduced.
The back button keeps the destination label `Lists` and adds `reminders.back`.
Both back and the relocated user-list `More` menu have a minimum 44 × 44 pt target.
Existing title/count accessibility, completed controls and menu actions remain.
Titles can wrap at larger Dynamic Type sizes; smart-list counts stay together.

The owner's dark-mode screenshot establishes the original separate circular back
row. It is input evidence, not a rendered result of this change. The source image
is retained and indexed in the canonical QA journal under session
`inline-reminder-back-chevron`.

## Source verification

- Based on `origin/main` at `c42b88e6712882f1d627d68d5769913d959bc72c`.
- Read AGENTS.md, CLAUDE.md, ios/README.md and Issue 32 before implementation.
- One focused self-review checked dismissal, More actions, labels/IDs, adaptive
  styling and retained stack/path ownership. `git diff --check` passed.
- RemindersView.swift, HomeView.swift and reorder/drag-drop code are untouched.
- No build, Swift test, simulator UI or physical-device checks ran. The coordinator
  reserved the machine for compatibility QA and a performance quiet window.

## Pending coordinated UI slot

Run once, serially, through `ios/Eval/run-e2e.py` with its durable default output:

1. `RemindersListsTests/testSmartListPillsAreOneRowAndTappable`: existing smart-list
   journey plus All/count accessibility, 44 pt back target and parent pill position.
2. `TabMemoryTests/testTabsKeepTheirPlace`: user list, tab restoration, More/editor,
   sidebar, inline back, parent list position and native edge-swipe return.
3. `CRUDTests/testListCreateRenameDelete`: existing list action/back journey with
   the new back selector.

Inspect All and a user list in light/dark appearance and a large accessibility
text size during that slot: chevron/title/count alignment, wrapping, no separate
or duplicate back row, and visible global tabs/menu. Native edge-swipe behavior
with the hidden bar is explicitly pending runtime verification. Do not merge or
install on a phone until the coordinator accepts this evidence.

## Native edge-back diagnosis (pending)

Candidate A (`9435048`) disables the dormant drawer gesture at recognition time.
The coordinator reports the unchanged isolated TabMemory method still failed at
integrated `73b7565` (43.655 s). A is insufficient and is not an accepted fix.
Original evidence remains in the canonical results directory at
`runs/ai-final-integrated-20261018/header-A`. This PR remains a draft.
Do not ship A by default as a confirmed fix; coordinate its experimental retention
or removal after the active compatibility build ends, in the same source tree.

The DEBUG-only `-debugNativePopProbe` app argument enables a passive controller
embedded in the list detail. For the existing TabMemory method, set test-runner
environment `ONE_DEBUG_NATIVE_POP_PROBE=1`; without it the method is unchanged.
The coordinator can pass this through their test configuration (or the standard
`TEST_RUNNER_ONE_DEBUG_NATIVE_POP_PROBE=1` forwarding when invoking xcodebuild).
Environment forwarding and probe compilation/runtime are not yet verified.

The probe walks only its own UIKit parent/navigation-controller chain, never
searching global windows. It records navigation/recognizer identity, enabled,
delegate type/identity, state, stack depth, transition-coordinator presence,
top/visible controller type/identity, navigation-bar visibility and whether its
view has a window. No personal titles or reminder content are recorded. It adds
an observation target and samples every 50 ms; output is written on changes or
once per second to `Library/Application Support/NativePopProbe/<UUID>.jsonl` in
the app data container (one file per probe instance, no truncation of old files).
A `NativePopProbe:` console line also identifies the output path. Copy all files
after the single diagnostic journey, before another launch or app reset, into
the canonical run's attachments and index their hashes with the QA journal.

Use the coordinator's existing `simctl get_app_container <owned-device>
com.luworks.one data` retrieval workflow once a diagnostic run is authorized.
No new framework or standalone runner is needed. The timer and observation target
are removed on dismantle. Neither recognizer state/enabled/delegate nor the
navigation stack is mutated. No private APIs, proxy delegate, swizzling or
replacement swipe-to-dismiss behavior are installed.

Observation limits: target-action does not guarantee delivery for recognizer
failure, and 50 ms sampling can miss a transient failed/cancelled state. Report
`failed` only if observed; no target callbacks plus `possible` samples does not
prove a delegate veto. Transition-coordinator presence does not prove an active
interactive transition. A missing navigation controller is explicitly logged as
`nil`/`unavailable`, not mistaken for a disabled recognizer. Probe timing itself
adds small DEBUG-only overhead. Do not mix this diagnostic with candidate B or
weaken the original native-back assertion.
