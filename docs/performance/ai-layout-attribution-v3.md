# AI response layout attribution v3

Production base: main3ef64389fb390ee3270c3f1250d33f5c77722702, including delivered baseline, local fallback and Release footprint changes. This is measurement-only diagnosis; no new speed gain or production candidate is claimed.

## Question and fixed endpoint

The prior matched fallback conversation had n3 full turn→layout626.148916→309.332167ms (2.024x), versus the3x target208.716305ms. Response-ready improved7.431x, but ready→layout remained204.692–385.162ms. Local reply work0.219–2.539ms and Activity recording0.099–0.140ms cannot explain the remaining100.616ms gap. Feedback/response endpoints nearly coincide. These observations motivate attribution, not an animation/CPU causal conclusion.

The existing action/ready/geometry/two-display-link endpoints remain identical. Add ignored diagnostic timestamps around the existing messages observer persist() and scroll request, and within each existing probe: arm, first callback and first eligible geometry callback. First/latest timestamps are retained per turn; no new observable state or accessibility publication occurs before the existing endpoints finish. The marker layout_attribution=1 requires the full new set in the reducer. persist_call is elapsed time around a try? save path, not successful commit or durable persistence latency. Scroll request time is not animation duration.

## Minimal execution and decision

Reuse Today-Performance3243BEDB-4F6A-4807-AE9E-30115C528377 and the retained derived-optimized cache after the current resource holder releases. Build once Debug-O/jobs2/parallelNO and run only AIResponsePerformanceTests/testConversationFreshLaunchN3: three fresh processes, OS warm, identical today-dataset.json,09:41, Hello/fresh history, simulator unavailable-model fallback. Retain exact source/command, raw log and closed xcresult in primary tests/results; reduce the new same-turn points. No profiler, physical device, signing change, extra workload or Year diagnostic retry.

This changed diagnostic instrumentation is a new attribution cohort, not a before/after speed comparison with earlier traces. Framework geometry and callback waits are elapsed intervals, not exclusive CPU categories; overlapping observer/response spans must not be summed. Continue to preserve per-turn raw values and median/range; do not invent p95 from n3.

Reject a production optimization unless a safe removable app-owned operation consistently explains at least30ms. A save-dominated hypothesis must preserve successful-save and reopened-history semantics. A geometry/callback-dominated result does not justify deleting animation, moving the probe, or calling this endpoint presented/fully usable. If attribution remains inconclusive, report the specific unresolved boundary rather than claiming plateau.

## Validation status

Source `d74593e` was materialized in the retained project path, built once Debug-O/jobs2/parallelNO and ran the sole existing conversation method: PASS60.245s, xcodebuild exit0. Three fresh-process turns passed the original five endpoints, complete keyed attribution, exact reply/noAdd assertions. Device shutdown and Device-panel close completed; readback showed no booted simulator or heavy executable. Static diff check and five reducer regression tests also passed. One focused read-only source diagnosis recommended attribution before another production candidate.

| Same-turn elapsed interval | Raw n3 ms | Median ms |
|---|---|---:|
| persist() call |24.115,40.228,25.090|25.090|
| scroll request call |1.082,1.042,0.970|1.042|
| ready→response probe arm |27.880,44.117,28.594|28.594|
| response arm→first callback |116.949,266.387,89.102|116.949|
| first callback→eligible geometry |0.003709,0.003667,0.003875|0.003709|
| eligible geometry→original layout endpoint |35.378,71.293,57.459|57.459|

All three response probes were eligible on their first callback, so repeated rejection by the geometry guard does not explain these samples. Most of the measured response interval was before that callback; this does not tell whether the main thread was busy, scheduling was delayed, or the host/simulator constrained callback delivery. The remaining second eligible callback spacing is not a measured frame budget or hitch rate. persist() exceeded30ms once, not consistently, and the bounded sample does not justify changing save semantics. No safe removable operation meeting the candidate criterion was established. This is an unresolved attribution boundary, not a performance plateau.

This cohort full turn→layout was242.310000,441.476958,206.650625ms (median242.310000ms); changed instrumentation and integrated production source make it unsuitable for claiming a gain against the earlier309.332ms candidate median. Do not reset the original208.716ms target to one third of this diagnostic sample. The generic summary tool emits per-cohort target suggestions; the frozen paired comparison remains the acceptance denominator.

Canonical primary evidence: `tests/results/runs/performance-pages-ai-20261018/`, `layout-attribution-v3-b0094925.log/json`, exact `layout-attribution-v3-command.json`, `staged-source-layout-attribution-v3/manifest.json`, `layout-attribution-v3-{stages,summary}.json`, closed `layout-attribution-v3/ui.xcresult` and executed `layout-attribution-v3-products/`. All are archived/indexed in the separate QA Activity journal under `performance-ai-layout-attribution-20261018` (and `-ui`). No profiler, phone or model-available inference ran.
