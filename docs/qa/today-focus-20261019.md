# Today Focus native verification

Source base: `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c`. The feature integrates PR108's exact `e623117b2d04c5fc1ce7d63e71feba401d3ba6be` deletion dependency in merge `2017a9c`; PR108 was still open when verified. This is a stack, not a claim that its API is on main. [Semantics and storage contract](../engineering/today-focus.md).

## Completed checks

- `./dev test unit --only TodayFocusStoreTests`: 10 executed, zero missing. Disk reopen, atomic readback, I/O failure, stale writer, corrupt/newer format preservation, absolute expiry/DST, per-occurrence/source identity, orphan anchoring, explicit active restore and real Activity recovery/clear independence. Report: `tests/results/devtools/logs/ddaf830a45fc40cdb926fd3eb63bce85.report.json`.
- Initial integration selection: 6/6 passed, including four Focus checks and PR108's existing two confirmed deletion regressions. Raw report/xcresult: `tests/results/devtools/logs/b59da8e1238442238f49bf677afd2179-xcode/`.
- Final review repairs: `./dev test integration` selecting `PlannerSessionTests/focusPausedOrDisabledActivityDoesNotOwnFocusOrItsUndo`, `focusRefreshedSourceFieldsKeepFocusButDifferentIdentityDoesNotInheritIt`, and `calendarDeletionKeepsUnavailableOrChangedMirrorsAndLocalSeriesUndo`: 3/3 passed, zero missing. Real SwiftData/actions/Activity with service fakes; this is not real-account EventKit proof. Report/full xcresult: `tests/results/devtools/logs/638509566a6540e9b581ce5d903d9ff6-xcode/`.
- One native batch selected four `TodayFocusTests` methods plus `CalendarRecurringDeleteTests/testDeleteThisEventOnlyFromRowKeepsOtherDays`, reusing simulator `F1EDE224-AE71-43C5-AD96-9356AB938948` and DD `966e68900ebd9697d5ce`. The EventKit deletion, Focus persistence/expiry, hidden-busy/explicit-overdue, and Settle/Restore/source-incomplete/Delete/Undo methods all logged pass. The runner's 600-second budget interrupted the fifth method; the batch is **interrupted**, not green. Raw log, summary, progress and incomplete xcresult are retained in `tests/results/runs/today-qa-20261019-133657-15a72933/`. Its unfinished xcresult cannot be exported as a finalized bundle.

The real EventKit test creates synthetic simulator calendar data, deletes only the selected occurrence and verifies adjacent days remain. It uses no private calendar/account data. All four Focus journeys use the versioned `tests/fixtures/today-focus.json` and production native views/actions.

## Retained failures and remaining check

The first representative UI attempt (`today-qa-20261019-131529-55e8463a`) exposed a helper that rejected full-width List headers. The second (`today-qa-20261019-131952-ec5fe8f1`) completed Settle/count updates but queried Smart All as a Button instead of its actual AX type. Both were fixed without changing assertions. The second run's early `after.png` was a transition frame and is not final after-state evidence.

The isolated fifth-method retry (`today-qa-20261019-134746-e8bbe0d2`) completed Snooze hide/count assertions, then failed at the second source inspection: Reminders had retained the already-open All list, while the helper insisted on finding a home-screen smart pill. Its complete xcresult, AX snapshots and video are retained. The helper now uses the existing source row when already in that list; all incomplete/source title/Due/list/Undo assertions remain. Only this method remains to be rerun after the shared runner queue, not the four passing methods.

Routine verification exceeded ten minutes because of these concrete selector/navigation repairs and the bounded batch timeout. Passing methods were not repeated. No full suite or physical-device test was run for this feature.

## Native visual evidence

Primary evidence folder: `tests/results/today-focus-20261019/`, indexed through `tests/qa/journal.py`.

- `before-native.png` and `after-native.png`: successful `./dev ui capture --scene today --scenario normal --appearance light` captures of the production DayAgenda in the native Workbench, at the same simulator viewport and fixture clock. The added 44-point Active heading shifts the existing timeline; meetings, timers and reminder controls remain native. This is a component capture, not full-app functional proof.
- `native-before-snooze-video-frame.png` and `native-after-snooze-video-frame.png`: unaltered frames at 33s and 47s from the failed retry's retained native recording `snooze-first-failure-attachments/D94546F4-6B6D-44E2-B18D-D29BE0586C17.mp4`. Both were inspected locally: Active 4→3, Snoozed 0→1, invoice hidden, meeting/suggestion unchanged. They prove the completed hide steps, not the later failed source inspection.
- `snooze-helper-failure-screen.png`: 50s frame showing All 3 with the original incomplete invoice, explaining why no home smart pill exists. Raw video/AX data is preserved alongside it.

No screenshot substitutes for Due equality or Undo assertions. Google OAuth/network integration, real-account reauthorization, physical devices, Release and hosted CI acceptance are not established. Changed source IDs remain conservative clearable orphans; they are never linked by title. Native system events retain occurrence/future scope; local repeating mirrors retain their existing series-only deletion boundary. Calendar Undo explicitly describes compensation as a new plain copy in the default calendar rather than full invitation restoration.
