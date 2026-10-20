# Test authority integration

This change owns only `scripts/testing/contract.py`, `tests/testing/groups.json`,
`tests/testing/test_contract.py` and this document. Runner, dev CLI, project,
package and production module wiring remain parent-owned. Read this together
with `baseline.md`, `visual-testing.md` and `ci.md`: older pending-state
statements in those documents are not evidence that the integrated targets ran.

## Source and execution contract

`contract.inventory()` discovers both XCTest methods and Swift Testing `@Test`
functions from the current source files. Strings/comments and non-XCTest helper
methods do not create tests. Source inventory is never execution evidence.
The original migration inventory in `groups.json` remains unchanged: every one
of its 661 logic and 319 UI method IDs must remain present after target aliases
are applied. Current counts may grow; regressions compare IDs, not totals.

| Group | Selector lane | Runner | Target | Sources / behavior |
| --- | --- | --- | --- | --- |
| unit | logic | SwiftPM host | TodayTests, SceneRegistryTests | Unchanged `ios/Eval/Tests/OneLogicTests`, plus `ios/SceneRegistryTests` in its separate package target |
| ios-unit | unit | Xcode iOS | TodayTests | The same logic and scene registry sources in the integrated Xcode target |
| integration | integration | Xcode iOS | TodayTests | `ios/TodayIntegrationTests/StoreUpgradeTests.swift`: actual `One` production models, frozen disk reader, reopen and mutation assertions |
| snapshot | snapshot | Xcode iOS | TodaySnapshotTests | All six `ios/TodaySnapshotTests/NativeSnapshotTests.swift` native image comparison/determinism methods |
| accessibility | ui | Xcode iOS UI | TodayUITests | `AccessibilityAuditTests/testCoreTabsAudit`, `testHealthDetailRangeAndDismissAudit`, `testStopwatchLargeTypeActionsAudit` |
| ui / core | ui | Xcode iOS UI | TodayUITests | Complete current UI collection / existing focused core journeys |

The union of the iOS unit and integration lanes is the source membership of
Xcode `TodayTests`; the integration reader must never be expected from host
`swift test`. These tests import the same actual production modules. No test
module copies or substitute model definitions are introduced here.
The snapshot target alone uses `SnapshotTesting` exact **1.19.6**; its pin is
recorded as test-only lane metadata, not proof of project linkage.
Snapshot references still require actual recording/review/comparison as described
in `visual-testing.md`. Selecting methods does not turn missing PNGs into passes.
UI execution uses scheme/app host **TodayMock** with `TodayUITests` selectors.
`OneUITests/...` remains accepted and translates to `TodayUITests/...`.

## Parent adapter API

Use the Python API for named lanes; this change does not add CLI arguments:

```python
p = contract.plan(['ios-unit', 'integration', 'snapshot', 'accessibility'])
expected = p['selectors']['integration']
by_target = p['expected_by_target']['integration']['TodayTests']
attempts = contract.xcresult_attempts(actual_completed_xcresult_json, 'integration')
result = contract.report(expected, attempts, exit_code=process_exit, raw_log=raw_log)
```

`selectors` explicitly lists expected IDs per lane; `expected_by_target` groups
the same IDs per lane and target. `lanes` supplies runner/platform/source metadata.
Empty lanes remain explicit empty arrays/maps and must not be scheduled.
`logic` includes both host targets; do not replace its target prefixes with a
single target or require the iOS integration method on a Mac.
For one Xcode invocation combining lanes, compare its parsed leaves against the
union of the selected lanes, or partition leaves by expected IDs before reporting
each lane. Do not pass a whole multi-target tree to a narrow lane report: extra
executions fail closed. Supply the lane to `xcresult_attempts` for unqualified IDs.
Explicit target IDs survive canonicalization, so the wrong target cannot satisfy
the right method. The CLI/runner owner must wire these plans before claiming that
`--group integration` or `--group snapshot` executes their new authorities.

Unknown groups/lanes/selectors, cyclic includes, missing source directories and
zero source/selection inventories raise `ValueError`. Report failures include
missing or extra executions, zero expected/executed tests, invalid execution
statuses, nonzero process exits, unexpected skips and bad-selector/parser/no-test
diagnostics. An opt-in skip must still match the exact method, category and reason;
it remains incomplete coverage, and all-skipped execution fails. First failures
are retained even if a later attempt or final xcresult leaf passes. Aggregate
suite counts and a successful process exit cannot replace actual leaf results.
Modern and legacy typed xcresult leaves are supported. Structured parse errors
must be retained as failed reports by the caller; no log-only iOS fallback exists.

## Verification and evidence

Host-only verification uses `python3 -m unittest discover -s tests/testing -v`.
Fixtures are small synthetic inline parser trees and Swift snippets in the
versioned Python test file. Runner interaction tests inject subprocess results;
no Swift, Xcode, simulator or app execution occurs. Positive/negative regressions
exercise lane/target isolation, real source selection, full baseline ID retention,
malformed/missing/extra results, skips and first-failure preservation.

Raw host test output and development actions are retained through
`tests/qa/journal.py` in the Git-common primary checkout's `tests/results/`, under
session `test-authority-integration-20261018`. The parent must run actual host
Swift tests and focused iOS integration/snapshot/accessibility acceptance after
wiring its adapters. Physical-device behavior and hosted CI remain separate gates.
