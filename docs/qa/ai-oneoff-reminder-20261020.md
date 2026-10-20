# Submitted one-off reminder: screenshot fix

Baseline: clean `origin/main` `45cf41c4`; isolated worktree `t3-481b4414`, branch `fix/chat-oneoff-reminder`. No root dirty patch, CI/workflow/signing changes or phone writes.

At 09:11 in America/Los_Angeles, the exact submitted text `11点去 costco 加油 买 粒粒` previously routed as `unsure`, allowing generic conversation. `setting reminder` could not recover the subject; the generated wrapper `设置11点去costco加油买粒粒的提醒` remained in the title. The baseline regression run executed three tests with three failed assertions (routing, recovery and wrapper cleanup); the parser's original 11:00 deadline mapping already worked.

The clear single one-off request now goes through deterministic admission before either model path, directly creates `去 costco 加油 买 粒粒` for today's 11:00 deadline/alert, and keeps planned time empty. The existing passed-clock policy uses tomorrow. Explicit recurrence, alarms, calendar events/invites, month-only dates, materially ambiguous choices and ordinary conversation retain their existing boundaries. No background grant changed. `setting reminder` and `one off` use original user context/timestamps and reuse the same decided card instead of creating another.

Connected direct creation uses an explicit Reminders service commit before local durability and the creation ledger receipt. It refuses ambiguous list identity. Local-save failure compensates the exact system creation; failed compensation retains its real identity in the recoverable draft. Retry/Cancel, Undo/Open and deliberate Add again preserve receipt ownership. An intentionally disconnected app remains local-only under the existing authority. Other insertion paths are unchanged.

## Evidence

All runtime evidence is retained in the primary checkout `/Users/yuanlu/code/one-app/tests/results/`, indexed by the QA journal. These paths are local evidence, not hosted CI acceptance.

| Check | Result | Retained evidence |
| --- | --- | --- |
| Baseline new regressions | 3 executed, 3 assertion failures | `ai-oneoff-reminder-20261020/before-executed.log`, `before-unit-raw.log` |
| Focused logic | 51 passed, 0 missing: OneOffReminderTests (7), ChatRoutingTests (34), CaptureCardStateTests (9), ReminderRecoveryTests (1) | `devtools/logs/e124a007f8f640fea946e8cf5785fb23.{log,report.json}` |
| Final admission boundary | 7 OneOffReminderTests passed, 0 missing after excluding untimed alarm requests and subjectless input | `devtools/logs/5578f1d6a9ec4d4bb1419cda7bb857ae.{log,report.json}` |
| Native integration | 1 selected Swift Testing leaf passed after real iOS compilation; injected creation failure leaves no task/ledger, retry is idempotent, persisted deadline survives a new ModelContext, Undo removes the same task | `devtools/logs/aa8b7b7dd5f94169a23db59f172e526f-xcode/TodayTests.{report.json,xcresult}` |
| First UI batch | 3 failures in shared sidebar helper before opening chat; offscreen row existed but had activation point `{-1,-1}` | `runs/today-qa-20261020-092844-a1706d3c/` |
| Focused UI repair | 1 representative passed in 52.507s: submitted original text, Added, fresh EventKit-store readback at 11:00, Open with original title/deadline, Undo and backend absence | `runs/today-qa-20261020-093303-317f93c4/` including full `ui.xcresult` and screenshot attachment |
| Formatting | `./dev format --check` passed; `git diff --check` clean | `ai-oneoff-reminder-20261020/format-check.log` |

The first unit invocation was refused by the existing host-heavy lock before execution. Native setup initially reported missing verified xcodegen; `./dev bootstrap` installed the pinned tools. Preserve both diagnostics. An intermediate final unit run rejected three existing polite/quantity requests under an overly broad question guard; its raw log/report `8c3815525af1420f8c2ed3387c4a9f3c` is retained. The corrected final guard distinguishes unknown action objects (Buy what?/买什么) from polite imperatives and quantities; existing assertions remain intact.

A focused alarm-boundary regression also reproduced three failed assertions for `Set an alarm`, `Wake me up` and `设置闹钟`: a parser result without a clock can temporarily look like an ordinary task. The direct-admission source guard now excludes alarm intent independently of parsed fields, as well as subjectless `Remind me`/`new task`. Preserve the red `7374566154794d5992ad92efc418e368` and final green reports above.

One focused source review resolved direct new-chat relationship persistence, draft retention, repeat-Add receipt reuse and deliberate Add-again invalidation. Final pure question/month/alarm/subject admission guards were logic-tested after the successful UI snapshot; the original Costco creation/persistence/Undo behavior was unchanged. The native integration uses synthetic local services; only the representative UI journey proves actual simulator EventKit persistence. Compensation/local-failure ordering is tested with synthetic closures, not an observed EventKit or disk fault.

## Limits and ownership

- No full UI suite, Foundation Models execution, physical-device run, phone installation or exact-main hosted CI acceptance is claimed.
- The two other UI methods were not rerun after fixing the common sidebar helper. Their dialogue/failure behavior has focused logic/integration coverage, not final UI PASS evidence.
- Source-maintained affected UI contracts: direct one-off cases now assert Added; cases specifically testing pending-preview editing/cancellation use explicit recurrence, preserving their Add/no-write assertions. This covers the existing card-state, conversation, context, capture/edit, appearance and capture-preview performance fixtures in addition to screenshot recovery and J1. These additional UI methods were not executed in this bounded batch; no full-suite or refreshed performance measurements are claimed.
- Only the lane-created `Today-Dev-dfe250c7` simulator `25BC8AD3-B944-46DA-B4CC-90B55F480F59` was opened, then shut down and deleted after the batch. Protected `Today-UI` `203E49F9-2B3D-4079-A10E-E2C6DA518473` remained booted; phone, device derived data and root checkout were untouched. Host-heavy was released to the phone owner.
- PR handoff is for root review. No merge, force-push, branch deletion or signing change is authorized by these results.
