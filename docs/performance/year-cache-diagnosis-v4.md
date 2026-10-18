# Year cache evaluation diagnosis v4

## Question and fixed source

The [root resource baseline](root-resources-v4.md) observed about250MiB whole-app footprint in Year and a similarly high window immediately after returning to Week, before later states fell near100–122MiB. This does not prove a leak or exclusive Year allocation. Current source `YearView` has a41-year `LazyVStack/ForEach` whose closure synchronously calls `yearSection`→`marks`→`computeMarks` on a cache miss before returning its view value. The framework may evaluate offscreen children for sizing/prefetch/scroll positioning; source inspection proves neither all41 years are evaluated nor only visible years are evaluated.

Production reference `f1c8e19f449335cb273d83afbb1d569fe9a00fe8`; frozen diagnostic source `0adb5c46d026ca67c56144cdf61324b43d399acb`. This includes the newly accepted Activity hydration implementation, so it is a new diagnostic cohort, not a memory/latency comparison against earlier aa7 root data. No production optimization is proposed here.

## Counters and acceptance

`YearCacheTrace` exists only in DEBUG and requires all four flags: `-uiTesting`, `-performanceTrace`, `-performanceResources`, `-performanceYearCacheCounts`. The mutable store/lock/event buffer is allocated only when enabled. Record cumulative requests/hits/misses, cache invalidation sequence, completed miss year/start/end uptime/cache count, and year-header appeared/disappeared lifecycle events. No marks, titles, models or signatures are retained. The event cap256 has an explicit truncated count. Diagnostics live for the process independently of product cache invalidation; clearing a product cache must not erase earlier work evidence.

The serial resource queue attaches an optional immutable snapshot at its layout observation. Original action/layout timestamps, two-display-link endpoint, sampling cadence and functional assertions stay unchanged. `snapshot_ns` can follow `layout_ns`: aggregate counts describe snapshot time only. Endpoint claims must filter event `ns <= layout_ns`; completed miss wall durations also need `start_ns >= operation.start_ns` for operation-local costs. Miss `ns` is completion time. Durations are wall observations around mark computation/cache insertion, not CPU/render cost or allocated bytes. An in-flight request can make cumulative requests exceed completed hits+misses.

Header appeared/disappeared is lifecycle evidence, not viewport visibility. Compare completed missed years with ever-appeared headers by the exact endpoint, preserving invalidation episodes and events before/after the action. A few misses before their headers appear are normal ordering, not evidence of eager work. Many far years completed while only a small header set has appeared would support evaluating unnecessary/remote-year work as a candidate; it still would not explain250MiB or prove safe savings. If only the requested year and nearby prefetch years are computed, reject the41-year eager-computation explanation. Truncated/missing/failed-functional snapshots cannot establish absence or complete n3 diagnostic coverage.

No year range, day buttons, marks, VoiceOver content, state retention, cache policy or production scheduling is changed. Any later optimization must be separate, justified by this evidence, and accepted only by matching the original workload/config/endpoints and kept-state assertions. Existing51% memory and3x latency aspirations are not achieved by adding counters.

## Execution and actual findings

Static checks, one focused source review and11 reducer unit cases passed. An actual compatibility check consumed the earlier closed22-window root log: absent counters remained missing, not zero, and no counter n3 group was accepted.

The single retained-cache optimized-Debug build and `PerformanceClimbTests/testRootYearCacheDiagnosticWindows` passed130.622s; producer0,22 valid VM windows,358 valid in-window samples, maximum sample gap147.157ms. One PID41123, complete same-PID Year visits1/2/3, no truncated counter events. Original navigation, reminder-list and Calendar-mode restoration assertions passed. Pre-run host load averages26.68/29.46/22.85, exact heavy executable/booted-device readback empty. These instrumented wall timings are diagnostic, not a comparable speed denominator for an uninstrumented candidate. The simulator was shut down/panel closed and capacity handed directly to Reminder v2; no further method or profile was added.

