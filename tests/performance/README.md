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
file; `--update` without that list overlays changed candidate files, preserving
unchanged file timestamps for incremental build reuse. Build source is mutable
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
