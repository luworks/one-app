# Bounded CI adapter

`scripts/devtools/ci_adapter.py` exposes the integration-owned CLI entry point:

```python
main(root, lane, *, selection, output, sha, synthetic, no_distribute) -> int
```

The caller passes a policy selection JSON path, an unused output directory (or
one containing only the wrapper's `selection.json`), the full integrated commit
SHA, and both safety booleans set to `True`. Use an output directory outside the
checkout. The adapter requires a clean checkout including untracked files and
compares HEAD and source fingerprints before and after execution. It never
accepts a previous report. `cli.py` wiring remains parent-owned.

Selection version 1 requires `mode: wide|affected`, string `reason`, string lists
`changed` and `targets`, and booleans `all_targets` and `snapshots`. Wide mode
requires `all_targets=true`; affected mode requires false. Graph targets are not
test selectors. This first adapter conservatively executes the entire registered
group for both selection modes, including documentation-only changes, rather
than guessing test ownership or allowing an empty lane.

## Execution authority

- **format** calls `commands.format_sources(check=True)`, using the pinned Apple
  swift-format resolver and its explicit Swift file arguments. Empty inputs fail.
- **lint** calls `commands.lint`, retaining every process receipt. It requires the
  complete SwiftLint/Ruff/actionlint set applicable to the checkout and a positive
  SwiftLint file count. Its executed count measures completed tool invariants.
- **business** uses the same `swift test --package-path ios --jobs 2` command as
  `commands.test(unit)`. Expected IDs and finished-test parsing come from
  `scripts/testing/contract.py`; discovery alone never counts as execution.
- **integration** uses the registered integration group and the existing serial
  `ios/Eval/run-e2e.py` authority, with explicit validated `--only` IDs, the shared
  dev simulator name and derived-data directory, and a fresh evidence directory.
- **core-ui** uses the registered core group plus the existing event long-press,
  flexible-task drag and durable share-import journeys named in `CORE_EXTRA`.
  These are concrete supporting journeys; event long-press coverage does not
  establish that every possible event drag is immobile. Unknown methods fail
  before launching a runner. The synthetic dataset and isolated stores remain
  owned by the existing UI tests; integration tests touching EventKit operate
  only in the runner-owned disposable simulator.
- **build** uses the dev Debug simulator build recipe through `commands.execute`,
  adding explicit `CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO`. It
  checks the nonempty app executable and both embedded extension executables.
  This does not claim physical-device, Release or signing acceptance.
- **extended** uses the registered complete UI collection only for a matching
  `workflow_dispatch` and `MANUAL_LANE=extended`. Routine lanes never pass `--full`.

All direct commands use the shared dev process runner, bounded 600-second timeout,
redacted retained logs, host/derived-data locks and QA journal. The UI authority
owns its simulator shutdown. The adapter requires successful UI and shutdown
stages, parses the retained `xcresult-tests.json` execution leaves again, and
checks the runner's SHA and selection. First failures survive later passing
attempts; there is no adapter retry. Missing tests, unexpected tests/skips,
zero results, bad-selector diagnostics, cancellation, timeout, source mutation
and command failures all fail closed.

The current dev/test authorities do **not** provide completed reviewed scene
baseline comparisons, unsigned Release graph/link-map/resource validation,
sanitizer result collection, stable benchmark budget acceptance, or guarded
unsigned archive acceptance. Accordingly `snapshots`, `release`, `sanitizer`,
`performance`, and `protected-release` emit failed reports with those concrete
prerequisites and execute no replacement/no-op checks. Manual lanes additionally
require matching explicit dispatch. No signing, export, upload or distribution
command is exposed. These blockers must be implemented by their respective
owners before the required CI check can pass; do not disable them to get green.

## Report and artifacts

The exact required fields accepted by `scripts/ci/policy.py::validate_report` are:

```json
{"sha":"<40-character integrated SHA>","lane":"business","status":"passed","executed":1,"failed":0,"cancelled":0,"missing":0,"synthetic":true}
```

All four counters are nonnegative integers (booleans are invalid); executed must
be positive and failed/cancelled/missing must be zero. Extra adapter fields are
`errors` (retained first diagnostics) and `source_sha256` (when source validation
succeeded). Tests count finished leaf attempts, including failed attempts;
format counts explicit checked inputs, lint counts completed tool invariants,
and build counts verified executables. A process failure can add a failing
invariant even when no individual test failure was parsed. Missing prerequisites
produce a failed report, never a synthetic passing count. Output ownership errors
return nonzero without overwriting existing evidence.

The existing `scripts/ci/run.py` stages the report and retained output through its
artifact allowlist and validates the report. The adapter also exposes
`safe_artifacts(source, destination, *, sha, lane)` for focused callers: matching
synthetic receipt required, fresh destination outside source, no symlinks or
hidden entries, only logs/text/JSON/crashes/PNG/xcresult contents, redacted text,
and hashed manifest. It is never invoked on a workspace or app/user database.
Raw process logs remain in the shared QA results tree and known runner evidence
is retained under output; the adapter does not collect arbitrary result folders.
Hosted runners resolve QA storage from their own checkout's Git common directory,
not a hardcoded workstation path.

## Verification boundary

`tests/ci/test_adapter.py` uses versioned inline synthetic Swift source and an
injected command runner to exercise actual report rejection, failure retention,
zero/missing results, cancellation, source changes and safe artifact staging.
The public `main` has no synthetic success mode or runner flag. These host tests
perform no Swift builds, simulator boots or real CI dispatch. Real tool, build,
simulator and hosted CI execution remain pending parent-owned verification.
Development actions and focused test output are journaled in the workstation's
canonical `/Users/yuanlu/code/one-app/tests/results` tree.

Local verification on 2026-10-18: `python3 -m unittest discover -s tests/ci -v`
passed 44 host tests (19 adapter regressions plus 25 policy tests). Scoped Ruff
and `git diff --check` passed. Durable evidence is indexed under session
`ci-adapter-20261018`, with logs in `tests/results/runs/ci-adapter-20261018/` of
the canonical checkout. This is host adapter evidence, not executed lane acceptance.
