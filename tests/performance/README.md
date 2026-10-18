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
