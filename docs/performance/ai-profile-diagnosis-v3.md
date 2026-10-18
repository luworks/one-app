# AI first-PID profile diagnosis v3

## Decision

The first profiled conversation turn is covered and symbolized. Its response-probe arm to first display-link callback spans **145.692 ms wall time**, containing **89 ms main-thread CPU sample weight**. This is evidence of substantial main-thread work in the gap; it does not explain all wall time or establish a specific wait, scheduler cause, animation delay, or safely removable app operation. No production candidate is justified by this capture.

This is **one profiled turn/PID**, not the n3 speed comparison. Preserve the accepted PR80 comparison (626.149→309.332 ms, 2.024x) separately. The profiled turn's 285.658 ms full endpoint is diagnosis only, not a new acceptance result or a change to the ≥3x target.

## Actual execution and inputs

- Instrumented source `d74593e`, existing Debug `-O` Products; simulator Today-Performance `3243BEDB-4F6A-4807-AE9E-30115C528377`, iPhone 18 Pro Max, iOS 27.0. Same Hello/fresh-process/in-memory fixture method `AIResponsePerformanceTests/testConversationFreshLaunchN3`.
- Parent ran the bounded helper once with `test-without-building`, no compilation or manual install. Actual runner/profiler exit 0; orchestration elapsed 99.273 s. Only the first app PID **1196**, main TID **14132867** (`0xd7a683`), was attached. First token `552DC2BC-42FB-4D29-969D-F97A94D24CEF`. Later method repetitions have different app processes and are excluded from this profile.
- Actual trace duration **13.105415 s**, ending **Target app exited**, not the requested 30 s time limit. Parent shut down the device and closed its panel after capture.
- Modeled export: **32,432,818 bytes**, SHA256 `d3407336e93874cfc6385211a868932ed5b5b594172b631f7a17a94c45d3a5ff`. 69,836 rows across the exported tables; **96,085 unique IDs / 939,531 references / 0 unresolved references or cycles**. 6,764 modeled CPU rows; each actual `weight` is **1,000,000 ns (1.00 ms)**. 146 modeled binary images include their actual UUID/load addresses; no guessed load bias or external symbolication.
- TOC `time-profile` has `record-waiting-threads=0`; raw sampling has `all-thread-states=NO`. A sparse sample interval cannot classify blocking versus scheduling.

Canonical primary results root: `tests/results/runs/performance-pages-ai-20261018/`.

| Evidence | Directory/file under that root |
|---|---|
| Original raw recording, command, PID/container/hash checks, test output and TOC | `ai-profile-first-pid-v1/` |
| Actual closed modeled export and export status | `ai-profile-first-pid-v1-export/modeled.xml` |
| Reproducible reducer, input hashes, exact intervals, all top-10 tables/stacks | `ai-profile-first-pid-v1-analysis/{reduce_profile.py,analysis.json,reduction.log}` |

## Clock alignment and coverage

The actual `com.luworks.one` `PerformanceSample` signpost for `page.ai` is at trace **3,777,181,875 ns**, with embedded `end_ns=217904120838208`. Their difference is **217900343656333 ns** (app uptime minus trace-relative time). Apply this measured difference to the first turn's app-side stage timestamps from the raw UI stdout.

An independent earlier `PerformanceEndpoint(begin.page.ai)` signpost gives difference **217900343679750 ns**, agreeing within **23,417 ns (0.023417 ms)**. Both signposts are emitted after their stored app timestamps: this is an observed alignment with small anchor disagreement, not a guarantee of zero timestamp/emission error. No start-date/wall-clock or guessed process-start offset is used.

The selected arm/callback interval is **10.792640875–10.938333083 s** on the actual trace; ready/layout is **10.746021542–10.957470000 s**. Both lie inside the 0–13.105415 s recording and contain main-thread modeled samples. `analysis.json` retains the exact endpoint/anchor timestamps, first and last selected samples and input hashes. Samples at interval boundaries have ordinary sampling/anchor uncertainty.

| First-turn interval | Wall ms | Main CPU sample weight ms | Unresolved leaf weight |
|---|---:|---:|---:|
| `send_to_response_layout` | 285.657625 | 165 | 9 ms (5.45%) |
| `ready_to_response_layout` | 211.448458 | 125 | 8 ms (6.40%) |
| `ready_to_arm` | 46.619333 | 26 | 1 ms (3.85%) |
| `arm_to_first_callback` | 145.692208 | 89 | 6 ms (6.74%) |
| `first_callback_to_endpoint` | 19.136917 | 10 | 1 ms (10.00%) |
| `persist` | 43.008583 | 22 | 1 ms (4.55%) |

CPU sample weight is a statistical estimate, not exact measured thread runtime. Do not subtract it from wall time and name the remainder a wait. Inclusive symbols overlap and must not be summed. The arm→callback interval has **0 missing-backtrace weight** and **6 ms unresolved leaf weight (6.74%)**; unresolved frames elsewhere in a stack are separately retained, not treated as resolved merely because the leaf is named.

## Main-thread arm→callback attribution

Top 10 self symbols (sampled leaf; no owned One leaf appears in this interval):

