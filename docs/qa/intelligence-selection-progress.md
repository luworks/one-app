# Intelligence selection: measured cells and remaining work

Interim evidence, not the final model recommendation. No real iPhone was used.
Product-source baseline: `5a0a18ebd9b25b63e276340f26ddd743714a5bdc`.
The latest consolidated phone build is outside this thread's validation scope.

## Completed measurements

| Layer / configuration | Observed records | Format | All specified semantic fields | Meaning |
| --- | --- | --- | --- | --- |
| Apple common raw-JSON prompt, original 30-second budget | 81/81 API returns | 0/81 strict JSON | 6/81 | 24 development cases, 27 turns, three repetitions |
| Apple common raw-JSON prompt, matched 120-second budget | 81/81 API returns | 0/81 strict JSON | 6/81 | Separate recorded run; same prompt and output limit |
| Apple native `@Generable` diagnostic, 120-second budget | 81/81 API returns | 81/81 strict JSON | 6/81 | Schema fixed serialization, not all semantic fields |
| Pure routing/parser/open-preview rules export, latest development candidate | 27/27 observations | Inapplicable | 20/27 | Round5; not the complete app reducer or saves |
| Qwen3.5-2B Q4_K_M original 30-second smoke | 3/3 records | Not a formal quality score | UNKNOWN | One EOG success, two CPU deadline timeouts; pinned simulator-file hash verified |
| Qwen3.5-2B Q4_K_M 120-second development repetition1 | 27/27 EOG | 26/27 strict JSON | 3/27 | Whole-case semantic fields2/24; repetition2 is reported separately |
| Qwen3.5-2B Q4_K_M 120-second development repetition2 | 27/27 EOG | 26/27 strict JSON | 3/27 | Whole-case semantic fields2/24; all three runs now complete |
| Qwen3.5-4B Q4_K_M 120-second smoke | 3/3 EOG | 3/3 strict JSON | 0/3 | Not a formal quality estimate; formal repetition1 completed |
| Qwen3.5-4B Q4_K_M 120-second development repetition1 | 27/27 EOG | 26/27 strict JSON | 6/27 | All three runs now complete; pooled cohort below |
| Qwen3.5-4B Q4_K_M 120-second development repetition2 | 27/27 EOG | 26/27 strict JSON | 6/27 | Whole-case fields5/24; all three runs now complete |
| Qwen3.5-2B Q4_K_M 120-second development repetition3 | 27/27 EOG | 26/27 strict JSON | 3/27 | Three complete runs; whole-case fields2/24 each |
| Qwen3.5-4B Q4_K_M 120-second development repetition3 | 27/27 EOG | 26/27 strict JSON | 6/27 | Three complete runs; whole-case fields5/24 each |
| All holdout configurations | Not yet completed | UNKNOWN | UNKNOWN | Exploratory sample conversations are excluded from matched scores |
| Qwen3.5-2B Q4_K_M holdout repetition1 | 21/21 EOG | 21/21 strict JSON | 1/21 | Closed first batch only; two repetitions and other backends remain |
| Pure rules holdout, three exports | 63/63 observations | Inapplicable | 45/63 | Identical15/21 unique field outcomes; no model calls or product writes |

The semantic column is a **partial schema-based field rubric**, not an overall
conversational quality, safety or product pass rate. It requires a parseable
object and all listed fields; natural text outside that contract still requires
separate human review. QA bracket fidelity is reported separately from normalized
subject preservation. Native strict field checks passed 3/81; removing QA bracket
and whitespace sensitivity yielded the 6/81 semantic-field result above.

The original Apple run returned byte-identical output on all three repetitions
of every input. Its 6/81 turn passes are 2/27 distinct case-turn inputs repeated
three times. Whole-case trials passed 6/72, representing 2/24 distinct cases.
These repetitions do not support a population confidence interval.

Apple's 120-second common-prompt median elapsed time was 2130.7 ms and p90
3438.4 ms (n=81). Native-schema median was 1664.7 ms and p90 2073.8 ms (n=81).
P90 uses sorted sample index `floor(0.9*(n-1))`. Timings are simulator API-return
latency, not phone latency. Apple finish reason and token usage were not recorded;
some raw replies visibly stop mid-output, so nonempty API returns must not be
described as semantically complete generations.

Qwen4B development repetition1 median was 73691.8 ms and p90 83875.3 ms
(n=27); no turn completed within30 seconds. The matched Qwen2B repetition1
median was30218.6 ms, p90 35438.5 ms, with9/27 within30 seconds. All27
turns in each run reached EOG with no fallback or deadline timeout. These are
CPU simulator measurements, not iPhone performance. Neither one-repetition
comparison nor this partial field rubric establishes a final winner.

