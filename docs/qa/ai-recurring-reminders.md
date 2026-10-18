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

## Verification and evidence

- Owner screenshot retained in primary `tests/results/ai-recurrence-20261018/`,
  indexed with SHA256 by QA journal session `recurring-reminder-20261018`.
  The screenshot proves chat misrouting and malformed title, but cannot establish
  its underlying weekday set or model path.
- Focused source review found and fixed two regressions before execution:
  one-off `this/next weekend` must not gain recurrence; model weekday mapping
  must not advance an explicitly later start date.
- Python TitleQuality scorer: 7 tests passed. `git diff --check` passed.
- Pure Swift at `17bb5cb`: red comparator restored only pre-fix `ChatRouting`
  and the initial weekday parser block from `3bc6a01`, retaining the new compatible
  recurrence type and new tests. One exact-owner regression test produced 16
  expected assertion failures, reproducing chat misrouting, malformed titles,
  single-day loss and wrong first date. This is not an old-app or FM execution.
- Restored candidate: 86 focused tests ran; 84 passed, 2 methods failed with 3
  assertions. The failures identified missing 中 in the Chinese midday route
  vocabulary and the old `Run every weekday` fixture expecting no first due date.
  Added the complete token and updated that expectation to the first eligible day;
  the ratchet was not lowered. At `702c4fc`, the two affected methods plus actual
  fallback exporter passed (3 tests). Capture baseline is 46/46 train, 22/22 test.
  Other passing tests were not repeated. There is no claim of a full-suite pass.
- Swift commands ran from this worktree's `ios/` through the global-lock wrapper
  with `--jobs 2`, in the explicitly released 11:10–11:12 PDT window. A repair
  invocation initially used the repository root and exited without finding a
  Package.swift; it was corrected to `ios/` before the 3-test run.
- No Xcode build, simulator UI, actual local save/reopen, notification delivery or
  EventKit runtime execution has been performed for this revision. No real
  Foundation Models or physical-device behavior has been measured.

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

## Actual broader goal evaluation

`702c4fc` exported 11 development turns from 9 cases through the production pure
routing/context/parser/dialogue seam. Raw per-turn JSON, hashes, source manifest,
red/green/repair logs and scorer output are retained in primary
`tests/results/ai-recurrence-20261018/`, indexed by the QA journal. The 7 reserved
validation cases (8 turns) were not executed; they are reserved, not blind.

Both exact owner requests produced `task`, title `丢垃圾`, 17:00 and normalized
`weekly:sun` / `weekly:fri,sun`; the shared time-correction/English add-repeat,
weekday and ordinary conversation tests passed. Structured content evidence is
separate from app persistence and the confirmation gate.

The benchmark is **not green**. Source-aware, attributed content review of actual
outputs identifies three goals at that revision, retained without changing expectations:

- Colloquial `麻烦帮我加个每逢周五…的提醒` stays conversational.
- `不是下午五点，改成下午六点，周五和周日都保留。` is not recognized as
  the requested preview correction.
- The mixed NAS request retains its explicit firmware-update note inside the
  title while `notes` is null, failing the separate title/notes goal.

The existing scorer reports 3 failed / 16 unmeasured turns, zero reviewed passes.
The latter includes unexecuted validation plus development rows whose Add/Apply
controls and writes were not observed. Raw exports omit unknown gate/write fields
rather than fabricating passing values. Semantic review is attributed derived
analysis (`observations-reviewed.json`); raw backend artifacts remain unchanged.
This wider benchmark exposes gaps beyond the repaired weekday pipeline and is not
represented as model quality, full app acceptance or successful persistence.

## Observed goal repairs at 48d2d81

The three observed failures were then repaired in the existing production seams,
without changing expected answers or adding cases:

- Chinese routing accepts the polite 麻烦 prefix; full weekly-list parsing accepts
  每逢. Existing lead-in cleanup handles scheduling before 的提醒.
- `Dialogue` excludes the rejected old clock in an explicit correction, and only
  treats a keep-weekdays clause as a retained constraint when its complete day set
  equals the pending preview. A mismatch does not silently discard specified days.
- With the title author's ownership confirmation, explicit note labels are handled
  inside `CaptureTitleRefinement.fallback`, alongside existing motivation handling.
  Source note text is preserved, existing notes are retained, repeated calls are
  idempotent, and a note label inside a quoted name is not extracted.

After compat explicitly released its batch and performance agreed the short slot,
only `RecurringReminderTests/testObserved|RecurringReminderExportTests` ran:
**3 affected regressions + 1 actual exporter passed**, at source `48d2d81`.
The warmed `--jobs 2`/global-lock slot ended at 11:20:15 PDT and was handed directly
back to performance. No 86-test or 68-input capture baseline rerun occurred.

Refreshed raw backend outputs are in `fallback-goal-repairs/`. They show:
colloquial Friday18:00 task + reason notes; Chinese correction keeps Friday/Sunday
and changes to18:00; NAS title `备份 NAS`, notes `run before firmware update`,
Tuesday/Friday20:00. The exact screenshot cases also remain correct in this real
11-turn export. Source-aware attributed review rates the colloquial title's
remaining 记得 prefix as adequate but less concise, not a critical semantic error.

The current scorer result is **0 observed failures / 19 unmeasured / 0 reviewed
passes**. Eight validation turns remain unexecuted; all UI gates, writes, model
generation and persistence remain unmeasured. This supersedes the historical
702c4fc three-failure benchmark result, without rewriting its retained artifacts.
The patch is ready for centralized simulator build and the three UI journeys;
no Xcode build or UI journey has yet run on this recurrence source.
