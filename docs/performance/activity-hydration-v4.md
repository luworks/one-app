# Activity row hydration climb v4

## Decision

Adopt the narrow persisted-row initializer: skip creating a UUID and computing current calendar fields that the read path immediately overwrites. SQL, indexes, migrations, transactions, rollback and lazy content/snapshot loading are unchanged. Current matched host measurements show1.80x newest-page,1.19x deep-page and1.45x search speedups, saving only0.16–0.20ms per150-row read. This is a P2 component improvement; it does not meet3x or establish a page, AI, startup or simulator speedup. Do not prioritize further micro-optimizations here ahead of larger user-visible costs without new attribution.

Production reference is aa7c7c89, whose Activity sources also match merged d45d1d3. Frozen reference `a907cd15ceefefa11ecba98732df3fdeb0a2e181` adds only the portable benchmark/host runner on top of the measurement baseline. Frozen candidate `e21026c717679520e4c2b5769cbf9a7f1676d10e` adds the two production files and focused hydration/fixture tests. Old PR72 measurements are historical; they are not used as this denominator.

## Context and endpoints

Both sides: same assigned checkout `ios/` path, retained `performance-climb-20261018/derived-host`, Swift Package Release (actual PIF `SWIFT_OPTIMIZATION_LEVEL=-Owholemodule`), jobs2, Apple Swift6.4/arm64-apple-macosx26.0 host, Mac14,10/16GiB/12CPU. No simulator or phone participates. Pre-run load averages reference3.86/10.91/14.03, candidate3.27/8.46/12.66; raw hardware/process snapshots retained. A shared Swift mutex and load<=30 check gate each serial invocation after actual heavy-holder release. First reference compile37.30s is excluded from read timings; the existing scratch path was reused, not a new cold cache.

`ActivityReadPerformanceTests.swift` contains the versioned deterministic100,000-event generator. Rows are inserted1000/batch before timing; fixed UTC timestamps, deterministic IDs and bilingual title distribution. Cursor discovery and one warm read/case occur before timing. Cases use existing `page` API: newest changes/You, deep keyset page after10,000 matching rows, and bilingual text search. Each returns150 rows and asserts the count. Each of five recorded samples averages25 consecutive reads using monotonic uptime; these are n5 batch averages, not125 independent samples. SQLite/OS caches are warm. No cold I/O, persistence latency, tail/p95, full export, SwiftData or EventKit latency claim.

| Component ms/read | Reference median [range] | Candidate median [range] | Ratio | Absolute saving ms | Proposed3x goal ms | Remaining ms |
|---|---:|---:|---:|---:|---:|---:|
|activity_read_deep|1.242247 [1.236005, 1.312015]|1.042217 [1.030020, 1.269282]|1.192x|0.200030|0.414082|0.628134|
|activity_read_newest|0.376013 [0.362683, 0.383788]|0.209312 [0.206348, 0.216005]|1.796x|0.166702|0.125338|0.083974|
|activity_read_search|0.522465 [0.516057, 0.549845]|0.359702 [0.345022, 0.360677]|1.452x|0.162763|0.174155|0.185547|

Newest elapsed time falls44.33%, deep16.10%, search31.15%; none meets the owner's>50%/3x aspiration. Stretch10x goals remain reference/10, not candidate/10. Confidence is moderate for newest/search under this small host workload: observed ranges are disjoint. Deep's ranges overlap and one candidate sample is slower than the reference median, so its smaller median gain is less certain. No confidence interval or top-app numeric comparison is fabricated. Relative factors alone overstate user value when absolute savings are fractions of a millisecond.

## Correctness and scope

Candidate `ActivityStoreTests`:25 passed,1 skipped,0 failures (26 executed). The existing opt-in large benchmark is the skip; its quick5k default benchmark also ran. Three added behavior tests exercise full persisted field/default identity restoration, SQL NULL/invalid-tier/coercion equivalence, and unchanged lazy content/snapshot access. The malformed test-database fixture now removes only column NOT NULL constraints, preserving the partial-index `WHERE subject_ref IS NOT NULL` predicate and complete migration/version setup. This repairs test input, not an app database or schema.

Reference and candidate100k read methods both passed/exit0. Four meaningful comparator tests passed (duplicate/conflict validation, failed/incomplete gates, sample/context compatibility, finite values and batch units). One focused source review found no material issues. No broad passing-suite repeats were run. These are macOS logic/SQLite evidence; no candidate iOS Xcode build, simulator journey, physical-device test or model generation is claimed. The modified production logic has no UI copy/navigation change, and app-side integration claims remain limited accordingly.

## Reuse

From the assigned `ios/` directory, after the real heavy-holder handoff:

```sh
python3 ../tests/performance/with_host_runner.py -- test -c release --jobs 2 \
  --scratch-path /Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/derived-host \
  --filter ActivityStoreTests
ACTIVITY_READ_BENCH=1 ACTIVITY_READ_SAMPLES=5 \
  python3 ../tests/performance/with_host_runner.py -- test -c release --jobs 2 \
  --scratch-path /Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/derived-host \
  --filter ActivityReadPerformanceTests/testWarmPageReads
```

Use `record_command.py` around each exact invocation and compare identically configured reference/candidate with `compare_component_reads.py`. Its JSON preserves raw n5 values, method/command acceptance gates, missing cases and context; tiny-sample p95 is absent. `with_host_runner.py` versions the earlier temporary wrapper's shared mutex/load contract, uses nonblocking fail-closed checks, and runs only jobs2 Swift tests. Mutex availability does not replace real resource ownership. Temporary generated benchmark databases are isolated test data; reusable generator/fixtures/tools are versioned.

## Evidence and next action

Primary `tests/results/runs/performance-activity-hydration-20261018/`: `reference-warm-read-8e6d40ec.log`/context, `candidate-correctness-e8a31879.log`/context, `candidate-warm-read-9a74b0b4.log`/context, augmented comparison contexts (originals unchanged), `current-read-comparison-v2.json` with actual Release PIF settings in `actual-release-compile-context.json`/preserved `actual-host-manifest.pif`, exact source hashes in `source-comparison-manifest.json`, and `activity-hydration-current-source.patch`. Environment declarations are the actual invocation settings and confirmed by emitted sample counts/context. All producers stopped; closed raw artifacts archived/indexed in the separate QA journal. Heavy capacity was handed directly to the Reminder repair writer, with no performance simulator left booted.

P1 next performance work remains Year allocation/cache-evaluation attribution and other real user latency gaps. P2 for this component is complete once delivered; do not keep repeating the same passing benchmark to chase3x. A later SQL/index candidate would require separate query-plan/data-distribution/write/size evidence; none is introduced here. Packaging and AI full-layout goals remain tracked in their separate reports, without resetting historical targets or claiming a global plateau.


The original comparison's generic `-O` label was clarified from the actual SwiftPM PIF to `-Owholemodule`. New v2 augmented contexts/comparison retain that exact build-setting name; original contexts/comparison remain unchanged. Both executed commands, Package.swift and toolchain were identical across the pair, so this metadata clarification changes no sample or numeric result and requires no repeat benchmark.
