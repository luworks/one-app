# Dev Xcode test adapter handoff

Base: `9183e90942e817c499ea3c3d5a7f04fee6ec1494`. Scope is the dev test
adapter and host-only process-mocked regression coverage. Project generation,
Xcode targets, packages, production models, signing and snapshot references are
parent-owned. This document complements `test-authority-integration.md`.

## Entry points and API

- `./dev test unit`: existing SwiftPM host logic authority, including the separate
  SceneRegistryTests package target. Integration is never selected on the host.
- `./dev test ios-unit`: generated `TodayTests` scheme, unit lane only.
- `./dev test integration`: generated `TodayTests` scheme, integration lane only.
- `./dev test snapshot`: generated `TodaySnapshotTests` scheme, snapshot lane only.
- Each focused command accepts repeatable `--only SUITE[/METHOD]` or explicit
  target selectors; unknown or out-of-group selections fail before platform work.
- `./dev test ui|core|accessibility` retains `ios/Eval/run-e2e.py`, TodayMock and
  TodayUITests authority, including legacy OneUITests selector aliases.
- `./dev test ui --full` retains the existing UI-only full route.
- **Parent only, at the authorized frozen final revision:**
  `./dev test release --full` runs host once, combined iOS unit/integration once,
  snapshot once, then complete UI once, sequentially. Nonzero stage results do
  not hide the first failure or cause retries. Setup exceptions stop collection.
  `release` without `--full`, and `--full` with `--only`, are rejected.

Python API: `commands.test(root, group, only=(), timeout=600, full=False)`;
`xcode_tests.run(root, contract, groups, only=(), timeout=600, locked=False)`.
`locked=True` is internal: caller must already hold the shared host/DD locks.
`xcode_tests.selected(...)` resolves source-backed plans;
`completed_report(...)` retains parser errors as failed machine-readable reports.
The TodayTests invocation compares all completed leaves to the **union** of
selected unit and integration IDs. Explicit targets are preserved.

## Resource and evidence ownership

One existing host-heavy lock and worktree DD lock cover each invocation; final
collection holds them across all stages without reacquisition. The Xcode adapter
also uses the existing UI runner's simulator-name/cache lock protocol.
Canonical simulator: `Today-Dev-<first eight characters of worktree_id>`;
canonical DD: `derived_data(root)`. Reuse requires exact name, iPhone 18 Pro Max,
iOS 27.0 and Shutdown state. Ambiguous names or an already active simulator fail
without taking ownership. Only the selected/created device is booted and shut
down; no deletion, erase or global cleanup is performed. Xcode batches keep the
same device warm; it shuts down before the UI runner takes its lifecycle.

All platform commands use the existing owned-process helper. Each has a unique
redacted raw log in the Git-common primary checkout's
`tests/results/devtools/logs/<unique>-xcode/`. Reports and every file of the
completed xcresult bundle are hashed/indexed through `tests/qa/journal.py` into
`/Users/yuanlu/code/one-app/tests/results/activity.sqlite`. No live bundle is
moved/finalized. Modern xcresult summary and test-tree JSON outputs are retained
as command logs. No aggregate count or console-only fallback can establish iOS
execution. Missing bundle, malformed/zero leaves, unknown statuses, wrong/extra
IDs, missing IDs, unexpected skips, process/parser exits and diagnostic logs fail
closed. Earlier failed leaves or console failures remain failures after a pass.

## Build policy and remaining parent gates

Every Xcode lane uses `xcodebuild test` in Debug for the iOS Simulator; it rebuilds
with normal Xcode incremental behavior and never uses an unvalidated
`test-without-building` cache. Source/lock/Xcode/SDK/architecture/configuration
cache provenance optimization is intentionally pending, not asserted.

Parent must generate schemes **TodayTests** and **TodaySnapshotTests**, with
TodayTests containing old logic, SceneRegistryTests and real production
StoreUpgrade Swift Testing/resources; only TodaySnapshotTests links exact
SnapshotTesting 1.19.6. Parent must integrate its runtime changes and run actual
host Swift, focused simulator integration/snapshot and UI acceptance in its owned
heavy lane before final collection. Snapshot PNG recording/review/comparison,
physical devices and hosted CI remain separate acceptance gates.

## Host-only proof

`python3 -m unittest discover -s tests/devtools -p test_xcode_tests.py -v`
exercises real source plans, combined lanes, simulator ownership, command shape,
completed evidence, first failures, parser/process failures and full-route order
with mocked processes. `python3 -m unittest discover -s tests/testing -v` covers
the shared contract (including legacy typed xcresult leaves). These checks do
not build Swift/Xcode or run/boot a simulator. No full collection was executed.
