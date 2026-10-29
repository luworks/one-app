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
| Qwen3.5-2B/4B matched formal development and holdout | Not yet run | UNKNOWN | UNKNOWN | Exploratory sample conversations are excluded from matched scores |

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

No winning model is established yet. Qwen formal trials, untouched holdout,
broader Live product paths and semantic safety review remain required. Missing
candidate integration is unmeasured; it does not prove that the incumbent wins.
Review the [runtime findings](intelligence-runtime-review.md) and
[product boundary proposal](intelligence-product-boundaries.md): the direct
one-off rule path bypasses ordinary model parsing, and replacing the backend
cannot repair every failure in that path.

Heavy resources were released normally for root's consolidated phone delivery.
The owned simulator is shut down; model files, caches and evidence are retained.
This thread does not install, test or record on the owner's phone.
