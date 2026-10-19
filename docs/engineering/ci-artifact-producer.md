# Closed CI artifact producer integration

Base: `2d92ca00677351f2649ca2ac42487b244b66d674`, including the merged
`f32b942` artifact-integrity contract. Scope: `scripts/ci/run.py`,
`scripts/devtools/ci_adapter.py`, `tests/ci/`, and this document.
This supersedes the producer-pending descriptions in `ci-artifact-integrity.md`
and `ci-native-integration.md`; their bundle-preservation and authority rules remain.

## Producer lifecycle

The workflow creates exactly `$RUNNER_TEMP/today-<lane>` with only its generated
selection file. The adapter rejects preexisting evidence, links, source-workspace
outputs and mismatched source commits. Execution remains synchronous through the
existing dev process/native adapters. Native evidence is copied only after
`commands.test` returns, including its owned process cleanup and simulator shutdown.
The canonical native directory and journal remain the original evidence authority.
No archive/copy operation is performed on an executing native adapter's bundle.

UI execution additionally requires a normal runner return and explicit successful
shutdown stage, with no shutdown error, before publication closure. Interrupted,
timed-out or incomplete shutdown runs retain their original outputs and failed
report, but receive no closed provenance receipt. Their potentially live bundles
are neither walked for sealing nor published. The original native process API
owns its closure contract; changing that API to return early would invalidate
this integration and must not be done without a matching closure authority.

After all owned writers finish, `close_producer` inventories only fixed generated
roots: selection, accepted selection, adapter command log, test report, native
and UI runner evidence, and Release graph evidence. It never discovers arbitrary
workspace/private directories. Unrelated files outside these roots are not read.
Links, unsupported entries and empty bundles fail closure. Every regular bundle
file is included, including hidden and binary files; bundle bytes are immutable.
External text evidence is redacted before final hashing. Unexpected secret
candidates reject closure rather than changing bundle bytes to hide contamination.

The receipt binds full 40-character SHA, lane and exact source directory basename;
it uses the existing `artifact_provenance` v1 schema. File hashes describe actual
closed output bytes. `report.json` is atomically written last and excluded from
its own inventory, avoiding circular hashing. Failed attempts, retries, missing
results, parser diagnostics and nonzero exits remain failures in the report.
`safe_artifacts` now uses the same receipt-validating stage API as the wrapper;
there is no second permissive workspace-walking publication route.

## Wrapper ownership

After the adapter process exits, the wrapper writes a separate
`wrapper-command.log` using exclusive creation. It does not overwrite the
adapter's `command.log`. Redacted wrapper diagnostics remain available even if
the adapter report is missing, malformed or rejected. Candidate secrets in raw
wrapper output reject finalization; only redacted diagnostics are retained.

The wrapper verifies every already-sealed file hash before adding its log's
actual hash to the receipt, then atomically replaces `report.json` last.
It never accepts changed producer bytes by rehashing them. Stage subsequently
revalidates the full inventory, bundle membership and source bytes before its
atomic publication rename. A failed report can publish closed diagnostic
artifacts without becoming a successful lane. Nonzero adapter exit, including
cancellation, is preserved; zero exit with missing/invalid report still fails.
Report rejection never prints artifact content or unfiltered exception text.

## Explicit workflow trust boundary

Closure requires the configured **Today CI** GitHub Actions context,
`TODAY_CI_SYNTHETIC=1`, the exact integrated `GITHUB_SHA`, the supported event and
owned temporary directory. `pull_request_target` is rejected. This trusts the
workflow owner's no-untrusted-secrets isolation; CLI `--synthetic` alone never
establishes it. The configured workflow uses read-only repository permissions,
checkout with `persist-credentials: false`, and no secret forwarding to test code.
These must remain hard deployment constraints. Environment strings are context,
not authentication, and the receipt is not a cryptographic attestation.

Before execution and again before sealing, nonempty secret-bearing environment
assignments and recognizable credential candidates are rejected without printing
names or values. This includes runtime/upload credentials if actually inherited
by the producer process; no infrastructure credential exemption is inferred.
The workflow owner must isolate those credentials from checkout/test execution.
Candidate scanning is a blocking heuristic, not proof that arbitrary data cannot
contain secrets. Do not use this producer on private/user data or a runner where
untrusted code can access secrets under other names or through other channels.
No environment values are used to populate output or receipts.

## Release authority and remaining gates

The existing unsigned simulator **Release** build and three executable presence
checks remain. When those products exist, the adapter now calls the real
`scripts/release/graph.py::check` source API using bounded dev process execution,
retaining its command logs and graph JSON. It also calls the real
`release.py::validate_resources` on the actual Release app, checking privacy,
licenses and development-resource exclusion. Missing resources fail immediately.
Neither operation performs signing, archive/export or service access.

Source graph and simulator resource checks cannot replace `validate-local`'s
actual iPhoneOS archive, executable/dSYM UUIDs and executable-bound linker maps.
Even with successful source/resource checks, `release` remains failed with
`release_exclusion_authority_unavailable`. Sanitizer, performance and
protected-release remain unsupported. No unsupported gate was silently removed.
Root still owns project/configuration resources, real build/archive evidence and
any decision to authorize further Release work.

The existing upload action has `include-hidden-files: false`. Local stage now
preserves and inventories hidden xcresult files, but that upload setting still
needs a workflow-owner change before remote uploads can be called complete.
This bounded change does not modify upload configuration or upload anything.
No hosted CI, Xcode/Swift build, simulator, device, network, account or signing
operation was run. Host checks establish the producer/wrapper/stage lifecycle
with generated synthetic fixtures, not native or remote execution acceptance.

## Host evidence

Reusable inputs are inline synthetic fixtures in `tests/ci/test_producer.py`,
`test_adapter.py`, `test_artifact_integrity.py` and `test_policy.py`.
The two legacy policy fixtures now use full SHA plus valid closed inventory;
the original redaction, exclusion and symlink assertions are preserved.
Coverage includes final hashes/hidden files, independent wrapper log ownership,
first-failure retention, cancellation/missing reports, environment/candidate
secret rejection, changed closed evidence and incomplete shutdown publication.
Release coverage pairs missing actual resources with successful synthetic
resources that still cannot bypass the archive/link-map gate.

Run `python3 -m unittest discover -s tests/ci -v`. Evidence is retained under
canonical `tests/results/runs/ci-producer-seal-20261018/`, indexed through
`tests/qa/journal.py` session `ci-producer-seal-20261018`. Earlier test logs remain
separate; the final host log is `host-tests-closure-final.log`. Scoped Ruff checks
and `git diff --check` are retained in `static-checks-final.log`; the preexisting policy
fixture import layout uses `--ignore E402` for its scoped Ruff invocation.

Verification: the full host collection passed **75 tests** in 3.039 seconds.
A final malformed-report guard was then added; the affected producer collection
passed **10 tests** in 0.135 seconds (`producer-malformed-final.log`). Scoped Ruff
and diff checks passed at the final revision. No passing native journey or hosted
CI acceptance is claimed by these host fixtures.