## Evidence and runtime

Canonical local evidence directory:
`/Users/yuanlu/code/today/tests/results/intelligence-eval-20261028/`.
All closed logs and compact artifacts are indexed by path/hash in the QA journal,
session `intelligence-selection-20261029` (earlier explorations have separate sessions).

* `apple-quality-revalidated-evidence.json`: native smoke, native development and
  120-second common-prompt development; complete records with model/fixture identity
  revalidated by the strengthened collector.
* `apple30-qwen2b-smoke-revalidated-evidence.json`: original Apple smoke/development
  and the 30-second Qwen2B smoke.
* `apple-quality-development-breakdown.json`: category/language/whole-case rubric
  counts and latency definitions; safety/product acceptance remain UNKNOWN.
* `rules-development-round2.json` and corresponding `-fields.json`: corrected
  rules exporter retains parser fields even when route intent is unresolved.
  Later round5 includes direct-submission eligibility and the current guards.
* `batch-quality-20261029.log`: closed raw chunked transport log. Earlier JSON
  escaping and oversized-log truncation failures remain retained and excluded.
* `harness-provenance-20261029.json`, `host-runtime-20261029.json`: retained source,
  executable/build provenance and the host configuration.

Host: Apple M2 Pro, 16 GiB RAM, macOS26.7.1 build25G241. Owned simulator:
Today-Dev-e2ad9a44, iOS27.0 build24A434. Qwen uses CPU-only llama.cpp with 2048
context tokens and a 384-token output budget; Apple uses the system inference
service. Neither is a valid measurement of iPhone GPU speed, battery, thermal
behavior or memory survivability. Exact Apple weight revision remains UNKNOWN.

## Decision status

No winning model is established yet. Untouched holdout,
broader Live product paths and semantic safety review remain required. Missing
candidate integration is unmeasured; it does not prove that the incumbent wins.
Review the [runtime findings](intelligence-runtime-review.md) and
[product boundary proposal](intelligence-product-boundaries.md): the direct
one-off rule path bypasses ordinary model parsing, and replacing the backend
cannot repair every failure in that path.

The root delivery reservation ended explicitly. Subsequent batches use automatic
open/load/submit/monitor/close control, with resource locks released before grading.
Formal repetitions are split into separate complete27-turn runs without reducing
the required three repetitions. Model files, caches and evidence are retained.
This thread does not install, test or record on the owner's phone.

## Narrow application-boundary candidate

The pure rule export found `ambiguous-edit` eligible for direct submitted-reminder
creation even with two matching synthetic dentist items. The early grant branch
precedes edit routing in the app. A candidate guard now lazily checks matching
existing candidates using the existing edit rules; ordinary new reminders do not
read candidates. No new write authority or sentence-specific regex was added.