| Image | Symbol | CPU sample weight (ms) |
|---|---|---:|
| libswiftCore.dylib | `swift_conformsToProtocolMaybeInstantiateSuperclasses(swift::TargetMetadata<swift::InProcess> const*, swift::TargetProtocolDescriptor<swift::InProcess> const*, bool)` | 24.0 |
| libsystem_pthread.dylib | `pthread_getspecific` | 3.0 |
| AttributeGraph | `AG::Graph::propagate_dirty(AG::AttributeID)` | 2.0 |
| libobjc.A.dylib | `getMethodNoSuper_nolock(objc_class*, objc_selector*)` | 2.0 |
| libsystem_pthread.dylib | `pthread_setspecific` | 2.0 |
| libobjc.A.dylib | `objc_claimAutoreleasedReturnValue` | 2.0 |
| libswiftCore.dylib | `swift_release` | 1.0 |
| libswiftCore.dylib | `Hasher.init(_seed:)` | 1.0 |
| UIKitCore | `0x1c50591d4` | 1.0 |
| libobjc.A.dylib | `objc_release_x19` | 1.0 |

Top 10 inclusive symbols, unfiltered (the shared app/run-loop ancestry dominates; this is not an optimization ranking):

| Image | Symbol | CPU sample weight (ms) |
|---|---|---:|
| One | `main` | 67.0 |
| One | `static OneApp.$main()` | 67.0 |
| CoreFoundation | `__CFRunLoopRun` | 67.0 |
| dyld_sim | `start_sim` | 67.0 |
| GraphicsServices | `GSEventRunModal` | 67.0 |
| CoreFoundation | `_CFRunLoopRunSpecificWithOptions` | 67.0 |
| SwiftUI | `closure #1 in KitRendererCommon(_:)` | 67.0 |
| UIKitCore | `UIApplicationMain` | 67.0 |
| dyld | `start` | 67.0 |
| SwiftUI | `runApp<A>(_:)` | 67.0 |

Top 10 owned inclusive symbols, likewise retaining entry points and generic view constructors:

| Image | Symbol | CPU sample weight (ms) |
|---|---|---:|
| One | `main` | 67.0 |
| One | `static OneApp.$main()` | 67.0 |
| One | `specialized _VariadicView.Tree.init(_:content:)` | 7.0 |
| One | `specialized VStack.init(alignment:spacing:content:)` | 6.0 |
| One | `specialized closure #1 in VStack.init(alignment:spacing:content:)` | 6.0 |
| One | `closure #1 in Sidebar.body.getter` | 4.0 |
| One | `Sidebar.body.getter` | 4.0 |
| One | `static ConversationBucket.of(_:now:calendar:)` | 4.0 |
| One | `specialized static ConversationBucket.of(_:now:calendar:)` | 4.0 |
| One | `specialized HStack.init(alignment:spacing:content:)` | 3.0 |

Additional explicitly **overlapping stack-context** weights clarify the named framework work:

| At least one matching frame in a sample | Weight ms |
|---|---:|
| `AttributeGraph_any_frame` | 40 |
| `SwiftData_or_SwiftData_SwiftUI_any_frame` | 27 |
| `Conformance_leaf` | 24 |
| `ListBatchUpdates_any_frame` | 16 |
| `Sidebar_any_owned_frame` | 4 |
| `AskView_any_owned_frame` | 1 |

The complete top-10 leaf→root stacks are retained in `analysis.json`, not collapsed to raw addresses. Examples include SwiftUI ListBatchUpdates/UICollectionViewListCoordinator invoking Swift dynamic casts and conformance checks; SwiftData/_SwiftData_SwiftUI query work; AttributeGraph transaction propagation; and 4 ms with owned Sidebar/ConversationHistory grouping frames. These contexts overlap: 24 ms conformance is not additional to the framework-context weights.

The earlier ready→arm interval contains 22 ms inclusive `AskView.persist()` CPU sample weight, including 19 ms self conformance checking, inside 43.009 ms measured persist wall time. This does not identify a redundant save. The current method deliberately creates its first chat and must retain reply/history correctness. Moving or skipping persistence to shift work outside the endpoint would require a separate behavior design and acceptance, and is not justified here.

## Next action and rejection boundary

Keep production behavior unchanged. This capture establishes that the dominant callback gap is not solely an unobserved geometric rejection: first-callback geometry was eligible, and named SwiftUI/SwiftData/runtime work consumes material sample weight before the callback. It does **not** establish that all framework work is caused by the Ask response, that the hidden sidebar's List work dominates, or that disabling scrolling/animation would safely recover ≥100 ms.

A later source experiment should proceed only after an app-owned redundant invalidation/query/rebuild is identified and its removable cost is supported. Sidebar's 4 ms inclusive grouping is too small to justify changing its lifetime for the current ≥3x goal. No endpoint change, synchronous-save deferral, broad view-lifetime rewrite, additional profiler retry, or CPU-to-wall speed claim is proposed from this one trace. This is an attribution limit, not a claim that the optimization has reached a plateau.

Analysis validation: parsed actual XML, resolved every reference chain, asserted PID/main thread and observed units, checked both actual clock anchors and interval containment, and reproduced all tables with the retained standard-library reducer. No device/export/profiler/build/Swift/UI operations ran during analysis.
