# AI chat capability evaluation protocol

`tests/fixtures/ai-chat-capability-eval.json` defines 24 synthetic bilingual and
mixed-language scenarios, including explicit reminders, undated requests,
recurrence, alarms, events, agenda questions, edits, ambiguous references,
conversation, multi-turn recovery, a batch and a self-correction. The fixture is
an authored **development set**, not a blind or representative population sample:
it includes the owner's reported failure and was written with knowledge of the
project. Freeze its contents before either run, record its SHA-256, and use the
same cases, seeds, clock and scoring in both passes. Do not change expectations
in response to results. This evaluation does not establish model limits in general.

## Setup and safety

Use a named, isolated simulator and an isolated synthetic store with all live
accounts and sync disabled. Run the Live app when measuring Foundation Models;
TodayMock uses scripted/rule dependencies and cannot measure model generation.
Record the exact build SHA, binary variant, OS, model availability, language,
clock, time zone, fixture hash, and simulator identity. The fixture's clock and
seed describe the reference setup; if a Live build cannot pin them or seed the
items, record the actual time and setup, compute relative dates at submission,
and mark inapplicable cases unrun rather than inventing a result. The two dentist
items must be distinguishable, with one due at 15:00 and the other at 16:00.

Start a fresh chat for each case; keep turns within that case together. Use only
`[QA]` synthetic subjects. Capture screen recording and contact sheet with
`agent-device record start/stop` and `record contact-sheet`, plus screenshots or
hierarchy and timings. Record evidence paths and hashes in the QA journal under
the primary checkout's `tests/results/`. Save outcome before cleaning up. Undo
or delete only items created by the evaluation, including simulator Reminders or
Calendar if connected. Verify cleanup and do not touch unrelated data. A preview
is not a save; never tap Add or Apply merely to make a result pass.

## Scoring

For every turn record case ID, input, expected, visible actual reply/card, title,
date/time, repeat days, target, save/preview state, pass/fail/unrun, submit-to-final
response latency, and evidence path. A case passes only if every turn meets all
specified fields and boundaries; note title meaning separately from exact wording.
A direct-add case requires an Added receipt with Undo and Open, not just a card;
if the card is not expanded enough to verify a field, mark that field unverified.
A date-only reminder must not invent a clock time. A materially ambiguous case must not be silently saved. An explicit undated
reminder may be directly added without inventing a date or time. Explicit recurrence, alarms, events,
edits and deletes require their existing Add/Apply boundary. Any unintended
write or wrong-item edit is a safety failure even if other fields look correct.
For ambiguous cases a correct clarifying question is acceptable only where the
fixture says so. Never infer a correct save from a conversational claim alone.

Report completed cases / eligible cases and pass / completed for each category
and language, plus overall, rather than treating unrun as pass or fail. Report
safety failures separately. Record latency per turn; p50/p90 are descriptive
only when sample size and timing method are stated. Report run failures and
timeouts explicitly. One run gives observed strengths and failures, not a
statistical upper or lower bound. Follow with a separately authored blind holdout
and repeated trials before comparing alternative systems or making a release
claim. Separate product pipeline scores from model-only scores.

## Backend attribution

For each turn use `rules`, `model_success`, `model_timeout`, `model_error`,
`model_unavailable`, `mixed`, or `unknown`, supported by actual call-level
instrumentation and correlation to the turn. Availability alone is not proof of
generation. The current `ai.turn` route and `model_available_outcome_unobserved`
trace cannot distinguish successful model generation from failure/timeout and
fallback; without further evidence use `unknown`, explaining any known rule
stage separately. A direct rule-handled request can still invoke model title
refinement, so attribution is per stage, not guessed from the card label.
Avoid collecting user text in instrumentation; the synthetic fixture and UI
record already identify cases. Compare model-only extraction or chat on the same
frozen inputs only with an explicit harness and its actual production prompts,
model version and failure reporting; do not present a Mock run as a model score.

Simulator execution and latency do not establish the phone's model availability,
performance, EventKit/AlarmKit integration, or real-device behavior. API options
also need a matched evaluation, privacy/network and cost assessment before an
architecture decision. This protocol records a method, not results.
