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
