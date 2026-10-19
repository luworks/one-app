# Check, benchmark and report integration

Base: `ffc704de43ad451e5ee3866102409a1986b2548d`.
This lane owns only three new devtools modules, their focused Python tests and
this document. CLI wiring, launcher runtime routing, commands, configurations,
models and native acceptance belong to root. No existing file is changed.

## Exact Python interface for root wiring

```python
check.run(root, checks=check.DEFAULT_CHECKS, *, timeout=600, cancel=None) -> dict
benchmark.run(root, kind, *, n=1, arguments=(), conditions='', timeout=600, cancel=None) -> dict
report.collect(root, paths=()) -> dict
```

Import from `scripts.devtools`. Print the returned dictionary as JSON and return
its integer `exit`. `checks`, `arguments` and `paths` are sequences, never shell
strings. Suggested CLI shape is `check [--check NAME ...]`,
`benchmark KIND --n N --conditions TEXT [existing-command-arguments ...]`, and
`report [PATH ...]`. Root must add **report** to the launcher's read-only routing
alongside doctor/inventory/plan; otherwise optional runtime activation can defeat
the read-only entry contract. Library collection itself performs no writes or
subprocesses. Do not call inventory/tool installers/journal constructors around
report. Library errors are actionable ValueError/OSError/RuntimeError and use the
existing CLI error boundary.

Check defaults are `format`, `lint`, `unit`: existing strict formatter in check
mode, existing strict lint, and authoritative host test selection/parser.
Additional explicitly selected checks are `ios-unit`, `integration`, `snapshot`,
`core`, `accessibility`. Unknown, duplicate and empty selections fail before work.
The first nonzero command stops the sequence and subsequent checks remain
`not_run`; source changes during collection also fail. There is no default full
UI/release run, automatic bootstrap, baseline recording or code formatting write.
A selection passing means only those selected authorities returned success.

Each invocation calls `[sys.executable, absolute_root/dev, *arguments]` using the
existing owned-process runner, with no shell, and preserves space-containing
paths. Existing commands retain exclusive host/DD locks, build provenance,
simulator leases, native lifecycle, parsing and artifact authority; the new
parent does not acquire another lock around them. Timeout is **per invocation**,
not a total batch deadline. SIGINT/SIGTERM and caller cancellation use existing
runner cancellation with five seconds of outer grace for nested authority
cleanup. A pre-set cancellation Event launches nothing; timeout/cancellation
stops collection without retry. An exception retains runner/journal evidence but
may prevent a completed batch receipt; report does not invent that receipt.

## Benchmark inputs and interpretation

- `cold`: canonical `build Debug`, n=1, worktree DD must be absent at preflight.
  Never deletes, cleans or replaces caches. This observes DD absence; another
  concurrently launched command could populate it before the build acquires its
  own lock. Serialize benchmark work externally for a controlled comparison.
- `incremental`: canonical `build Debug`; exact existing source/toolchain/options
  build provenance must be valid before measurement. No source perturbation or
  cache warm-up is performed automatically.
- `unit`: `test unit`, plus existing CLI suffix arguments such as
  `('--only', 'SomeSuite/testMethod')`. The authoritative test command checks
  execution, skips and missing results; a printed success marker is insufficient.
- `ui`: `test ui`, requiring focused `--only SELECTOR` pairs. It uses the existing
  UI runner and includes its build/lifecycle overhead, rather than claiming pure
  test execution or screenshot latency.
- `screenshot`: `ui capture`, requiring existing `--scene` and new `--output`
  inputs; other capture options pass to the existing CLI. n=1 preserves the
  fresh-output contract. It includes build/launch/readiness/capture/shutdown.
- `gallery`: fails before execution with the concrete blocker that the gallery
  authority exposes an indefinite server, with no bounded refresh command.
  Screenshot capture can measure its native capture dependency, but does not
  establish gallery edit-to-refresh or browser latency.

Every benchmark requires explicit `conditions` describing actual host/cache/
device/environment preparation; these are **caller assertions**, not verified
machine facts. Source fingerprint/toolchain, prior provenance, observed DD
existence, requested n, attempted n, successful n, each measured wall duration,
actual redacted argv, exit/reason and raw-log path/hash are retained. Cold means
absent worktree DD, not cold OS or SwiftPM caches. Incremental repeated no-edit
builds are not an edit/rebuild speedup experiment. Median/min/max summarize only
successful exited samples; failed/timed-out samples remain individually visible
and the collection fails. No P95 is estimated. `completed` denotes a measured
invocation collection, not visual or physical-device acceptance.

## Durable evidence and read-only reports

Closed raw logs use existing canonical `tests/results/devtools/logs/` paths.
Completed immutable unique JSON receipts live in canonical
`tests/results/devtools/runs/`. Both are hashed/indexed through the existing QA
Activity journal. No evidence or cache is deleted. Fingerprints include dirty
and untracked source inputs through the existing core implementation.

Default report discovery reads dev receipts, nested dev authority `*.report.json`
and E2E `tests/results/runs/**/summary.json`. Explicit retained JSON paths can
include gallery attempts or other authority reports. All explicit files must be
regular retained files beneath primary `tests/results`; traversal, final
symlinks, missing files and malformed JSON produce blockers. Reports preserve
complete source records with observed status/exit, source worktree and file hash.
Dev receipt raw-log hashes are rechecked; missing/changed logs, incomplete or
failed commands and source drift block the report. External authority statuses
are preserved without translating their counters/skips/parser evidence into
another acceptance verdict. Unrecognized/absent completion statuses block.

An empty evidence set is blocked. The report status is `observed` or `blocked`,
never a freshly inferred pass. Historical successful runs, including runs from
other worktrees, are not current-revision acceptance. Report does not acquire
locks, execute tools, open SQLite, create directories or repair evidence. Parent
may print it; redirecting output to a file is a separate caller-owned write.

## Verification and remaining gates

Focused command:

```sh
python3 -m unittest discover -s tests/devtools -p test_check_report.py -v
ruff check --config ruff.toml scripts/devtools/check.py scripts/devtools/benchmark.py scripts/devtools/report.py tests/devtools/test_check_report.py
```

Tests exercise selected authority mapping, failure stop, pre-cancellation,
benchmark n/timeout retention, unsupported cold/gallery conditions, read-only
report bytes/mtime, missing/modified/malformed/outside evidence and actual short
Python child exit/timeout/cancellation from a cwd containing spaces. Actual child
logs are retained in primary results through `Evidence`; mocked selection and
measurement tests are not native performance measurements. The final focused
run/log and action are indexed under journal session
`dev-check-report-20261018`.

No Swift/Xcode build, Swift logic suite, simulator/UI journey, native capture,
gallery browser flow, cold/incremental performance comparison or physical device
was run. Root must wire the entry points, preserve read-only report launch routing
and perform its authorized integrated native acceptance. Gallery bounded refresh
benchmark support remains a concrete missing upstream API, not a claimed pass.
