# Intelligence model selection

Status: protocol, not results. Baseline is `5a0a18ebd9b25b63e276340f26ddd743714a5bdc`.
Earlier manual probes under `tests/results/intelligence-eval-20261028` are exploratory
and do not constitute matched model scores. In particular, sample-program errors,
different prompts, and its incorrect printed token rate are excluded.

## Frozen comparison

Use the existing 24-case `ai-chat-capability-eval.json` as development data and
`intelligence-model-selection-holdout.json` as a separately authored holdout.
Freeze and hash both before running. The holdout was authored with repository
knowledge; it is not an external or statistically representative benchmark.
Do not inspect holdout failures while tuning. Record the final frozen candidate
before opening its holdout results. No expectations may change after observing
output. Evaluate each model three times per case, preserving turns within cases
and resetting context across cases. Randomize model order by recorded seed.

Candidates: system Apple Foundation Models; pinned Qwen3.5-2B and 4B Q4_K_M.
Record OS, system model metadata actually exposed, model artifact hash, runtime,
prompt hash, sampling settings, context and output budgets, cold/warm state,
time zone, fixed reference clock, load time, and actual per-turn results.
Simulator CPU measurements cannot establish iPhone GPU speed, battery or memory.

## Three distinct measurements

1. Model-only: one shared instruction and JSON contract for all models, identical
   user inputs, reference clock and context. No tools or planner writes. Preserve
   malformed, empty, timed-out, truncated and rejected generations as outcomes.
   A separate diagnostic may use each model's native structured generation; it
   must not silently replace the shared-contract comparison.
2. Rules: run the production routing/parser/context logic on the same frozen
   inputs. Report unsupported conversational generation as inapplicable, not a
   successful model response. Never map a route label to field correctness.
3. Product: observe Live Today routing, previews, commits, receipts and Undo with
   isolated synthetic data. A model-only answer is not a saved product action.
   Candidate model injection must traverse the same validation and write gates.
   Missing candidate integration remains unmeasured, not passed by substitution.

## Per-turn contract and evidence

The model-only response is a JSON object containing `intent` (chat, reminder,
event, alarm, edit, clarify), `reply`, `title`, `date` (YYYY-MM-DD or null),
`time` (HH:mm or null), `repeat` (once, daily, weekdays, weekly, monthly, yearly),
`weekdays` (Sunday=1), `duration_minutes` (integer or null), and `target`
(synthetic id or null). An extraction proposes
an action; it never claims a save. Questions and reported speech must not become
actions. Necessary ambiguity should yield one focused clarification. Timers,
world clocks and unsupported operations must be explicitly classified and
reported rather than silently relabeled as reminders.

Store input/case/turn/repetition, full raw output, parsed output, every checked
field, grading reason, stage/backend, actual call attempt, success/error class,
timeout/cancellation, fallback, first output and completion latency, generated
token count where available, and evidence path. Do not infer successful calls
from availability or an Apple Intelligence card label. Production telemetry must
not collect user message text; synthetic harness artifacts may retain it.

Report completed/eligible and pass/completed per category, language and backend;
unrun remains separate. A case passes only when every turn and required field
passes. Report semantic title preservation separately from literal QA brackets.
Report false execution claims, unintended writes, confirmation bypass and wrong
target edits separately, without averaging them away. Exclude harness defects
from model scores, retain them, fix the defect, and rerun the affected cell.
Use medians and p90 only with n and clock definitions; do not use sample code's
nominal token budget as the number of generated tokens.

## Iteration and final decision

Follow `goal-and-rubric.md`: measure baseline, identify a common root cause,
make one focused candidate change, rerun affected development cells, then run
the frozen candidate on the untouched holdout. Preserve earlier rounds. Stop
and audit the grader after 2-3 rounds without improvement. Keep production
confirmation and Undo boundaries from CLAUDE.md; product authority changes
require a separate explicit proposal.

Recommend one primary model or an explicitly defined routing policy based on
observed task correctness, safety, completion latency, availability and fallback,
privacy/offline operation, zero per-call local cost versus download/storage/
engineering costs, and integration evidence. State uncertainty and unmeasured
phone performance. A missing comparison is not evidence that the incumbent wins.
The final recommendation must explain which observed advantages justify its
cost and which acceptance criteria remain before release.
