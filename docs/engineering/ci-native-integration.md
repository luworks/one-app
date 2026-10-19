# CI native integration handoff

Base: `2145eb6`. This change owns only `scripts/devtools/ci_adapter.py`,
`tests/ci/test_adapter.py` and this document. It supersedes the integration,
snapshot and Release pending-route descriptions in `ci-adapter.md`; no CLI,
workflow, project, package, signing or release-validator file is changed.

## Native authority

CI `integration` now selects `plan(['integration']).selectors.integration`,
including the production StoreUpgrade Swift Testing method in **TodayTests**.
CI `snapshots` selects `plan(['snapshot']).selectors.snapshot`, the native
**TodaySnapshotTests** authority. Neither lane reads UI selectors or guesses
selectors from graph node names. SnapshotTesting's exact pin and baseline
recording/review remain project/snapshot-owner responsibilities. Missing references
and failed comparisons must fail through actual native execution.

Both call the same API as `./dev test integration|snapshot`:
`commands.test(root, group, timeout=600)`, which calls `xcode_tests.run`.
The dev adapter owns shared locks, canonical simulator/DD, process cancellation,
shutdown and full completed xcresult parsing. CI requires exactly one report
receipt for the expected scheme, from the canonical Git-common
`tests/results/devtools/logs/*-xcode/` directory, and a nonempty completed bundle.
It rejects symlinks, revalidates all retained xcresult leaf attempts against the
selected IDs, retains native process/parser/summary/log errors and coverage
status, and preserves the adapter's nonzero result (including shutdown failure).
Missing/extra/wrong-target leaves, zero execution, unexpected skips and earlier
failures cannot become passing reports. Console logs cannot supply native passes.

The complete closed native evidence directory is copied to CI output `native/`.
`native/<scheme>.report.json` retains the full dev leaf report and diagnostics;
`test-report.json` contains CI's independent leaf revalidation. All original
logs, reports and completed bundle files are already hashed/indexed by the dev
adapter in the canonical QA journal. No live bundle is copied or finalized.
`safe_artifacts` preserves every xcresult byte, including hidden store metadata,
and hashes staged files; other text remains redacted. Inputs are synthetic test
evidence only. Business host authority and core UI journeys retain their prior
runner routes; host business includes the separate SceneRegistryTests target.

## Release boundary and required API

CI `release` now actually requests `xcodebuild build`, scheme **Today**,
configuration **Release**, generic iOS Simulator, shared derived data, jobs 2,
arm64, with signing explicitly disabled. It requires nonempty app, widget and
share executables from **Release-iphonesimulator**. Debug products cannot satisfy
this lane. This bounded product-presence inspection does not establish exclusion
of development code or resources, linked dependencies, or final artifact safety.

No callable unsigned Release exclusion validator exists in the inspected
`scripts/release` API at this revision. The signed archive preflight/validator
requires signing metadata and is not a substitute. After the real Release build
and product inspection, CI therefore emits
`release_exclusion_authority_unavailable` and remains failed. It never archives,
exports, uploads, changes signing or claims release acceptance.

The release owner must provide an unsigned callable API accepting the repository,
actual Release products/DD and bounded process runner, returning retained
machine-readable checks plus diagnostic/artifact paths. Its authority must inspect
the actual Release graph/link maps, resources and app/extensions, reject missing
or stale evidence and development dependencies/resources, and report nonzero on
incomplete inspection. No speculative API is invoked here. Wire that actual API
before removing the remaining failure. Sanitizer, performance and protected
release stay unsupported because their acceptance authorities remain absent.

## Parent upload boundary

The current parent-owned `scripts/ci/run.py::stage` still redacts text and drops
hidden files inside xcresult bundles. The CI adapter's own `safe_artifacts` now
preserves those bytes, but that separate workflow staging function must adopt
equivalent bundle preservation before uploaded bundles can be called byte-exact.
The canonical native bundles and their journal hashes remain intact. This file
ownership boundary prevents repairing the wrapper in this change.

## Host-only verification

`python3 -m unittest discover -s tests/ci -v` exercises native success paired with
failed/retried/skipped/zero/unknown/missing/extra/wrong-target leaves, diagnostic
and process failures, missing evidence, symlink rejection and byte-preserving
bundle staging. Release tests inspect command configuration and both present and
absent synthetic product paths; a successful build still cannot pass without the
real exclusion validator. Versioned inline fixtures live in `tests/ci/test_adapter.py`.

No Swift/Xcode build, simulator, remote CI dispatch or full collection ran in
this task. Hosted runner label `xcode-27` and Xcode 27.1 are configured in the
workflow; initial run **39192267117** failed because `dev ci` was absent, per the
parent handoff. That history is not a CI pass. Baseline recording/review,
perturbation acceptance, real Release inspection and actual hosted CI execution
remain parent-owned gates.

Final local verification: **52 host tests passed**, scoped Ruff and diff checks
passed. Durable logs and journal session: `ci-native-integration-20261019T034643Z`,
under the canonical checkout `tests/results/runs/` directory. This evidence does
not establish hosted CI or simulator acceptance.
