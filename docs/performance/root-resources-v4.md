# Shared-root resource baseline v4

Frozen production reference: main`aa7c7c89b74d7107c618b18fa2d6fb6f6011625c`, including completion writeback PR89 and page resource baseline PR87. This extends resource coverage to the existing seven-transition/kept-state journey; it is not a production optimization or speed comparison with earlier cohorts.

## Fixed semantics

Reuse [resource protocol v3](page-resources-protocol-v3.md): optimized Debug-O, same fixture/in-memory store/09:41, Today-Performance iPhone18ProMax/iOS27.0, retained derived-optimized, jobs2 and serial UI. Original action/layout endpoints and the complete root navigation/kept-state assertions stay unchanged. The new opt-in wrapper waits for a same-seq/generation1s resource window after each of the seven transitions, repeated in the original order three times. A shared XCTest collector preserves the already validated raw JSON/VM assertions instead of duplicating them.

Resource payload schema1 remains compatible. Existing page visits retain page-route counting. Root transitions previously had no page visit number; resource-only operation-name counters now label completed layout visits1/2/3 with visit_basis=layout_operation_name. No latency report fields or timestamps change. The reducer never pools different visit bases. The first cold-process Today launch is a separate one-off window; clock→Today visits are comparable returning-anchor proxies, not equivalent to the initial launch or proof of leaks.

App-wide physical footprint in each visible state remains distinct from exclusive page allocation, native XCTest peak, RSS, hitches or presentation. Same-PID ordered cycle growth can identify a state needing allocation/lifetime diagnosis; it does not establish redundant retained views or justify tearing down state. Any later candidate must keep the existing reminder-list and Calendar-mode restoration assertions and match operation history/window/cadence. All resource sampling remains DEBUG-only; Release retains the disabled stub.

## Execution status

Source review and seven reducer tests passed, including incompatible visit-basis rejection. No Swift/UI has run for this new wrapper yet. Planned single incremental build + PerformanceClimbTests/testRootNavigationResourceWindows, without additional methods. Settings resource attempt on old64a3de9 is separate: failed third Settings action isHittable116.861s,7 diagnostic windows only; finalizer stalled and was stopped after bounded SIGINT/TERM cleanup. It is not accepted as a three-visit baseline or changed by this helper refactor. Offline failed-view diagnosis is kept separately.
