# Reminder deadline save regression — 2026-10-19

Base: `f76b106cde588968ccb463bbc67c4c782a378e64`.
Worktree: `/Users/yuanlu/.t3/worktrees/one-app/t3-4fc457b1`.

The unchanged production TaskEditor was characterized with synthetic data and
DEBUG-only EventKit probes. An ordinary 14:00 → 13:10 edit reached Apple. That
first characterization failed an incorrect expectation that Apple's start should
also move; the assertion was corrected to preserve the original start, rather
than attributing that failure to the reported regression.

The reported outcome was then reproduced under a controlled independent Apple
note edit immediately after the local save: Done closed the original editor,
Apple's full fingerprint won reconciliation, and the actual Apple object still
held 14:00. This establishes one concrete failure path; the owner's private store
and the exact timing of its external changes were not inspected.

The repair commits changed fields to EventKit before updating the local object
and dismissing. It publishes the accepted fingerprint only after the local save
and invalidates older asynchronous fetches through the existing completion fence.
System failure leaves the draft; a subsequent local failure is reported as partial
success and retries the same identity. Planned time remains local.

Validation:

- `./dev test ui --only TodayUITests/ReminderTimeSaveTests/testDeadlineTimeRoundTripsThroughAppleWithoutChangingPlanOrMetadata`
  — behavioral red, then **1 executed / 1 passed** on the repaired original Form.
- The passing journey checks actual DatePicker editing, Apple/app/persisted values,
  reopen, foreground refresh and relaunch. Deadline is 13:10, Plan a time stays
  off, and the Apple ID/list, native start, explicit timezone, URL, priority 5,
  original biweekly recurrence and two alarms are retained. The concurrent Apple
  note also survives.
- `./dev format --check`, `./dev lint`, `git diff --check` — passed.

Native evidence: TodayMock hosts the production SwiftUI editor and a real
RemindersSync/EventKit adapter for this journey; Xcode 27.1 / iOS 27.0 Simulator,
`Today-Dev-7133c72b` (`E22BEEDE-2E4E-4750-8555-42DA0054EFDC`), the same owned DD.
This is not phone, iCloud propagation, Release, or final full-suite acceptance.
The explicit injected-failure/retry and delayed-fetch journeys remain in the
following compact-editor layer; this passing result does not claim those ran.

Raw evidence is retained in the primary checkout and indexed in its QA journal:

- Red: `tests/results/runs/today-qa-20261019-110957-b1042a07/`.
- Green: `tests/results/runs/today-qa-20261019-111357-bcee37c6/`.
- Exported screenshots/attachments: `tests/results/reminder-compact-20261019/`.
- Initial compile failure and ordinary-save characterization are retained at
  `today-qa-20261019-105947-80abaa08` and `today-qa-20261019-110454-3dc2031d`.

Large xcresults, recordings, screenshots, private source references and runtime
SQLite stay outside Git. Compact Due layout and strict editor deletion/Undo are
preserved separately and do not delay this behavior repair.
