# Performance tools

Protocol: [`docs/performance/protocol.md`](../../docs/performance/protocol.md).
Results and targets: [`baseline-2026-10-18.md`](../../docs/performance/baseline-2026-10-18.md).

- `inventory.py <app> --output <json>` reads actual bundle bytes, nested extensions,
  Mach-O metadata, exact duplicate hashes and a ZIP deflate-9 proxy. It does not
  infer App Store size or asset reachability.
- `record_command.py --label <label> -- <command...>` stores command output and
  host context under canonical primary `tests/results/runs/<session>/`, recording
  the action in the separate QA journal. Default session is this baseline; pass
  `--session` for a later run. It does not archive still-active files.
- `launch_probe.py --simulator <udid> --output <durable-directory>` requires the
  booted `Today-Performance` simulator and an installed Debug app. It performs one
  excluded warmup and three process relaunches using the versioned dataset. It
  terminates only Today's app on that simulator. No cold cache/reboot is implied.
  The output directory must be new; repeated runs cannot overwrite prior launch evidence.
- `memory_sample.py --simulator <udid> --output <csv> -- <command...>` samples
  only the exact simulator app executable's RSS every 0.5 seconds while the
  command runs; records UTC and PID for alignment with test logs. It does not
  measure physical footprint, GPU allocation, battery or test-runner memory.
- `summarize.py <ui.log> --output <json>` retains all explicit `PERF_SAMPLE`
  values and emits n, median and range; leaves p95 unknown.
- UI instrumentation: `ios/OneUITests/PerformanceBaselineTests.swift`; use the
  existing E2E runner for the four named methods, never the full suite for this
  baseline. These additions do not change production app behavior.
- Store benchmark: existing `ActivityStoreTests.testBenchmarkLarge`, enabled by
  `ACTIVITY_BENCH_ROWS=100000`. The versioned generator is in
  `ios/One/ActivityExport.swift`; no required input is generated into `/tmp`.

Tool validation: `python3 -m unittest discover -s tests/performance -v`.
Raw JSON contains byte counts, not rounded MiB; report MiB as bytes / 1048576.
After every producer exits, import/archive through `tests/qa/journal.py` to index
paths/hashes, including complete xcresult bundles. Never prune this evidence in
worktree cleanup.

## Measured optimization climb

Targets: [`climb-targets-v1.md`](../../docs/performance/climb-targets-v1.md),
machine-readable `targets-v1.json`; decisions: `climb-rounds.md` beside that report.
Pass `--session performance-climb-20261018` to the command recorder for this work.

`materialize.py --revision <measurement-sha> --source <new-build-source>
--evidence <new-evidence> --instrumentation <explicit-file> ...` retains the frozen
`fc683a7` source tar, applies only listed instrumentation files, and records their
hashes. This prevents concurrently committed optimization lanes leaking into the
baseline. `--update --instrumentation <file>` adds only another portable measurement
file; `--update` without that list audits every tracked target-revision file
against current source bytes, including files restored to baseline after an earlier
candidate. Equal bytes retain their timestamps for incremental build reuse.
A `.SOURCE_NAME.materialize.json` provenance sidecar beside the source records
managed paths; baseline or previously managed deletions are rejected before any
update writes. Existing sources without a sidecar receive the full target audit;
unrecorded historical additions cannot be identified and remain untracked.
Untracked files and build caches are not traversed or cleaned; source symlinks
and unsupported tracked members are rejected. Build source is mutable
cache; archives/patches/manifests and copied completed products are immutable
evidence. No source deletion or branch checkout is performed.

`compare_app.py` takes before/after raw UI logs and context JSONs. Required equal
context keys are configuration, optimization, simulator ID/runtime, fixture hash,
instrumentation hash and endpoint version. Duplicate app/test stdout records are
deduplicated by monotonic interval identity; different test methods remain separate
cohorts. n<3 cannot pass the 3x/10x gate, and p95 remains unknown. The reported app
intervals are layout/display-link proxies, not compositor presentation, physical
touch or full usability. Shipping Release size, optimized Debug phase timing and
native host component benchmarks are three separate tracks.

`with_owned_runner.py --simulator-name Today-Performance --derived-data <owned-DD>
-- <command>` uses the E2E runner's named simulator/cache file locks for direct
`xcodebuild` of the frozen source project. Direct builds are required to select
that project and identical optimized Debug flags. The parent still obtains the
global quiet-window handoff; these local locks do not grant a global slot.
Capture output with `record_command.py`, and index the closed complete xcresult
through the QA journal after the producer exits.

`extract_xct_metrics.py <raw-ui-log> --output <new.json> [--include-mib]`
retains each XCTest metric's ID, printed unit and raw values, with method-attempt
functional gates, median/range and no percentile estimate. Peak physical,
physical delta, absolute physical and scroll duration remain separate. Optional
MiB conversion explicitly assumes decimal kB; original values remain primary.

`profile_startup.py --simulator <owned-ID> --fixture <durable-json> --output <new-dir>`
requires the explicit global handoff, visible booted Today-Performance and a
stopped installed target. It never boots/builds/installs. It attempts one bounded
10s Time Profiler capture plus signposts, retains raw errors, and exports only
TOC on success. Total script budget is60s including cleanup. Verify installed
UUID against the intended optimized artifact before calling; inspect actual PID,
samples/schema/symbols before treating the capture as useful. Profiled durations
are excluded from the unprofiled before/after comparison. Parent indexes the
closed trace/export directory via the QA journal; unsupported capture is a
recorded limitation, not an invitation to change profiling/privacy settings.

Current metric table and gaps: [climb-current-state.md](../../docs/performance/climb-current-state.md).
The app comparator requires each corresponding functional method to pass;
failed/incomplete logs retain diagnostic ratios but cannot pass the3x/10x gates.
