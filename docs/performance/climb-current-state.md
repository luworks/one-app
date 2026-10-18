# Performance climb current state — 2026-10-18

Status after the first bounded measurement window, 11:02–11:10 PDT. Targets are [versioned separately](climb-targets-v1.md); decisions and candidates are in [the ledger](climb-rounds.md). Baseline protocol/report is PR #66; optimization draft is [PR #72](https://github.com/luworks/one-app/pull/72). No speed gain is accepted yet.

## Context

| Track | Source / build / method / sample context |
| --- | --- |
| Package | Production baseline c42b88e / tooling fc683a7 versus integrated candidate44daf47; generic iPhoneOS arm64 Release, same inventory.py and deflate9 Payload/One.app proxy, command-only CODE_SIGNING_ALLOWED=NO, jobs2, n1 deterministic artifact per source. No archive/export/thinning. |
| App phases | Frozen fc683a7 production plus explicitly retained identical measurement instrumentation through d25b546; Debug SWIFT_OPTIMIZATION_LEVEL=-O, DEBUG fixture guards retained. Today-Performance iPhone18ProMax iOS27.0, UDID3243BEDB-4F6A-4807-AE9E-30115C528377; Mac14,10/16GiB/12cpu. Source tar/patch/manifests retained; not the recorder cwd HEAD. |
| Data / load | Versioned today-dataset.json hash e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7, relative local dates,09:41 pinned clock, simulator fakes/in-memory store; small feature dataset, not large user history. Quiet holder, no other build/UI/Swift; command-start load averages9.51/17.93/22.42 include prior host history. |
| Endpoints | Monotonic first explicit OneApp.init statement→bootstrap/nonzero foreground geometry/two displaylinks; resumes from scene active; navigation begins inside action. Excludes dyld/pre-init, actual touch, compositor presentation, animation completion and full usability. Same trace hash96100a8c3e80d0ca8f8b46fe216955a3e0d878afd16950ce90bbbc268bdd3c87. Three cycles/launches; n3 median/range, no p95. First cycles retained, no cache purge. |

## Measured state and required gaps

| Metric | Current / baseline | Proposed required ceiling | Confidence / gap / next action |
| --- | --- | --- | --- |
| Release app | 23,374,117→9,390,496 B, −59.83% | ≤11,453,317 B | High for this build method; raw ceiling met. Three dSYM UUIDs/verification/source lookups pass; no App Store or runtime claim. |
| Local compressed proxy | 7,621,937→4,557,045 B, −40.21% | ≤3,734,749 B | High for local ZIP;822,296 B above ceiling. Next controlled -Osize experiment, unchanged resources/endpoint. |
| Audio resources | 5,280,736→2,445,686 B, −53.69% | ≤2,587,561 B | Container/native decode/determinism/signal checks pass; all8choices/28s kept. Perceptual/AlarmKit exact-rate behavior unverified; do not cut duration to reach package goal. |
| Init→layout opportunity | Reference median1576.318 ms, range1562.401–2299.459, n3 | ≤525.439 ms; stretch≤157.632 ms | Reference method passed; candidate pending. Proxy only; no3x/10x result. |
| Resume→layout opportunity | Reference median47.013 ms, range37.816–73.626, n3 | ≤15.671 ms; stretch≤4.701 ms | Reference method passed; candidate pending. Proxy only; no3x/10x result. |
| Store stage | Reference median73.906 ms, range69.887–139.081, n3 | ≤24.635 ms; stretch≤7.391 ms | Reference method passed; candidate pending. Proxy only; no3x/10x result. |
| Bootstrap stage | Reference median56.500 ms, range55.848–69.336, n3 | ≤18.833 ms; stretch≤5.650 ms | Reference method passed; candidate pending. Proxy only; no3x/10x result. |
| calendar.month_to_calendar.year | Reference median682.670 ms, range682.625–815.636, n3 | ≤227.557 ms; stretch≤68.267 ms | Destination/retained-state assertions passed; candidate pending. |
| calendar.week_to_calendar.month | Reference median254.050 ms, range237.113–364.146, n3 | ≤84.683 ms; stretch≤25.405 ms | Destination/retained-state assertions passed; candidate pending. |
| calendar.week_to_tasks | Reference median166.553 ms, range166.445–650.764, n3 | ≤55.518 ms; stretch≤16.655 ms | Destination/retained-state assertions passed; candidate pending. |
| calendar.year_to_calendar.week | Reference median251.017 ms, range250.441–267.599, n3 | ≤83.672 ms; stretch≤25.102 ms | Destination/retained-state assertions passed; candidate pending. |
| clock_to_today | Reference median112.705 ms, range99.353–116.765, n3 | ≤37.568 ms; stretch≤11.271 ms | Destination/retained-state assertions passed; candidate pending. |
| tasks_to_clock | Reference median117.535 ms, range116.136–299.237, n3 | ≤39.178 ms; stretch≤11.753 ms | Destination/retained-state assertions passed; candidate pending. |
| today_to_calendar.week | Reference median167.375 ms, range165.987–434.741, n3 | ≤55.792 ms; stretch≤16.737 ms | Destination/retained-state assertions passed; candidate pending. |
| Year scroll peak physical | Reference raw[303073.968,292260.528,283167.408] kB; median278.721 MiB | ≤136.573 MiB (49% of matched reference) | XCTMemoryMetric app scoped, n3; simulator proxy. Different from historical unoptimized Debug denominator; candidate pending. |
| Year scroll absolute physical | Raw[284674.736,282708.656,226937.520] kB; median269.612 MiB | ≤132.110 MiB | Physical delta includes negative values and is not retention. Need same protocol candidate, not RSS substitution. |
| Scroll duration | [2.483321,2.482554,2.482785] s | Frame/hitch target requires different metric | No hitch/FPS evidence; automation scroll duration is not rendering latency. |
| Host query / durable save / growth / usable endpoints | New matched component comparisons and true product endpoints pending | baseline/3, stretch/10; memory49% baseline | Legacy host n1 is not a valid before/after denominator. No measured energy/battery result. |

