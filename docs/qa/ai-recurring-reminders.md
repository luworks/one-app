# Recurring reminder intent and weekday retention

Issue: https://github.com/luworks/one-app/issues/70

## Source and delivery boundary

Review base `3bc6a01` explicitly merges final AI source `73b7565` (title PR65
`3881c77`, behavior `9b6ea3c`; context PR69 `7f47288`; experimental header PR63
`9435048`) and evaluation PR67 `137760e`. The fixed review-only base is
`t3/recurring-reminder-review-base`. It must not be merged into main: header A
and inherited UI candidates are not verified product fixes. Adopt only the focused
recurrence commits after the verified AI65/69 changes reach main. No force push,
branch deletion or signing changes are needed.

## Production path

`AskView.send` calls `ChatRouting` before `ChatResponse` and `Understander.parse`.
The latter calls `CaptureConversation.parse` / `CaptureParser`, rules/classifier
for type, then title-only refinement. The live `SystemPrompt.planner` is shared
by chat/classification sessions. It now explicitly treats direct recurring chores
as reminders, retains every weekday, and keeps Add/Apply mandatory.

The parser consumes complete Chinese/English weekday lists before generic weekly
words. Explicit weekdays use the existing repeat string field, e.g. `weekly:1,6`
(Calendar Sunday=1, Friday=6); ordinary legacy `weekly` remains unchanged.
`RepeatRule` still encodes as a single string, preserving old Codable and SwiftData
storage. No schema fields or migration are added; Habit and LedgerEntry stay.

Preview summaries name all selected days. `Dialogue` retains recurrence through
clock corrections and supports adding recurrence to the pending subject.
`Capture.makeTask`, snapshots, stored cards and task copies already copy the raw
repeat string. Editors include the current custom selection so Save does not
clear it. `RepeatRule.next` advances within the complete day set. EventKit mapping
exports/imports interval-one weekly day sets; unsupported interval/positional rules
remain unsupported. Model multi-item draft mapping also carries explicit weekdays,
validates the full list and preserves an explicit future start-date lower bound.

## Evidence at initial review

- Owner screenshot retained in primary `tests/results/ai-recurrence-20261018/`,
  indexed with SHA256 by QA journal session `recurring-reminder-20261018`.
  The screenshot proves chat misrouting and malformed title, but cannot establish
  its underlying weekday set or model path.
- Focused source review found and fixed two regressions before execution:
  one-off `this/next weekend` must not gain recurrence; model weekday mapping
  must not advance an explicitly later start date.
- Python TitleQuality scorer: 7 tests passed. `git diff --check` passed.
- Swift logic, simulator build/UI, actual local save/reopen and EventKit runtime
  behavior are pending resource release at this revision. No real Foundation
  Models or physical-device behavior has been measured.

## Focused checks

Run from `ios/`, after explicit resource release:

```sh
python3 /tmp/today-overnight-swift.py test --jobs 2 --filter 'RecurringReminderTests|RepeatWeekdayTests|RecurringReminderExportTests|CaptureEvalTests|ConversationJourneyTests|ChatRoutingTests|DialogueTests|AICaptureMappingTests'
```

The fallback export uses the existing frozen TitleQuality interface:
`AI_RECURRING_EVAL_FIXTURES=<repo>/tests/fixtures/ai-title-rewrite-recurring-cases.json`,
`AI_RECURRING_EVAL_OUTPUT=<primary>/tests/results/ai-recurrence-20261018/fallback`,
`AI_RECURRING_EVAL_SHA=<executed revision>`.
It executes development only; reserved validation stays unexecuted, not blind.
Unobserved gate/write fields are omitted so the scorer reports unmeasured rather
than counting fabricated `false` or null as passing. The fixture is a broader goal
benchmark: authored expectations do not imply that every rephrase or saved-item
edit is currently supported.

UI (one shared warm runner, build once, at most these three methods):

- `OneUITests/AIRecurringReminderTests/testDirectChineseSundayPreparesReminderWithoutWriting`
- `OneUITests/AIRecurringReminderTests/testFridaySundaySurviveAddAndEditorSaveReopen`
- `OneUITests/AIRecurringReminderTests/testEnglishRecurrenceFollowupAndTimeCorrectionKeepSubjectAndDays`

The UI title selector is the existing editable `capture-title` Button, not a
StaticText. These checks establish simulator fallback only. Apple Intelligence,
notification delivery and live Apple Reminders sync require separate evidence.