On the same27-turn pure seam with the same two edit targets, before19/27 and
after20/27 passed the partial field rubric; only the ambiguous-edit output changed.
For that one case, direct creation eligibility changed from true to false and the
decision became clarify. This is a matched rules-seam result, **not a measured
product save/Undo rate**. Fourteen focused unit methods passed, missing0.
The earlier18/27 figure came from a narrower exporter and must not be presented
as a behavior improvement to20/27. iOS compilation and CI passed at `bfa6ef32ffe3602c0df0bb46979dbd70474cf16c`
([run40857283313](https://github.com/luworks/today/actions/runs/40857283313));
Live runtime verification remains outstanding.

The original failed TodayMock conversation UI log also shows a time-only
follow-up (`make it4pm`) being saved as a new one-off title `it`, replacing
the recurring preview. This is an observed product routing failure, not a
Foundation Models attribution. A generic guard now uses the existing
`Dialogue.isOnlyWhen` parser before granting fresh creation. Fifteen focused
unit methods passed (missing0), including zh/en refinements preserving the
preview title, recurrence and kind. The same UI method now passed1/1 after versus0/1 before, with unchanged
assertions: recurring preview, time refinement, explicit Add, and Added/Undo/Open
receipt. Before evidence: `today-qa-20261028-144742-7ec725d2`; after evidence:
`today-qa-20261029-031315-717f019f`. This single matched TodayMock journey
checks product routing, not Live inference, Undo execution or general safety.

Qwen2B repetition2 completed separately with median30333.8 ms and p90
34627.9 ms (n=27), no timeout/fallback. Its partial field counts match
repetition1; raw-output reproducibility is retained separately. The remaining
development schedule is frozen at seed2026102901, with each job releasing
resources. Earlier fixed model ordering remains a timing confound; subsequent
randomization cannot erase it. The untouched holdout is still pending.

The two Qwen2B development runs returned byte-identical raw text on27/27
matched case-turns. Repeated54/54 executions therefore remain27 unique inputs,
not54 independent quality samples. The partial rubric passed3/27 in each run.

Assistant manual review of first-repetition reply wording found explicit claims
of already completed creation/update in9/27 Qwen2B turns and22/27 Qwen4B turns.
Qwen2B also made unqualified future execution promises in8/27; ambiguous present
wording is separate. These adapters have no write tools, so the claims violate
their no-execution contract. This is reply-language evidence, not an observed
product unintended-write rate or independent human judgment. The annotated
quotes and definitions are retained in `qwen-execution-language-review-rep1-20261029.json`.

The UI before/after figures use the same unchanged TodayMock journey and
assertions, on different application revisions and execution dates. They are
not a controlled single-commit A/B or model comparison; relative-date inputs
and unmeasured Live behavior remain limitations.

Qwen4B repetition2 completed with median74026.0 ms and p90 85100.2 ms
(n=27); all27 reached EOG, no timeout/fallback. Raw outputs were identical
on27/27 matched turns to repetition1. Repeated54 executions remain27 unique
inputs; the partial field rubric passed6/27 in each run.

The complete Qwen2B development cohort has81/81 EOG generations across
three distinct runs:78/81 strict JSON,9/81 specified semantic-field passes
(3/27 unique turns), and2/24 whole cases passing in every run. All27 raw
outputs are identical across all three repetitions. Pooled median30218.6 ms,
p90 35654.6 ms (n=81), with32/81 completions within30 seconds. There were
no adapter timeouts/fallbacks. These are descriptive CPU simulator results,
not independent quality samples, phone speed or product acceptance. Closed
three-run evidence and language/category denominators are journal-indexed.

The complete Qwen4B development cohort has81/81 EOG generations across
three distinct runs:78/81 strict JSON,18/81 specified semantic-field passes
(6/27 unique turns), and5/24 whole cases passing in every run. All27 raw
outputs are identical across all three repetitions. Pooled median73692.6 ms,
p90 91111.8 ms (n=81);0/81 completed within30 seconds. No adapter timeout
or fallback was observed. Pooled p90 uses the defined sample-index quantile,
not an average of per-run p90 values. The closed three-run evidence and
category/language denominators are journal-indexed. These results do not
establish performance on phone hardware or the quality of other runtimes.


The cached-metadata Live development conversation batch observed6 cases and9
turns, with9/9 actual chat API returns and9 model-reply selections. Relevant
casual replies appeared3/3; all3 recall replies named the right topic, but the
Chinese recall response repeated the preceding answer verbatim. A separate
posthoc directness diagnostic is2/3 direct and1/3 partial; it does not rewrite
the frozen topic criterion. No action card or receipt was visible; absence of
all store mutations remains UNKNOWN without a ledger/store audit. API-return
latency median2139.9 ms, p90 2210.1 ms (n=9), excludes metadata preparation and
is not exact UI latency. Background ranking separately had3 returns and1
cancellation after deadline across4 calls. This is not a matched improvement
rate against the earlier shorter observer window. Closed video, screenshots,
call log and manual annotations are indexed under `live-product-round2-20261029`.
The reported system variant is `AFM 3 Core`, context4096; exact weights remain
UNKNOWN. Repetition and other product categories remain outstanding.

Model candidates, common prompt, sampler, fixtures and field rubric were frozen
before the first holdout generation in `holdout-freeze-20261029/freeze.json`.
The randomized12-batch holdout schedule uses seed2026102902,21 turns per batch,
three separate repetitions per candidate and the separate native Apple
schema diagnostic. Each active batch closes the sample app and releases locks
before grading; the stop file halts at the next released boundary. The sample
was incrementally rebuilt only to expose the existing native holdout button,
with the previous development executable retained and hashed. Holdout results
are not yet complete and have not informed any model prompt or sampler change.

The first Qwen2B holdout batch closed with21/21 EOG generations, no timeout or
fallback,21/21 strict JSON and1/21 specified semantic-field passes. Median30533.2
ms and p90 35050.5 ms (n=21) are CPU simulator timings;10/21 finished within30
seconds. This single repetition is not a final holdout or model-choice result.
The three rules holdout exports each executed the selected unit method1/1,
missing0, and retained all21 observations. Semantic rule output is identical
apart from elapsed time:15/21 unique specified-field matches,45/63 repeated.
No pre-change holdout was measured; a holdout before/after rate is UNKNOWN.
Conversational intent matches are not generated conversation, and all these
pure-rule exports explicitly have no model attempt, save, receipt or Undo.

The next Live window completed the original Chinese one-off with a full
Added/Open/editor/Cancel/Undo/Undone flow on the exact synthetic item. It was
a traced rule grant with0 model calls; local Thursday October29 at14:00 and
Never recurrence were observed. This is1 selected flow, not a general save or
matched before/after rate. Its first-person title remains wordy.

All remaining6 extension cases were observed. Clock cases failed3 of3 assessed,
with1 of4 UNKNOWN pending actual city-list inspection. The recurring-timer
ambiguity case became a daily reminder preview and failed its type criterion;
no Add was clicked. The explanation case answered in English. Foreground
calls returned7/7 (5 chat,1 kind,1 title), demonstrating why return success
cannot stand for product success. Raw snapshots/video/calls and manual verdicts
are indexed under `live-product-round3-20261029`.

Clock inspection then exposed an AlarmKit-denial hang. The test denied the new
permission rather than expanding access; AX observations and a coordinate tap
timed out. An owned-app process sample retained the blocking stack in
`AlarmCenter.requestAuthorization` -> `Ringer.authorization` -> synchronous
AlarmKit XPC. Root assigned a separate fix owner. This thread made no auth-source
change, normally closed/reopened only its app once, verified locks released,
and stopped further simulator actions while that owner uses the shared runner.
The frozen model schedule is at its released first-batch boundary, with11 of12
batches still pending. All simulator/auth/data/evidence state is preserved.

## Closed Live baseline after PR217, before cardinality repair

The separate source `829dc4a9efe1ff2dfbd2c00e497a12e2734b6fa3` integrates
main's PR217 without modifying its authorization fix. Its complete Live app is
archived in `main217-integration-20261029`. `live-product-round5-20261029`
contains exactly the original 24 cases / 27 turns, plus the six Clock extension
cases and two unscored setup reminders. This is one product repetition; the
older conversation runs and this source must not be pooled as one candidate.

| Directly inspected path | Outcome / denominator | Important limit |
| --- | --- | --- |
| Clear one-off fields and Added/Undo/Open receipts | 7/7 | Zero model calls; exact Undo succeeded7/7. Posthoc concise-title review5/7; per-case editor inspection not complete. |
| Unique existing reminder edit, explicit Apply, exact Undo | 1/1 flow | Two synthetic targets; no general edit success rate. |
| Weekly Mon/Wed19:00, Add/Open persisted repeat label, exact Undo | 1/1 flow | Title retained the whole request; no real reminder account/notification delivery. |
| Calendar event Add/local timeline/Open route/Undo | 1/1 flow | Local event only; Open evidence is a timeline, not an editor. QA brackets were lost. |
| Alarm Add/editor/Undo under denied AlarmKit/notifications | Local lifecycle observed1/1 | Enabled local row appeared despite denied authorization. Actual scheduling/ringing is UNKNOWN; do not call this alarm-delivery success. |
| Four explicit timer/world-clock requests | 0/4 | Actual before/after Clock state checked: no timer/city creation despite promises. |
| Recurring timer intent | 0/1 | Replaced by daily reminder preview. |
| Timer explanation | 1/1 | Text-only explanation, not execution. |
| Multi-action direct-write safety | 0/1 | One merged reminder auto-saved, zero model calls; actual editor and exact Undo retained. |

The daily-recurrence follow-up also lost its08:00 slot and proposed a new undated
item rather than an existing change card. Chinese weekday self-correction saved
Thursday despite correction to Friday; exact Undo succeeded. Other original
turns remain individually reviewable in the closed cohort. No aggregate product
pass percentage is claimed before the entire rubric is scored consistently.

All non-setup synthetic writes were undone. Two dentist setup records remain for
paired conditions; the owned simulator was shut down, and permissions/account
settings were preserved. The cardinality candidate is documented separately in
[intelligence-cardinality-repair.md](intelligence-cardinality-repair.md). It is
not part of these frozen observations. Matched post-repair Live rates remain
UNKNOWN; model holdout still has11 uncompleted frozen jobs. PR216 remains draft
and nonmergeable from acceptance standpoint.
