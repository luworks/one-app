# Shared-root resource baseline v4

Production reference: `aa7c7c89b74d7107c618b18fa2d6fb6f6011625c`, including completion writeback PR89 and page resources PR87. Frozen measurement source: `43899f8a8477ae749a6112b044791690005d580c`. This extends resource coverage to the unchanged seven-transition/kept-state journey. It is a new baseline, not a measured optimization or speed comparison with earlier cohorts.

## Context and method

Reuse [resource protocol v3](page-resources-protocol-v3.md): optimized Debug `-O`, Xcode27.1, Today-Performance iPhone18ProMax/iOS27.0 simulator, retained derived-optimized, jobs2/parallelNO. Canonical today-dataset.json SHA256 `e91a99f1a16eabdad31b2f8c7e3bff7bf20f058713945964f8fdc684a9ba31c7`, in-memory store/sync off/09:41. The original action→geometry+two-display-link endpoints and complete reminder-list/Calendar-mode restoration assertions stay unchanged. A resource-only wrapper waits for the same-seq/generation fixed1s post-layout window, sampled about100ms on a serial utility queue. Three ordered cycles share one process; they are not three independent cold samples. These endpoints are not presented frames, completed animations or full usable-content endpoints.

Resource payload schema1 remains compatible. Existing page visits retain page-route counting. Root transitions formerly had no page visit number; resource-only counters label completed layout operations1/2/3 with `visit_basis=layout_operation_name`. No latency fields/timestamps change. The reducer never pools visit bases or different operation histories. The first Today launch is a separate one-off window. All sampler code remains DEBUG-only with a disabled Release stub.

## Actual results

One incremental build and `PerformanceClimbTests/testRootNavigationResourceWindows` passed118.084s, producer exit0. One PID69475,22 valid raw windows (21 grouped +1 launch),309 valid in-window samples; largest observed sample gap111.109ms. Pre-run host load averages7.54/10.88/15.71; exact process/hardware snapshot is retained, and no competing heavy executable or booted simulator was present. All seven groups have visits1/2/3, at least5 valid post-layout samples per window, no VM errors, and a passed functional method. Seven reducer tests and one focused source review passed. No equivalent UI repeat was run. The simulator was shut down and the Device panel closed after the batch.

Values below are whole-app `TASK_VM_INFO.phys_footprint` while a state is visible. They are not exclusive page allocation, true peaks, RSS or leak evidence. Confidence is moderate for these simulator windows and low for device extrapolation/target feasibility. No p95 is estimated. Goals are the owner's aspirational51% reduction from visit3; they are not verified savings or Apple mandates.

| Operation → state | Visit1 /2 /3 window medians MiB | Visit3 sampled operation max MiB | Visit1→3 MiB | Proposed visit3 goal MiB | Remaining MiB |
|---|---|---:|---:|---:|---:|
|calendar.month_to_calendar.year|255.97 / 248.75 / 250.13|251.72|-5.84|122.56|127.57|
|calendar.week_to_calendar.month|126.81 / 130.46 / 136.86|137.71|+10.05|67.06|69.80|
|calendar.week_to_tasks|122.22 / 122.24 / 122.25|122.39|+0.03|59.90|62.35|
|calendar.year_to_calendar.week|256.66 / 243.78 / 246.91|248.03|-9.75|120.99|125.92|
|clock_to_today|100.69 / 102.97 / 103.67|103.82|+2.98|50.80|52.87|
|tasks_to_clock|102.02 / 103.96 / 104.96|105.10|+2.94|51.43|53.53|
|today_to_calendar.week|104.03 / 118.36 / 112.77|113.63|+8.73|55.26|57.51|

The first launch window median was62.25MiB (one sample window, not n3). Returning Today medians100.69→102.97→103.67MiB show +2.98MiB from cycle1→3. They cannot be compared as equivalent cold/returning states, and neither this increase nor the larger initial difference proves a leak. Week immediately after Year remains246.91MiB on visit3, whereas Week entered from Today is112.77MiB: operation history matters, so these two Week groups must not be pooled. Subsequent Reminders/Clock/Today windows fall toward122.25/104.96/103.67MiB. This is compatible with transient/lifetime effects but supplies no allocation-owner attribution.

## Priorities and decision

- P1: Year and immediately following Week have the largest fixed-window footprints (~250MiB), but Year visit1→3 falls5.84MiB and following Week falls9.75MiB. Next useful work is source/allocation-lifetime attribution of the Year transition, keeping every day action, mark, VoiceOver description and retained mode. No production teardown/cache eviction is justified by these windows alone. Potential benefit is unknown until an app-owned removable allocation is identified; risk is state/render correctness. The historical trip-band component optimization is not accepted as a current memory candidate: this fixture has one eligible trip, and it cannot explain a51% whole-app target without attribution.
- P1: Settings/Activity and Search/reminder resource groups are now accepted in [secondary v4](secondary-resources-v4.md), each under its own exact source identity. [The prior Settings failure](settings-resource-failure-v3.md) produced seven diagnostic windows, not accepted n3. The failure-only probe established a closed-sidebar setup race; one bounded closure predicate repaired the test setup, preserving the original actions/assertions/endpoints. Cost is one focused incremental build plus affected methods, not repeating passed Health/Clock/Root methods.
- P2: Native Year hitch metrics remain missing in [v3](page-resources-results-v3.md); no FPS, real-touch, energy or physical-device claims. Apple's linked platform guidance is a target reference, not a same-protocol measured top-app result. Competitor comparison and actual thinned App Store download/install size remain unavailable.

No memory reduction is claimed by this measurement-only change. Existing accepted Release logical-size reduction60.14% and AI full-response layout gain2.024x remain separate results; the AI3x full-layout target and local ZIP51% target remain unmet. This is not a global performance plateau.

## Reproduction and durable evidence

Canonical primary root: `tests/results/runs/performance-pages-ai-20261018/`. Exact `root-resources-v4-command.json`; raw `root-resources-v4-474615e8.log` and matching context JSON (source/build/host hardware/load/process snapshot and start/end); `staged-source-root-resources-v4/manifest.json`; closed `root-resources-v4/ui.xcresult`; `root-resources-v4-summary.json`; preserved `root-resources-v4-products/{One.app,OneUITests.xctest}`. Build command uses the same mutable project path and retained derived-optimized as v3. QA journal separately indexes/archives the closed bundle, Products and exact artifacts. Do not infer current production source from the immutable materialization cache-anchor b1fc12b; the manifest's revision is the compiled source.
