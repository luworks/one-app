# Remove Returned to Today — 2026-10-21

Baseline: isolated `t3/remove-returned-today`, clean before fast-forward from
`a56646b2` to fetched `origin/main` `9dfed1b28b4c135c232bc280820eb623479ced7f`.
Issue #32 remains open. No other checkout or phone was modified.

The supplied physical-phone screenshot shows five old titles in a separate
Returned to Today list above Overdue. This is direct user evidence of unwanted
persistent history. It does not reveal those records' stored states. Source
inspection finds DayAgenda's `returned` selecting `.active` and expired `.snoozed`
records absent from the day's ordinary projection, then resolving their old
source occurrence without a day filter. PR147's expired `.settled` projection
returns nil; it does not itself convert that state to `.active`. The precise
prior phone interaction for each screenshot row is unknown.

Remove the entire extra section, its row actions and its dedicated visible-identity
calculation. Keep source-date filtering, ordinary overdue visibility, Settle's
local-day expiry, absolute Snooze expiry, explicit Restore/Unsettle and brief Undo
toasts. Preserve persisted Focus records and the separate Activity ledger; no
schema migration, source mutation, Calendar/Reminder completion/date/alert/repeat
write, settings or bottom-navigation change.

The reusable `remove-returned-to-today.json` fixture supplies old settled/restored
events, current-day reminder/event, overdue reminder and tomorrow event. Mock-only
clock parsing accepts ISO instants and dataset loading uses the same runtime
calendar/clock, so relaunching one isolated store on D+1 tests actual dates.

Evidence root: `/Users/yuanlu/code/one-app/tests/results/remove-returned-to-today-20261021`.
The first phone screenshot and initial missing dependency-lock failure are retained.
No physical install, real overnight wait, full UI run or prototype change was
performed for this PR. Subsequent phone delivery is authorized but assigned to
the root after CI and preflight; this PR does not establish physical acceptance.

Verification retained in the primary checkout:

- Baseline RED: `red-ui/ui.xcresult` and exported AX/screenshot prove the new-day
  meeting/task were present, then the test failed at the Returned heading
  assertion (line 195). The old explicitly restored occurrence was in that list.
- GREEN: `tests/results/runs/today-qa-20261021-013117-151ddb20/summary.json`
  records build/UI/shutdown exit 0 and exactly 3/3 selected methods passed:
  `testCrossDayReleaseUsesOriginalDatesWithoutReturnHistory` (56.339 s),
  `testFocusChoicesPersistAcrossRelaunchWithoutReseedingSourceModels` (98.199 s),
  `testSettleToastUndoRestoresVisibleIncompleteReminder` (20.321 s).
  Command: `./dev test ui` with these three `--only TodayUITests/TodayFocusTests/…`
  selectors. Existing live runner was resumed after provider capacity failure;
  no duplicate build, test or review was started. Its completed run was archived
  and indexed with `tests/qa/journal.py` (482 imported events).
- Simulator: TodayMock, iPhone 18 Pro Max / iOS 27.0, owned
  `Today-Dev-ea3af8fd` (`0A695D9E-9C31-42A0-AE55-3A66ADB1EB89`), now shut down.
  Retained build source fingerprint:
  `54d31c75bd6e191817eaffff647c6cba47d17c1ab9b51313664c5f1c5f8b9208`.
  Tests ran on the uncommitted patch above baseline; only this evidence document
  changed after the passing run.
- `green-attachments/` contains complete exported screenshots and AX. Visually
  inspected `cross-day-release`: Oct 21 meeting/task, Overdue/Snoozed/Settled/
  Tomorrow and bottom controls remain; no Returned heading or old rows.
- `./dev format --check` passed (retained `format.log`); `git diff --check` passed.
- One independent GPT 6.1 Sol medium read-only review returned no findings.
  Task: `node:delegated-task:command%3Amcp%3Af41b19c7-b9d4-4121-9009-7d9f5ead3d29%3Adelegate-task%3Aremove-returned-to-today-review-20261021-v1`.
  Reviewer ran no builds/tests and edited no files.

Initial dependency-lock, source-change provenance and simulator preboot failures
remain retained as infrastructure evidence, separate from the actual baseline
RED. No unit or integration test execution is claimed: the mounted integration
expectation was updated for the new behavior but not run locally. Physical dates,
live EventKit/source payloads, phone upgrade and real overnight behavior remain
unchecked by these Mock simulator journeys. Issue #32 remains open.
