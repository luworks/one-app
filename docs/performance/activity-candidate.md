# Activity persisted-row hydration candidate

Status: source-only candidate, pending parent-owned serial correctness and matched
performance runs. No build, Swift tests, simulator, or profiling ran in this lane.
No measured speedup or acceptance of the 3x/10x target is claimed.

Owned files: `ios/One/ActivityEvent.swift`, `ios/One/ActivityStore.swift`,
`ios/Eval/Tests/OneLogicTests/ActivityStoreTests.swift`,
`ios/Eval/Tests/OneLogicTests/ActivityReadPerformanceTests.swift`, this note.

## Hypothesis and changed variable

`ActivityStore.event(Row)` previously constructed a new event, generating a UUID,
reading the current wall clock/calendar and computing local date components and
time-zone offset, then overwrote that identity and stamp with persisted values.
The candidate constructs the persisted envelope directly. New events still
generate a UUID and use the same `ActivityClock.stamp` and payload defaults.
JSONL parsing keeps its existing initializer and fallback behavior.

Expected affected metrics: 150-row newest/deep page hydration and result-row
hydration during search/export. Search SQL scanning, count, and bulk insertion
are unchanged; no benefit is predicted for count or bulk insertion. This narrow
candidate alone is not assumed to meet the overall performance targets.

SQLite column coercion, NULL fallbacks and optional-field mapping stay at the
existing row-reader boundary. In particular NULL tier becomes system; an invalid
non-NULL tier still derives from kind; unknown kind with invalid tier is system.
Persisted timestamps/day/time zone remain independent of the current calendar.
Snapshot bytes and content remain lazy on page/single-event reads and populated
by export. Locking, connection lifetime, SQL, schema, indexes, retention,
redaction, privacy and migration behavior are unchanged.

## Correctness handoff

Added tests cover fresh-event identity/stamp/defaults, equality of every persisted
field across page/single-event/export, deferred payload loading, NULL required
columns in a deliberately damaged test-only schema, malformed numeric coercion,
and invalid/NULL tier handling. Small inline fixture data stays with these tests;
the benchmark's deterministic generator is versioned in its test source.

Parent, once the quiet host lane is granted, can run from `ios/`:

```sh
swift test --jobs 2 --filter ActivityStoreTests
```

Existing paging, query-plan, bilingual/wildcard search, retention, corruption,
snapshot and export coverage remains in that suite. No tests were executed here.
Static review checked all assignments against the old hydration path;
`git diff --check` is the source-only whitespace gate.

## Matched read benchmark handoff

Copy the identical **test file only** to the frozen production baseline checkout
(`c42b88e`, or the parent's explicitly recorded baseline revision). Its code uses
only pre-existing APIs; do not copy the candidate's production source. Record the
test hash and both source/diff states. No branch switching belongs to this lane.

From each checkout's `ios/`, serially, same Xcode/Swift/SQLite, configuration,
optimization flags, host load, and filesystem/cache context:

```sh
ACTIVITY_READ_BENCH=1 ACTIVITY_READ_SAMPLES=5 \
  swift test -c release --jobs 2 --filter ActivityReadPerformanceTests/testWarmPageReads
```

Use `tests/performance/record_command.py` to retain complete command output and
host context in canonical primary-checkout `tests/results/`; archive/index with
the QA journal only after the command exits. Record configuration explicitly:
SPM release is a host optimized track, separate from optimized Debug app proxies.

The opt-in test builds the same 100,000 synthetic events with frozen timestamps,
UTC calendar, stable IDs and text. Setup/inserts and deep-cursor discovery are
excluded. Each query gets one excluded warmup. Each of 3–5 samples times 25
identical 150-row reads using a monotonic clock and emits `PERF_SAMPLE` JSON with
raw batch milliseconds and amortized milliseconds/query. Deep starts after
10,000 matching rows; search remains the existing Chinese substring query.
There is no speed threshold assertion; row counts are checked.

Report raw values, n, median and range for each metric; compare like-for-like
**amortized warm host reads**, not historical n=1 queries, cold reads, phone
latency, UI frames or p95. Inspect dispersion and functional results before
retaining/rejecting the candidate. Parent owns final baseline/candidate evidence,
target gaps and acceptance decision; all remain pending.
