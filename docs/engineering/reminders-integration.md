# FeatureReminders integration handoff

The five authorized real sources moved from `ios/One/` to
`ios/Sources/Features/FeatureReminders/`. No model, package, project, shared row,
service, or configuration source was edited. English UI copy and the existing
smart-list filters/order, pinned/list drag behavior, inline add, list deletion
confirmation/delayed delete, completion/Undo actions, and editor saves remain.

## Assembly and package APIs

- Package entries: `RemindersView`, `ReminderListScreen`, `QuickReminderSheet`,
  `TaskEditor`, `ListEditor`; each has an explicit package initializer and package
  `body`. `ReminderTarget` and its associated `SmartList` are package values.
- Construct `RemindersView(isPushed:path:sync:requestAccess:)` with the existing
  `RemindersSync` instance and a required `@MainActor () async -> Void` callback.
  Production must call the existing `FirstRun.reminders()` through this callback.
  Its `.task` invokes the callback; there is no default empty action. Keep the
  existing TODAY_MOCK axe guard at assembly (`PreviewFixtures.isAxe`), before
  requesting access. The original My Lists `#Preview` fixture block was removed
  from the production feature source; root can recreate it in Workbench using
  `PreviewFixtures.reminders` and a deliberate preview permission action.
- `QuickReminderSheet(listName: = "")`, `TaskEditor(task: = nil)`,
  `ListEditor(list: = nil, onCreated: = nil)` retain their editing defaults.
  `ListEditor.onCreated` is explicitly MainActor and still propagates a newly
  created list into `TaskEditor.listName`.
- Shared `TodayPlannerUI.TaskRow` must accept required
  `open: @MainActor (OneTask) -> Void` after its existing options. Both open and
  completed rows pass `open: { editingTask = $0 }`; `ReminderListScreen` presents
  its own `TaskEditor(task:)` in a local item sheet. Shared rows must invoke the
  supplied action for tap and Show Details, retaining existing performance hooks,
  completion/Undo and all row options. No other feature editor is imported.
- Direct target dependencies named by these files: One, TodayCore, TodayData
  (`ActivityEvents` in quick add), TodayPlatform, TodayDesignSystem,
  TodayPlannerUI. FeatureClock/FeatureHealth/TodayShared imports were removed.
  Root owns actual manifest dependencies and original-source membership removal.

## Required root-owned declarations

Expose the existing APIs with package access, without changing their behavior:

- `OneTask`: initializer with title/note/due defaults; title, note, createdAt,
  plannedStart, durationMinutes, due, dueHasTime, isDone, doneAt, isOverdue,
  listName, tags, flagged, reminderOffsetMinutes, repeatRule, repeats, checklist,
  ringsAsAlarm; SwiftData identity/query access remains intact.
- `OneList`: order/name query fields, colorIndex, symbol, color, pinned and
  SwiftData identity; `ReminderPalette.color`, `.colors`, `.symbols`.
- `RemindersSync.isDenied`; `Ringer.isAvailable` and `.isDenied`;
  `UndoToast` environment type;
  `TaskActions.toggleDone(_:context:toast:)` and `.delete(_:context:toast:)`.
- `ListActions.nameProblem`, `.rename`, `.create`, `.delete`, `.taskCount`,
  `.togglePinned`, `.reorder` with existing labels/results.
- `Ledger.record(.created,task:title:after:context:)`, `LedgerFormat.time`,
  `ActivityCenter.record`; retain their nested action/result visibility.
- Existing Core values/helpers used unchanged: ListName, PillOrder,
  NewReminderDraft, ReminderSuggest (including Suggestion/Input initializers),
  QuickTime (including nested Day/preset values), RepeatRule, ChecklistItem,
  DayLabel, Preferences.newReminderList, ReminderOffset. These already extracted
  Core declarations must remain accessible. Platform performance trace hooks,
  DesignSystem pills/rows/stacked cards/PressScale also need their existing
  constructors available across package targets.

## Required root-owned shared splits

`ListGlyph` remains a package declaration with explicit
`init(color:symbol:size: = 30)` in `ListEditor.swift`, as requested. Root must move
that declaration once into TodayDesignSystem for Settings, removing this local
declaration and adding the DesignSystem import back to ListEditor when needed.
`reminderCountText` remains internal here; root may move the unchanged formatter
with the glyph if it becomes shared.

`SmartList` and `SmartListLayout` remain package declarations in RemindersView
because this lane cannot write Core/DesignSystem. Settings currently consumes
both: root must split identity/title/symbol plus layout/keys/order into TodayCore,
color into TodayDesignSystem, and leave `includes(_:calendar:)` in a
FeatureReminders extension. Do not import FeatureReminders into Settings.
ReminderTarget stays in FeatureReminders. Existing keys and order algorithms
must survive the split exactly.

PendingListDeletion/deleteListAlert are feature-internal and currently used only
by this lane's screens. No shared-module move is necessary unless another caller
is introduced by integration.

## Evidence and remaining gates

`xcrun swiftc -frontend -parse -package-name TodayModules` passed for all five
moved Swift files. `git diff --check` passed. A focused source comparison found
only imports/access levels, explicit constructors, permission/sync injection,
local TaskRow editor callback wiring, and the fixture-preview removal described
above. No build, Swift tests, simulator UI or physical-device validation ran;
root owns cross-module type checking and runtime acceptance.

QA session: `reminders-module-20261018`, canonical journal
`/Users/yuanlu/code/one-app/tests/results/activity.sqlite`.
