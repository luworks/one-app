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

Static diff check and five reducer regression tests passed (including required-point failure and same-turn wait extraction). No Swift build or UI execution has run for this revision yet. One focused read-only source diagnosis recommended attribution before another production candidate; this document records its concrete findings and reject criterion.
