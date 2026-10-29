# Reminders shared cards

Owner request: My Lists should use the same UI components and card rhythm as World Clock, superseding the grouped-row appearance for My Lists only. Context: [issue #32](https://github.com/luworks/today/issues/32).

`StackedCard.swift` supplies the shared surface (12pt circular corners, 16pt inner horizontal padding) and native List row treatment (15pt outer gutters, 1pt vertical insets, no separators). Both city cards and My Lists instantiate it. World Clock retains its time-of-day gradient, 82pt height, 78pt flat graph layout, content and gestures. My Lists uses each list's color at an adaptive opacity with primary text on a plain system background. List cards grow with Dynamic Type and wrapping titles. Smart and pinned selectors remain on `PillStyle`.

Lists still navigate through the existing `ReminderTarget` path. A plain button opens each list so the whole card owns the disclosure indicator and tap target; this avoids the native List chevron outside the card. Context menus, swipe actions, move/delete hooks and drag/drop handlers remain. The default list and Add List remain accessible with their existing identifiers. Drag previews use the same card and retain pinned state.

## Verification state

- Both owner reference screenshots inspected; one focused source review completed; `git diff --check` passed.
- No build, logic test, simulator UI run or physical-device run performed. The parent owns sequential runner scheduling; Health currently owns Today-Codex and its derived data, with Year queued next.
- Existing reusable data: `tests/fixtures/today-dataset.json` (see the fixture catalog). No cosmetic-only test or new dataset added.
- Development actions and PR link are recorded in the QA journal under session `reminders-shared-cards`; its database remains in the primary checkout's `tests/results/`.

## Intended acceptance (at most three journeys after UI slot grant)

1. Open Home from its card, confirm its displayed open count against the existing dataset, navigate back and reach Add List; inspect light/dark appearance and a long title.
2. `RemindersListsTests/testLongPressDragReordersLists`, plus focused manual checks of the existing Rename / Color & Icon / Pin / Delete menu and trailing swipe actions within this management journey.
3. `ClockTests/testScrubbing`, with a visual comparison of normal city cards and the flat graph toggle to confirm World Clock remains unchanged.

Pending risks: native List drag/swipe behavior after the row-style change, rendered accessibility labels and full-card hit area, long titles and larger text, and exact light/dark contrast require runtime verification. This is ready for UI verification, not an acceptance claim.
