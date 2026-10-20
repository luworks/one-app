# Partial CI timeout diagnostics

Source base: `c513fe3b12d97c28283f4f88f69dd4f5304f6a04` in the sole CI writer
`codex-ci-native-reuse` (clean detached checkout before this candidate).

## Actual prior runs

- PR122 head `135e0a74caefecccfecc05ff241017718f018cd1`, run
  [39355902283](https://github.com/luworks/one-app/actions/runs/39355902283):
  cancelled by GitHub's 30-minute job limit. The retained evidence establishes
  build 159.145s, business 701, integration 28/28 (including both Health model
  tests), and snapshots 6/6 passed. Core UI report/raw log is absent. An orphan
  xcodebuild at cancellation does not establish the active UI subphase or cause.
  Artifact 12235987785 SHA-256:
  `bf1c252961a3dd926e776ef7782c67e9aa9b4315898af0c50835099bf5ff346f`.
- Main-critical `c513fe3`, run
  [39349072159](https://github.com/luworks/one-app/actions/runs/39349072159):
  completed **failure**, helpers exit 1 in 20.221s. The subsequent main usability
  validation was skipped. The downloaded job log lacks the underlying helpers
  failure detail; this candidate does not diagnose it or claim positive main
  acceptance. The earlier pending state is stale.

## Candidate boundary

The existing process runner and serial UI authority emit independent JSONL
diagnostics before waiting for completion: phase, owned PID, start time, elapsed
time, source test identifier/state, timeout/cancel and reap. Records flush at
each event; the existing process loop emits elapsed progress every 30s. The
diagnostic stream does not copy arbitrary stdout, argv, private titles, chat or
Health values. A separate always-upload step accepts only these diagnostic
files. They are explicitly diagnostic-only and never a producer receipt.

All setup and selected lanes share a 1440s maximum internal execution budget,
replacing the 2100s per-adapter timeout. The workflow records job start time;
the wrapper further subtracts elapsed checkout/helpers time from the unchanged
1800s outer budget, reserving 30s for earlier job setup, 30s for owned cleanup
and 180s for uploads. No outer timeout increase, gate removal, new runner,
platform, framework, scheduler or worker. Existing process-group cleanup/reap
remains scoped to the runner's own children. Live xcresults remain outside
accepted staging; missing/zero/cancel/timeout outcomes remain fail-closed.

This is diagnostic hardening, not a proven UI root cause or speed improvement.
The essential CI goal of <=300s including queue remains unmet. Independent
tooling candidate on main; PR122 and its declared TodayTestHost/verifiedMock
guard remain untouched. Any later integration into PR122 must be explicit.

## Verification and retained evidence

- `./dev test helpers`: **153 passed**, 14.477s. Includes pre-timeout flushed
  diagnostics, selector metadata without private output or accepted receipt,
  expired shared deadline/no dispatch, cleanup/upload budget, and existing
  missing/zero/cancel/timeout and unrelated-owner cleanup regressions.
- `./dev lint`: **passed** (SwiftLint, Ruff, actionlint).
- `git diff --check`: **passed**. One focused source review completed.
- First helper failure (macOS `/var` alias rejected in a fixture) and Ruff
  unused-import failure retained; corrected by using the fixture's canonical
  path and removing the unused import. No assertion weakened.
- No local native build, simulator UI, full UI, phone install/launch,
  permissions, signing or private-data operations. Phone remains user-accepted
  `9043647`; physical acceptance and main positive gate remain unknown.

Primary evidence: `tests/results/ci-hillclimb/timeout-diagnostics-20261019/`
(`validation.json`, both actual hosted job logs), with raw helper/lint logs
indexed in the existing QA Activity journal. Original PR122 evidence remains
under `tests/results/health-today-sync-20261019/cancel-39355902283/`.
