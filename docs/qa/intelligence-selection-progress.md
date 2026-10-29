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
| Pure routing/parser/open-preview rules export, corrected exporter | 27/27 observations | Inapplicable | 18/27 | Not the complete app reducer, existing-item resolution or saves |
| Qwen3.5-2B Q4_K_M original 30-second smoke | 3/3 records | Not a formal quality score | UNKNOWN | One EOG success, two CPU deadline timeouts; pinned simulator-file hash verified |
| Qwen3.5-2B Q4_K_M 120-second development repetition1 | 27/27 EOG | 26/27 strict JSON | 3/27 | Whole-case semantic fields2/24; two repetitions still required |
| Qwen3.5-4B Q4_K_M 120-second smoke | 3/3 EOG | 3/3 strict JSON | 0/3 | Not a formal quality estimate; formal repetition1 completed |
| Qwen3.5-4B Q4_K_M 120-second development repetition1 | 27/27 EOG | 26/27 strict JSON | 6/27 | One complete repetition; two repetitions still required |
| Remaining Qwen formal repetitions and all holdout | Not yet completed | UNKNOWN | UNKNOWN | Exploratory sample conversations are excluded from matched scores |

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
  The subsequently added direct-submission eligibility observation is not yet rerun.
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

No winning model is established yet. Remaining Qwen formal trials, untouched holdout,
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
as a behavior improvement to20/27. iOS compilation, Live UI reproduction and CI
verification of the candidate remain outstanding.

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