| Year entry | Requests /hits /misses as of snapshot | Misses in this operation | Timed compute+insert wall ms | Original action→layout proxy ms | Timed span /proxy | Whole-app fixed-window median MiB |
|---|---|---:|---:|---:|---:|---:|
|1|19 /11 /8|8|19.217|932.465|2.06%|258.19|
|2|62 /46 /16|8|9.651|933.049|1.03%|248.53|
|3|105 /81 /24|8|14.624|823.281|1.78%|249.99|

Every entry completed misses for2006/2007/2008/2024/2025/2026/2027/2028, with last observed cache count8 and invalidation sequence1/2/3. By each endpoint, headers2006/2007/2008/2025/2026/2027/2028 had appeared; only2024 was missed without a corresponding appeared header, which can be ordinary prefetch and proves no visibility defect. Snapshot observation followed the original endpoint by1.294/0.762/1.477ms; the reducer filters events at `layout_ns` and never backdates the cumulative counter columns above.

The41-year eager-computation explanation is rejected for this workload. Timed `computeMarks`+cache insertion is only~1–2% of the proxy span; this does not time signature hashing/cache lookup, header/body construction or rendering. No large speed/memory benefit is justified from batching this timed function alone. These are wall intervals, not CPU samples, and no retained-allocation owner or leak is established.

A different source-backed hypothesis remains: the original `.onAppear { proxy.scrollTo(...) }` allows initial historical-header work before selected-year positioning. In three entries,2006–08 appeared around378.267/382.077/331.954ms after action, then disappeared around848.847/847.860/757.266ms as2025–28 appeared. Selected2026 header appeared around848.850/847.867/757.267ms. These are lifecycle timestamps, not pixel presentation or proof that the intervening wall time is all removable work.

## Decision and next bounded candidate

Deliver this measurement/report independently. Do not adopt historical trip-band batching or cache eviction as a51% memory fix from these observations. P1 next candidate may seed a native selected-year scroll ID before first layout, retaining all41 years and existing day/month actions, VoiceOver, kept state and programmatic day-change positioning. Apple's [`scrollPosition(id:anchor:)`](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:)) supports an initially bound ID with [`scrollTargetLayout()`](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)); it does not promise that no other children are laid out. A candidate is not implemented or accepted in this PR. Keep the original proxy positioning in the first narrow experiment to isolate the earlier native seed, and reject any wrong year, rebound, changed retention or interaction failure.

Use a new exact-current-source reference/candidate pair, same flags/config/fixture/operation history and original endpoints. Do not claim production speed from comparing this counter-enabled/high-load cohort with a counter-disabled candidate. Any gain needs a matched counter-disabled comparison; counter-enabled results diagnose the mechanism only. Proposed latency3x/memory51% targets remain unchanged and unverified. No p95, FPS, energy, top-app competitor number or physical-device claim is inferred.

## Durable evidence and integration

Canonical `tests/results/runs/performance-pages-ai-20261018/`: `year-cache-v4-command.json`, `staged-source-year-cache-v4/manifest.json`, raw `year-cache-v4-ec342de5.log`/context JSON, closed `year-cache-v4/ui.xcresult`, `year-cache-v4-summary.json`, matching Products under `year-cache-v4-products/`. All closed artifacts are indexed/archived by the separate QA journal. No required input is temporary. The exact measured source remains0adb5c4 onf1c8e19; final PR normal-merges separately accepted native-header main84162a1 without changing Year/counter code. No equivalent passing UI repeat is claimed as newer-header runtime acceptance.

Reproduce reduction: `python3 tests/performance/summarize_year_cache.py CLOSED.log --output NEW.json`. It reuses resource/functional gates, validates timestamps/truncation, retains raw providers/hashes and snapshot counters, and accepts n3 only for the dedicated method with complete visits1/2/3. The exact build command reuses Today-Performance/derived-optimized, jobs2/parallelNO and original three-cycle root journey. No Year profiler retry or production optimization ran.

The unrelated [Activity report](activity-hydration-v4.md) also receives a metadata clarification from actual SwiftPM Release PIF: `SWIFT_OPTIMIZATION_LEVEL=-Owholemodule`; earlier generic `-O` wording did not change either executed command or numerical result. New version2 comparison contexts preserve that exact name while retaining originals. This documentation clarification needs no duplicate benchmark.
