# Performance climb current state — 2026-10-18

Status after bounded measurement windows and the failed Year diagnostic, released11:50:20 PDT. Targets are [versioned separately](climb-targets-v1.md); decisions and candidates are in [the ledger](climb-rounds.md). Baseline protocol/report is PR #66; optimization draft is [PR #72](https://github.com/luworks/one-app/pull/72). The selected shipping configuration remains Release -O; the later -Osize command-only experiment is not adopted. No overall3x/10x app-latency goal is met; component gains remain separately scoped.

## Context

| Track | Source / build / method / sample context |
| --- | --- |
| Package | Production baseline c42b88e / tooling fc683a7 versus integrated candidate44daf47; generic iPhoneOS arm64 Release, same inventory.py and deflate9 Payload/One.app proxy, command-only CODE_SIGNING_ALLOWED=NO, jobs2, n1 deterministic artifact per source. No archive/export/thinning. |
| App phases | Frozen fc683a7 production plus explicitly retained identical measurement instrumentation through d25b546 versus candidate f388d25; later35467e7 changes only a host test fixture; Debug SWIFT_OPTIMIZATION_LEVEL=-O, DEBUG fixture guards retained. Today-Performance iPhone18ProMax iOS27.0, UDID3243BEDB-4F6A-4807-AE9E-30115C528377; Mac14,10/16GiB/12cpu. Source tar/patch/manifests retained; not the recorder cwd HEAD. |
| Data / load | Versioned today-dataset.json hash e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7, relative local dates,09:41 pinned clock, simulator fakes/in-memory store; small feature dataset, not large user history. Quiet holder, no other build/UI/Swift; reference UI command-start load averages9.51/17.93/22.42 and candidate13.60/29.96/27.06 include prior host history. No concurrent heavy runner; exact process snapshots remain in command JSON. Separate-window thermal/cache noise is not eliminated. |
| Endpoints | Monotonic first explicit OneApp.init statement→bootstrap/nonzero foreground geometry/two displaylinks; resumes from scene active; navigation begins inside action. Excludes dyld/pre-init, actual touch, compositor presentation, animation completion and full usability. Same trace hash96100a8c3e80d0ca8f8b46fe216955a3e0d878afd16950ce90bbbc268bdd3c87. Three cycles/launches; n3 median/range, no p95. First cycles retained, no cache purge. |

## Measured state and required gaps