## Priority and top-app gap

- **P0:** no measured P0 defect in this lane. Correctness and Add/Apply/Undo/data preservation remain hard acceptance gates.
- **P1:** retain conventional symbol processing (large verified raw-byte gain, low product risk with dSYM evidence; focused runtime still pending) and carefully measured audio candidate (large resource gain, moderate perceptual/format inference risk). Cost: small owned changes plus bounded integration checks.
- **P1:** run matched Year/component/UI candidate comparison. Once-per-month materialization has a clear repeated-work mechanism; measurable user benefit and memory impact are not established. Activity hydration is a smaller component opportunity, not a promised overall3x gain.
- **P2:** controlled -Osize experiment and startup Time Profiler diagnosis. Current store+bootstrap account for too little total launch time to explain a3x overall gain; avoid moving the endpoint or deferring required work. Remaining gaps need evidence before another production edit.

No competitor has been measured under an authorized identical protocol. Therefore no numeric top-app rank/gap is known. Apple platform guidance is the comparison, not invented competitor data: [responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [launch](https://developer.apple.com/videos/play/wwdc2019/423/), [hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app). Proposed actual-product budgets are usable content≤500ms, discrete response≤100ms, main-thread update work≤5ms, hitch rate≤5ms/s. These proxy samples cannot establish compliance with those endpoints. Relative3x/10x goals remain even when a phase is already below100ms.

## Evidence and next bounded batch

Canonical root: `/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/`. Release rawlog/inventory, read-only product+dSYM snapshot, frozen source tar/patch, reference optimized product, complete baseline-ui/ui.xcresult, app samples/context and QA archive are retained and indexed in the separate QA Activity SQLite.3/3methods passed; no full suite/phone/signing change/data deletion. Shutdown and live no-heavy/no-booted verification completed11:10:14; directly notified root/compat/Recurring.

Next3actions: (1) same-DD incremental candidate3-method comparison plus focused logic/component checks after coordinator handoff; (2) separate command-only -Osize package experiment with source/resources frozen, dSYM verification and runtime tradeoff gates; (3) profile dominant startup spans before a narrow candidate, then update acceptance/remaining gaps. Two tooling findings from the single focused review are fixed: reverted candidates cannot silently leave tracked baseline files stale, and failed functional journeys cannot pass speed acceptance. The climb is in progress, not at a demonstrated plateau.
