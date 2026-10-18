# Actionable reminder recovery acceptance — 2026-10-18

Issue #83 / PR #84 fixes the owner's conversation that supplied `做一次 auto turbotax repo 下周四提醒我`, then `就设定 reminder`, `够`, and `你做吧`, but received only chat and an empty promise.

`ChatRouting` now recognizes complete suffix reminder instructions after its conversation/report guards. `CaptureConversation` recovers the prior USER subject/date on explicit reminder clarification or proceeding, ignores assistant asides, and retains the subject across short acknowledgments. An acknowledgment itself creates no proposal or write; unrelated conversation still clears the recoverable subject. `Understander` continues using parser-owned scheduling and title-only model refinement; shared model guidance distinguishes concrete creation, one-off dates, valid date-only reminders, and conversation. PR #80's synchronous unavailable-model conversation path is unchanged.

The result is a faithful `做一次 auto turbotax repo` reminder for next Thursday once, without an invented clock time. It is ready to Add. The existing Add/Undo contract owns every write.

## Actual verification

- Clean inherited baseline matched fetched main `fc7fc84`, including PR #80. Read AGENTS, CLAUDE, ios README and issue #32 before edits.
- Initial `swift test --package-path ios --jobs 2` selection: 52 tests passed across routing, context journeys, recurring reminders, title cleanup and recovery.
- One focused source review found an unquoted past-report false capture. Repaired that boundary; routing + recovery recheck passed 33 tests.
- Final recovery fixture check passed: 17 bilingual cases, including the complete eight-message history ending in the false promise and a renewed explicit reminder request. Assertions require a ready Capture with exact title/day, nil hour, task kind and correct one-off/weekly rule; host logic does not claim persisted-write observation.
- One simulator batch with `-jobs 2`, serial targeted methods, Today-EventSave (`9028A2F8-1FF3-4C59-8084-77132FE787B3`, iPhone 18 Pro Max, iOS 27.0), reused `calendar-save-20261018/cache`: Chinese mistaken-chat recovery and English recovery/quoted negatives passed. The Add/editor journey initially failed because the compact date picker has no `Due` accessibility name. Failure recording showed the correct saved date, Deadline on, Plan a time off and Repeat Never.
- Corrected only the UI selector to check the actual exact date button, retained the assertions and printed the actual hierarchy. Only the affected Add/editor/Undo method reran and passed (48.579 seconds). The log exposes `Oct 22, 2026`, `Repeat, Never` and the saved title. Other passing methods were not repeated.
- UI journeys assert actual actionable cards, enabled Add for date-only reminders, exact title/date without a recurrence/time suffix, and an empty change ledger before Add. The Add journey checks saved model editor fields and creation Undo. A retained Chinese screenshot was visually inspected and shows the correct title, Due Oct 22 and enabled Add.

Application source tested at `1afd5af`; the isolated UI selector recheck used `c8cd4f1` with the same app source. Later evidence-only edits require no new build. Fetched main advanced only through unrelated PR #82 Release symbols/audio packaging; no overlapping application behavior changed.

Foundation Models generation and physical-device/EventKit behavior were not evaluated. The simulator executes production fallback, with no injected model output. Model guidance is compiled, not claimed as model validation. No full suite, signing changes, data reset or cache deletion occurred.

## Retained evidence

Canonical primary checkout: `/Users/yuanlu/code/one-app/tests/results/`.

- `reminder-recovery-logic.log`, `reminder-recovery-review-logic.log`, `reminder-recovery-promise-logic.log`.
- `runs/reminder-recovery-source-20261018/`: owner screenshot and host logs, archived/indexed through the QA journal.
- `runs/reminder-recovery-20261018-ui/`: initial build/test raw log, complete failed xcresult (two passed journeys, one selector failure), exported screenshot/recording and editor failure frame.
- `runs/reminder-recovery-20261018-add-recheck/`: successful isolated recheck raw log, actual hierarchy, complete xcresult and summary.
- QA development/link journal session `reminder-recovery-20261018`; runner sessions `reminder-recovery-20261018-ui-a0455083` and the session recorded in the recheck summary. No journal errors; shutdown returned 0 for both batches. Device panel closed and actual resource release sent directly to performance coordinator.

Reusable inputs: `tests/fixtures/ai-reminder-recovery-cases.json`, `ai-reminder-recovery-ui.json`; consumers: `ReminderRecoveryTests` and `AIReminderRecoveryTests`. No required input lives only in a temporary directory.