| Metric | Current / baseline | Proposed required ceiling | Confidence / gap / next action |
| --- | --- | --- | --- |
| Release app | 23,374,117→9,390,496 B, −59.83% | ≤11,453,317 B | High for this build method; raw ceiling met. Three dSYM UUIDs/verification/source lookups pass; no App Store or runtime claim. |
| Local compressed proxy | 7,621,937→4,557,045 B, −40.21% | ≤3,734,749 B | High for local ZIP;822,296 B above ceiling. Completed -Osize experiment still misses the ceiling; retain selected -O pending a material safe candidate. |
| Release main executable | 16,731,520→6,147,480 B (selected -O) | ≤8,198,445 B | Actual Mach-O logical bytes; target met, paired dSYM retained. |
| All Release Mach-O | 17,861,152→6,716,288 B (selected -O) | ≤8,751,964 B | Target met; app and two extensions counted once. |
| Experimental -Osize package | App8,656,543 B; ZIP4,349,508 B | Same original ceilings | Compared with selected -O:7.82% raw/4.55% ZIP smaller. Original ZIP reduction42.93%, still614,759 B above target. Compile/dSYM verified only; runtime tradeoff unknown, not adopted. |
| Audio resources | 5,280,736→2,445,686 B, −53.69% | ≤2,587,561 B | Container/native decode/determinism/signal checks pass; all8choices/28s kept. Perceptual/AlarmKit exact-rate behavior unverified; do not cut duration to reach package goal. |
| Init→layout opportunity | 1576.318→1512.878 ms; candidate range1451.389–2268.682; 1.042×; n3 each | ≤525.439 ms; stretch≤157.632 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| Resume→layout opportunity | 47.013→34.516 ms; candidate range31.470–38.943; 1.362×; n3 each | ≤15.671 ms; stretch≤4.701 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| Store stage | 73.906→68.198 ms; candidate range67.704–137.985; 1.084×; n3 each | ≤24.635 ms; stretch≤7.391 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| Bootstrap stage | 56.500→57.097 ms; candidate range56.338–66.690; 0.990×; n3 each | ≤18.833 ms; stretch≤5.650 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| calendar.month_to_calendar.year | 682.670→716.910 ms; candidate range632.837–815.528; 0.952×; n3 each | ≤227.557 ms; stretch≤68.267 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| calendar.week_to_calendar.month | 254.050→235.586 ms; candidate range235.332–318.974; 1.078×; n3 each | ≤84.683 ms; stretch≤25.405 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| calendar.week_to_tasks | 166.553→166.764 ms; candidate range166.567–617.435; 0.999×; n3 each | ≤55.518 ms; stretch≤16.655 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| calendar.year_to_calendar.week | 251.017→250.080 ms; candidate range250.025–382.178; 1.004×; n3 each | ≤83.672 ms; stretch≤25.102 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| clock_to_today | 112.705→100.709 ms; candidate range99.362–116.250; 1.119×; n3 each | ≤37.568 ms; stretch≤11.271 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| tasks_to_clock | 117.535→117.653 ms; candidate range116.535–316.956; 0.999×; n3 each | ≤39.178 ms; stretch≤11.753 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| today_to_calendar.week | 167.375→182.471 ms; candidate range167.606–368.449; 0.917×; n3 each | ≤55.792 ms; stretch≤16.737 ms | Methods pass,3x/10x unmet. Descriptive one-batch medians; proxy only, not demonstrated causal gain/regression. Raw reference ranges retained in baseline-app-samples.json. |
| Year scroll peak physical | 278.721→233.190 MiB median (−16.34%); candidate raw[275565.256,218663.624,244517.576] kB | ≤136.573 MiB | n3 app-scoped simulator observations, not51% lower; broad ranges and system variability limit causal attribution. Printed kB is primary; derived MiB assumes1000B/kB. |
| Year scroll absolute physical | 269.612→202.784 MiB median (−24.79%); candidate raw[206785.224,212634.312,236489.416] kB | ≤132.110 MiB | n3; goal unmet. Negative/positive delta samples do not establish leaks or retention. |
| Scroll duration | Median2.482785→2.482527s; candidate[2.516832,2.482527,2.482487]s | Frame/hitch target requires different metric | No hitch/FPS evidence; automation scroll duration is not rendering latency. |
| activity_read_deep | 1.205417→1.046355 ms; 1.152×, n5 each | ≤0.401806 ms; stretch≤0.120542 ms | Warm host SQLite,100k deterministic events,25 reads/sample,150rows/read; SwiftPM Release -O same owned cache/hardware/quiet.3x unmet; not app latency. |
| activity_read_newest | 0.353337→0.206385 ms; 1.712×, n5 each | ≤0.117779 ms; stretch≤0.035334 ms | Warm host SQLite,100k deterministic events,25 reads/sample,150rows/read; SwiftPM Release -O same owned cache/hardware/quiet.3x unmet; not app latency. |
| activity_read_search | 0.504175→0.357540 ms; 1.410×, n5 each | ≤0.168058 ms; stretch≤0.050417 ms | Warm host SQLite,100k deterministic events,25 reads/sample,150rows/read; SwiftPM Release -O same owned cache/hardware/quiet.3x unmet; not app latency. |
| Dense Year band component | 69.366993→0.954924 ms per12months;72.641×,5 alternating pairs | ≤23.122331 ms; stretch≤6.936699 ms | Complete ordered equality/checksum passed,52annual trips/366dates/2028LA;6iterations/batch. Component10x goal met; whole Year UI goal not met. |
| Host query / durable save / growth / usable endpoints | Matched warm query comparisons above; durable save, growth and true product endpoints unmeasured | baseline/3, stretch/10; memory49% baseline | Legacy host n1 is not a valid before/after denominator. No measured energy/battery result. |

## Priority and top-app gap

- **P0:** no measured P0 defect in this lane. Correctness and Add/Apply/Undo/data preservation remain hard acceptance gates.
- **P1:** retain conventional symbol processing (large verified raw-byte gain, low product risk with dSYM evidence; focused runtime still pending) and carefully measured audio candidate (large resource gain, moderate perceptual/format inference risk). Cost: small owned changes plus bounded integration checks.
- **P1:** retain the equivalent Year batching candidate for its measured dense-trip component gain (72.64×), with explicit whole-operation gap (Month→Year0.952× observed). Memory medians are lower but causal attribution remains uncertain; no broad UI gain claim. **P2:** Activity hydration saves about0.147ms/newest150-row page (1.712×); low code cost/risk after field/fallback checks, but little absolute user-latency value. Do not keep micro-optimizing already sub-millisecond reads while launch/Year remain slower.
- **P2:** completed -Osize experiment and startup Time Profiler diagnosis did not establish another accepted production change. Current store+bootstrap account for too little total launch time to explain a3x overall gain; avoid moving the endpoint or deferring required work. Remaining gaps need evidence before another production edit.

