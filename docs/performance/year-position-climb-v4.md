# Selected-year initial positioning experiment v4

## Decision

Reject the native initial scroll-ID candidate. The matched Year proxy median worsened17.85% and visit3 whole-app footprint rose15.01%; the three correctness journeys passed, but there is no performance benefit to adopt. A normal revert preserves the attempted source in history. Final PR94 contains only the common cross-year reentry regression guard and reports/targets; `CalendarView.swift` is byte-identical to production basecf92fabb. No endpoint, year range, marks, accessibility, cache policy or production behavior is changed by the final delivery.

## Fixed source and method

Production base `cf92fabb2b92dc59d78eba061ec2b1ea3c12039c`; common-test reference `2d9fba0e24238bc9dbe872c87965618afe17ca92`; rejected candidate `0a7beefdfbdcdb18198762410e30efff0dec8802`. Only the candidate production diff initialized an independent year-offset scroll ID and added `.scrollTargetLayout()`/`.scrollPosition`, retaining both proxy calls and all41 years. One focused source review found no material static defect. Apple documents [initial target preservation](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)) and [target layouts](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)), but promises neither skipped child layout nor proxy ordering.

Both sources used the same Today-Performance iPhone18ProMax/iOS27.0, SDK27.1, Mac14,10/16GiB/12CPU, retained derived-optimized DD, Debug `SWIFT_OPTIMIZATION_LEVEL=-O`, jobs2/parallelNO, canonical today-dataset/fixed09:41, and unchanged geometry plus two-display-link endpoint. Dataset SHA256e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7. Common measurement-file SHA2565ec55001e3c923e044838c8c5c19cd400106cb5f01b1d8b060009ea0b7e213dc; exact hashed paths are in contexts. Year counters off both sides; fixed-window resource sampling on both. One fresh process then two ordered revisits, n3, no p95. No presented-frame, real-touch, full usability, CPU attribution or model claim.

Reference host load16.31/27.49/26.66; candidate13.73/20.32/23.74. No competing heavy executable or booted simulator was present before the exclusive pair. High and unequal background load plus small ordered samples limit causal precision; neither a precise universal regression factor nor framework blame follows. They do not establish the requested improvement, and memory worsens in all three matched visits. Do not compare these timings against the earlier counter-enabled cohort.

## Actual matched observations

| Metric | Reference visits1/2/3 | Rejected candidate visits1/2/3 | Result / target |
|---|---|---|---|
|Year action→layout ms|1045.320 / 982.892 / 1298.620|1632.606 / 1016.104 / 1231.932|median1045.320→1231.932ms; reference/candidate0.849x, no3x or10x|
|Year post-layout whole-app window median MiB|258.659 / 254.464 / 253.823|297.018 / 288.050 / 291.925|visit3253.823→291.925MiB; +15.01%, no51% reduction|

Each source supplied22 valid windows and seven complete same-PID operation/history groups (referencePID75812; candidatePID84449). Other root transitions remain separate observations in comparison.json; positive changes elsewhere are not cherry-picked to accept the failed Year candidate. Whole-app windows are not exclusive Year bytes, true peaks, retained ownership or leak evidence.

## Functional acceptance and bounded execution

Reference build+two methods PASS, producer0: chosen-day offsets0/400 plus reentry64.093s; root navigation/kept-state129.092s. Candidate build+four methods PASS, producer0: chosen-day58.033s, holidays/key17.164s, trip/birthday27.676s, root journey121.495 seconds. Test elapsed is automation cost, not product latency. Both use the identical added guard: after choosing offset400, reenter Year without corrective scrolling; selected-year January is fully visible/hittable, then Month retains the exact chosen date. Every original assertion remains.

The pair ran22:26:33–22:35:00UTC, about8.44min including builds; shutdown/panel close and exact heavy[]/booted[] followed, then capacity was released directly to the Reminder sole writer. No expanded batch, profile, phone/signing/data deletion or equivalent rerun. The final production revert needs no additional build: it restores the reference production bytes already measured and passed with the common test guard; remaining edits are documentation.

## Durable evidence and next work

Primary `tests/results/runs/performance-pages-ai-20261018/year-position-v4/`: exact reference/candidate commands and contexts, frozen manifests, comparison.json, both resources summaries, complete closed reference/candidate ui.xcresult, and preserved app/runner Products. Parent raw logs `year-position-reference-v4-f9ef886e.log` and `year-position-candidate-v4-682c5537.log` retain exact host context and producer status. Everything closed is indexed/archived through the QA journal, separate from user Activity. The original preparation manifests remain under initial-* for provenance. No required input lives only in/tmp.

The [new target registry](climb-targets-v5.md) preserves original owner goals, separates current integrated source from historical measured cohorts, and prioritizes AI full response, actual compressed bytes and Year allocation/positioning attribution. This rejected narrow experiment is not proof of a global plateau. The earlier cache diagnosis still rules out41-year eager computation and dominant timedcomputeMarks for its workload; this pair does not identify the new binding's allocation or CPU owner. No new production candidate is silently substituted.
