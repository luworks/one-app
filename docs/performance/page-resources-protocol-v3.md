# Page resource baseline protocol v3

Production reference: main5767d81c767ffec43e328aeaa6d974b3507e3c30. This independent resource cohort supplements26 accepted page latency endpoints and7 root transitions; it is not a new speed comparison or complete every-page resource coverage.

## Boundaries and metrics

Use optimized Debug (-O), the existing DEBUG fixture guards, today-dataset.json/in-memory store/fixed09:41, Today-Performance iPhone18ProMax/iOS27.0, existing derived-optimized cache, jobs2 and serial UI. No PERFORMANCE compile definition, signing change, physical device or user-data reset. Record exact measurement source, command, host load, SDK/runtime, fixture hash and sample order. Resource instrumentation requires -performanceResources + -performanceTrace + -uiTesting and is compiled out behind DEBUG with a disabled Release API stub.

- A separate serial utility queue samples TASK_VM_INFO roughly every100ms from the original action start through a fixed1s post-layout window. Check Mach return code and response byte count before interpreting phys_footprint/resident_size. Keep raw timestamps, errors/nulls and observed sample gaps. Timer completion can follow the window deadline; retain that callback raw with collection_end_ns but exclude it from window statistics.
- Fixed-window memory: median/range of valid phys_footprint samples at layout≤ns≤layout+1s. This is a fixed-window steady-state proxy, not proof that all async work settled. resident_size remains a distinct raw field, never relabeled physical footprint.
- Sampled operation maximum: maximum valid phys_footprint from action start through that deadline. Sampling can miss short peaks. It is different from the native XCTest measured peak.
- Revisit growth: same PID/page, ordered visits1→3 of the unchanged first-cycle-plus-two-revisits journey. Preserve individual visit values and negative growth; do not claim leakage or pool independent methods/processes. Returning-anchor retention remains unmeasured unless an equivalent anchor is explicitly sampled.
- Native scrolling: XCTMemoryMetric(application:app) plus iOS26+ XCTHitchMetric(application:app), one fixed fast upward gesture per measured iteration; stopMeasuring before downward reset. iterationCount3 includes one additional discarded warmup invocation. Retain actual metric IDs/units/raw values. Missing/error providers are missing, not zero. No FPS/hitch inference from elapsed scrolling duration or display-link spacing.

The original app latency start/end points remain unchanged. Sampling bookkeeping does not publish SwiftUI state during that endpoint. After the1s resource window closes, append a same-seq/generation base64 JSON payload to the already existing performance.trace accessibility report; XCTest retains the raw PERF_RESOURCE_APP JSON and attachment. This additional sampling/observation cost makes these resource runs a separate cohort.

Apple documents the app-target native memory peak/growth semantics in [Preventing memory-use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions), the task VM structure in [task_vm_info_data_t](https://developer.apple.com/documentation/kernel/task_vm_info_data_t), and the scrolling/hitch measurement workflow in [WWDC2025 performance testing](https://developer.apple.com/videos/play/wwdc2025/247/?time=2080). Local Xcode27.1 headers confirm XCTHitchMetric availability; actual simulator provider output still requires execution.

## Focused execution and acceptance

Build once on the retained project path/cache and run PageScrollResourceTests/testYearNativeScrollResources first. If provider works, reuse Products with test-without-building for PagePerformanceTests/testHealthResourceWindows and testClockResourceWindows; Settings/Activity is separately queued, not silently added to the initial batch. Keep routine verification around10min, stop equivalent failures and retain raw evidence. No historical Year profiler retry is involved: this is a new native metric protocol.

Six reducer checks cover raw deduplication, failed functional attempts, missing provider data, nonmonotonic/conflicting input, negative revisit growth and exclusion of the final late callback. Five or more valid post-layout samples are needed for a usable window; a completed UI method alone does not establish valid memory/provider data. Native metric extraction preserves unknown IDs before classification from actual output.

Proposed memory/sample-peak and hitch targets are51% lower than each matched positive baseline; zero already represents a floor, and negative growth is not a target to make more negative. These are aspirational goals until paired measurements verify them. Match source/config/fixture/page/visit sequence/window/cadence before comparing. No p95 from three visits and no competitor/top-app memory numbers are invented. Apple guidance is a platform reference, not a measured competitor.

Execution/results: [actual first batch](page-resources-results-v3.md). One incremental build and three targeted methods passed; native hitch provider returned no metric and remains missing, not zero. Settings/Activity remains pending. Source review keeps the original Health/Clock/Settings journey bodies and assertions unchanged; only opt-in resource wrappers and native Year scrolling metrics are added.
