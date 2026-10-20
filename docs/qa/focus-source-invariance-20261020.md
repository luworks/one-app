# Today Focus source invariance

Baseline: isolated worktree started at `a56646b2`, advanced cleanly to `origin/main b9450380`. No parent uncommitted edits were copied.

## Actual action audit

- `TodayRowAttention` in `TodayPlannerUI/Rows.swift` supplies the same closures to trailing swipe and context menu. Today uses `allowsFullSwipe: false`. Reminder completion remains its separate circle/action.
- `DayAgenda.attention`, `focusActions`, the Snooze sheet callback and grouped Restore all call `changeFocus` -> `PlannerActions.focus.change`. There is no completion, deletion, edit, reschedule or reconcile in that path.
- `TodayFocus.change` commits the independent atomic JSON overlay before changing its observable revision. Failure keeps the prior classification. Undo restores only the prior overlay state and records a Focus ledger Undo.
- `TodayFocusStore.state` expires Snooze at read time. `DayAgenda` refreshes its clock on its existing timer/foreground path; expired cross-day items enter Returned to Today using the exact source identity.
- Reminder identities come from accepted native-import scalar snapshots. Calendar identities use `cachedFocusIdentity`; hydration reads exact source/account/calendar/item/occurrence and does not save/delete. Anchor reconciliation only detaches stale overlay references.
- Overdue filtering is in DayAgenda; shared Reminders/Calendar screens do not receive Today attention commands. Hidden events still reserve their actual time in planning.
- Explicit Complete/Edit/Delete and their confirmed EventKit commits/Undo are unchanged.

No source mutation defect was reproduced. This is conformance coverage, not a source-write RED/GREEN claim.

## Bounded T3 mobile reference

Inspected public `pingdotgg/t3code` at commit [`d65249074b54d7e8a72cb9a9e7f8b37bbd0a89a6`](https://github.com/pingdotgg/t3code/tree/d65249074b54d7e8a72cb9a9e7f8b37bbd0a89a6), with [MIT license](https://github.com/pingdotgg/t3code/blob/d65249074b54d7e8a72cb9a9e7f8b37bbd0a89a6/LICENSE), copyright 2026 T3 Tools Inc.

Read `docs/user/thread-sidebar.md` and mobile `thread-swipe-actions.tsx`, `useThreadListActions.ts`, `thread-dismissal.ts`, `homeThreadList.ts`, `swipe-row-activation.ts` under `apps/mobile/src/features/home/`.

Applied the interaction ideas independently in SwiftUI: circular SF Symbols with short labels; close the Snooze sheet before invoking its action; guard and disable a committed picker against duplicate choices. Existing synchronous MainActor overlay commits already deduplicate identical states and keep rows visible on persistence failure. Native List retains gesture arbitration, system sizing and the existing 44-point row targets. No upstream source was copied or translated. No custom gesture framework, network mutation, worktree cleanup, session lifecycle, automatic settlement or T3 server semantics were imported.

## Verification

- `./dev test unit --only TodayTests/TodayFocusStoreTests`: 10 passed, 0 missing.
- `./dev test integration --only TodayTests/PlannerSessionTests/focusLifecyclePreservesSourcePayloadThroughProductionAdapters`: 1 passed, 0 missing. Native build passed; raw bundle: `tests/results/devtools/logs/8936ccb47faf4a52b39dfc44a0591059-xcode/TodayTests.xcresult`.
- `./dev lint`: passed. Formatting applied with `./dev format`; `git diff --check` passed.
- `./dev test ui --only TodayUITests/TodayFocusTests/testSettleAndRestoreChangeFocusCountsWithoutCompletingReminder --only TodayUITests/TodayFocusTests/testFocusChoicesPersistAcrossRelaunchWithoutReseedingSourceModels`: 2 passed, 0 missing/skipped. Same named simulator/cache, TodayMock identity verified. Raw run: `tests/results/runs/today-qa-20261020-101701-62ee726d/`; completed `ui.xcresult`, logs and screenshots retained.
- Inspected exported trailing-action screenshot: distinct Settle/Snooze/Delete labels and round SF glyphs remain readable in native action pills. Long-press menu, source reminder remaining incomplete, Restore, explicit Delete/Undo, persistent groups and expiry after relaunch passed. Dark mode/largest type and manual VoiceOver were not rerun.
- One focused self-review and diff check completed; no unresolved findings. The runner shut down its owned simulator successfully and released host/cache locks. No full suite was run.

The new `focusLifecyclePreservesSourcePayloadThroughProductionAdapters` exercises real PlannerActions/TodayFocus plus production Reminder/Calendar identity adapters. It compares every persisted reminder field (TaskSnapshot plus external/model identity), every event field, recurrence occurrences and row counts after each transition/Undo, checks adapter store acquisitions and alarm/notification/service write counters, then refreshes imports, reopens the disk overlay, checks exact expiry and occurrence isolation, and injects a concurrent disk change.

The native write boundary is verified by zero lazy EventKit store acquisitions; no live Apple account payload or user data is read. This does not claim a physical-device EventKit round trip. ModelContext stays alive while the production Focus JSON is reopened; full process relaunch belongs to the existing UI journey.

Raw evidence is retained in the primary checkout under `tests/results/devtools/` and indexed by the QA SQLite journal. Reference snapshots and task journal entries use session `focus-source-invariance-20261020`; initial missing-tool and wrong-target selection failures are preserved. Protected Today-UI and the phone were untouched.