No competitor has been measured under an authorized identical protocol. Therefore no numeric top-app rank/gap is known. Apple platform guidance is the comparison, not invented competitor data: [responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [launch](https://developer.apple.com/videos/play/wwdc2019/423/), [hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app). Proposed actual-product budgets are usable content≤500ms, discrete response≤100ms, main-thread update work≤5ms, hitch rate≤5ms/s. These proxy samples cannot establish compliance with those endpoints. Relative3x/10x goals remain even when a phase is already below100ms.

## Evidence and next bounded batch

Canonical root: `/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/`. Release rawlog/inventory, read-only product+dSYM snapshot, frozen source tar/patch, reference optimized product, complete baseline-ui/ui.xcresult, app samples/context and QA archive are retained and indexed in the separate QA Activity SQLite.Reference3/3 and candidate3/3 UI methods passed. Host initial9methods:8passed, damagedfixture method failed2assertions; fixture-only repair35467e7 then failedmethod+readbenchmark2/2passed. The8other methods were not rerun, and no unrestricted/full-suite pass is claimed. Original failure is retained. Damage came from removing NOT NULL inside an index WHERE clause; no production decoder repair was needed. Shutdown/live no-heavy/no-booted verification completed11:10:14 and11:29:05; directly notified root/compat. No phone/signing/data deletion.

Next3actions: (1) obtain Year-specific attribution in a separately coordinated window using the corrected readiness budget; this failed window is not retried; (2) choose only a material app-owned candidate supported by that attribution, preserving required work and product behavior; (3) evaluate accepted changes on the final integrated main revision under a fresh explicitly labeled context, preserving the frozen comparisons. The -Osize experiment is complete but not adopted: extra ZIP saving4.55% is small and paired Release runtime acceptance is absent. The10sTimeProfiler capture and modeled export now resolve83images, actual app UUID/load mapping and6init/bootstrap/layout signposts. In the app-init→endpoint interval, main CPU sample weight is621ms; swift_conformsToProtocolMaybeInstantiateSuperclasses is214ms self(34.46% of sampled main CPU), unresolved54ms(8.70%). This is not wall time or a nonprofiled latency estimate. Ringer/AlarmScheduler is9ms inclusive; cancellation is not established as a dominant removable cost, and sampling cannot count cancellations. Profiled wall2396.860ms is excluded from timing comparisons. No safe material app-owned startup candidate was identified. The modeled union export completed3.25s in its granted slot and writes a new sibling directory; its completed analysis/reducer is retained separately. No profiler/exporter remains active. Two tooling findings from the single focused review are fixed: reverted candidates cannot silently leave tracked baseline files stale, and failed functional journeys cannot pass speed acceptance. The climb is in progress, not at a demonstrated plateau.

## Integration and local stopping boundaries

Parent reports integrated main91c1298 after these frozen comparison sources.
The numbers above do not validate that newer main; source manifests identify
exact tested code. No force-push/rebase, signing change or phone work was used.
The third window stayed within4minutes and never booted a simulator; selected
Release -O settings remain unchanged after the command-only experiment.

Package candidates have diminishing verified compressed value: extension symbol
processing saved87,316 ZIP bytes in the copy model; compiler -Osize adds207,537
ZIP bytes versus the selected source-built -O product. Neither closes the
remaining selected-package822,296-byte gap. Further removing choices, shortening
alarms, discarding city/locale data, bypassing Add/Apply or weakening reachability
checks is not justified by the target. This is not a claim of a global optimum;
startup/Year profiling is still being assessed before declaring a local plateau.

## Year diagnosis boundary

A separate, explicitly granted3-minute diagnostic window attempted only the
existing `testYearScrollMemory` without building. The helper timed out after30s
without observing the exact app PID; XCTest worker printed Runningtests near
that cap and noTestCase began. The runner was cancelled/cleaned in36.7s. No
profiler started, noYear trace exists, and noSwiftCompile marker occurred.
Cleanup DVT operation dumps do not prove a root cause or app regression.
All raw logs/partialxcresult are archived with failed status. The simulator was
shut down, noheavy/booted verified, and root/compat explicitly notified11:50:20.
Per the window's failure/no-retry instruction, no second attempt ran. The tool
now permits up to60s PID discovery while reserving40s active journey work plus
10s cleanup within the same hard wall limit; this repair is static-only,
not verified by another runtime attempt.

The safe candidate set has narrowed, but this is **an evidence boundary, not a
proven local/global optimum**: the remaining Year initial-scroll hypothesis
still lacks attribution. No unmeasured rendering rewrite or discarded product
behavior is shipped to claim the51%/3×/10× goals. Next concrete work is the
bounded Year diagnosis with the corrected readiness budget, followed only by
an evidence-backed candidate; final main integration has its own validation
context. The current measured goals remain honestly unmet where shown above.
