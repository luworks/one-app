# Intelligence product proposal and authority boundaries

This is a reviewable proposal, not an authorization change or a shipped change.
Baseline: `5a0a18ebd9b25b63e276340f26ddd743714a5bdc`. `CLAUDE.md` remains authoritative.

Yuan's direction is to have normal conversation and act on sufficiently clear
requests without repeatedly asking for information already supplied. Keep that
separate from the permission to persist a particular kind of change.

| Concrete trigger | Required interpretation | Existing authorized boundary |
| --- | --- | --- |
| “明天下午两点提醒我浇花” | One reminder, tomorrow 14:00, once, faithful action title | Clear submitted one-off rule grant may create directly. Show Added only after the normal save/connected EventKit commit; provide exact Undo/Open. |
| “Remind me to buy paper” | Explicit untimed, undated reminder; do not invent a clock/date | Existing one-off grant can apply when rules establish the request. Missing optional scheduling fields do not justify an interrogation. |
| “每周一、周三晚上七点提醒我练琴” | One weekly reminder with both weekdays and 19:00 | Ready preview with Add. Do not ask for kind, recurrence or time again. Sending alone does not authorize recurring creation. |
| “明天早上七点设置一个闹钟” | Alarm with the requested time, distinct from a reminder | Ready alarm preview with Add. No repeated kind/time question. Existing system permission and save checks still apply. |
| “创建明天下午两点到三点的项目复盘日历事件” | Calendar event with correct start/end and faithful title | Ready event preview with Add; no invitation or attendee action without its existing explicit confirmation. |
| “把三点的复诊改到四点” when exactly one 15:00 target exists | Resolve the unique existing target and proposed replacement | One ChangeCard, Apply writes that target; Undo preserves its original snapshot. |
| “Move the dentist to four” with two matching targets | Material target ambiguity | One focused selection question. Never silently pick a target or create a replacement reminder. |
| “今天有点累” or reported speech about someone else's reminder | Natural conversation in the user's language | No proposed item or write. Do not claim to have read unavailable agenda/Activity data. |
| “Start a five-minute timer” | Preserve timer intent | Chat-to-timer support is not established by the current eval. Do not silently substitute a reminder/alarm. An honest limitation or explicit route to the existing Clock UI is preferable to a false execution claim. |

For a follow-up, reuse the current subject, kind and recurrence, change only
the supplied slot, and avoid a duplicate item. “At four” after a weekly reminder
must not become a new daily or one-off reminder. A previously Added/Dropped/Undone
card also retains its existing lifecycle; a continuation is not unlimited
permission to recreate it.

Capability questions (“Can you create reminders?”), explanations, refusals,
quoted commands and concrete polite requests must be distinguished. The frozen
development case `question-not-action` intentionally retains its original
clarify-or-preview expectation. Changing polite-question routing into a direct
write would require a separate authorization/compatibility review; do not edit
the fixture after seeing scores to make that behavior look successful.

## What can improve within the current boundary

* Resolve already provided slots, produce a concise faithful title, and present
  a fully populated proposal without redundant conversational questions.
* Keep deterministic scheduling validation, existing-target resolution and save
  receipts authoritative. A model's confidence is never a new write grant.
* Separate chat from extraction, and distinguish model unavailable/error/timeout
  from a successful call or a local fallback. Reply honestly when a capability
  is unsupported.
* Evaluate the same production roles for a replacement model. The current clear
  one-off fast path bypasses ordinary model parsing/title generation, so backend
  replacement alone cannot repair failures on that branch.

Automatically saving recurring reminders, alarms, calendar events or edits on
Send would expand the current authority. That option is deferred pending an
explicit product decision covering undoability, recurrence scope, system
permissions, ambiguous targets and failure receipts. This evaluation does not
enable it. Undo is a recovery mechanism, not permission to bypass the existing
confirmation gate.

## Clock findings and concrete next design

The first frozen Live extension observed timer requests being answered as chat,
unqualified promises to set a timer/add Shanghai, and a recurring timer becoming
a daily reminder preview. Foreground traces reconcile the former replies to
chat generation and the latter to kind/title generation. No Clock executor was
provided by those model calls. Tokyo's claimed existing-city state remains
UNKNOWN because the subsequent Clock inspection was interrupted by a separate
AlarmKit-denial hang. Do not infer that city's actual presence from model text.
The raw UI, call records and manual verdicts are retained under
`tests/results/intelligence-eval-20261028/live-product-round3-20261029` in the
primary checkout. These are first-repetition development observations, not a
model comparison or a general Clock pass rate.

The shared production instruction already says not to promise an action without
a preview. Repeating that sentence is insufficient protection against these
observed replies. The next coherent product change should introduce explicit
timer/world-clock intent variants and validated Clock proposals, then execute
only through the existing app services and confirmation boundaries:

* A concrete timer request resolves a duration within the existing Timer limit,
  prepares one timer proposal and offers Start. No further time/kind questions
  are needed when the duration is supplied. A model reply cannot start a timer.
* A city request resolves a concrete city record against the existing city
  database. An already-present answer must read the actual WorldClockStore.
  An absent city gets an Add proposal; an ambiguous city gets one selection.
  Undo must remove only the newly added city while its state is unchanged.
* A recurring timer retains the unsupported combination and asks one focused
  timer-versus-daily-alarm question. It never becomes a reminder by substitution.
* Denied AlarmKit access remains denied. A timer/alarm proposal must report the
  required access honestly and cannot claim a successful schedule. Do not
  request broader access as an evaluation workaround.

This design reduces redundant dialogue without granting new autonomous writes.
Making Send itself start timers, add cities or schedule alarms would be a
separate authority proposal requiring an explicit decision about exact Undo,
system permissions, duplicate submissions, background execution and failure
receipts. None of those new grants is enabled by this evaluation or this document.
