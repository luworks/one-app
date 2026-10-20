# Main helper environment repair

## Retained failures

- PR123 head `501eff4c1642b38351f5dbeb9176372bdd924b2a`, integrated `9fef85995270d35c0800a94b92faeeb32a7e2ec3`: run `39359694064`, job `118422704143`.
- Artifact `12237453092`: 458959 bytes, SHA256 `4c0774805f2d33c824628cf07150ae075c2b1e88c8d1b06dec664ef1ead08d1a`. Independent partial artifact `12237682662` is also retained.
- Build-for-testing exited 0 after 107.227s; integration exited 0 after 441.438s; snapshots exited 0 after 176.424s. These are separate from UI acceptance.
- UI PID 31292: `ShareImportTests/testPersistedShareIsVisibleAndReplayDoesNotDuplicate` started at 340.470s and failed at 417.345s. `SinglePresentationTests/testDraggingATaskDoesNotMakeAnEvent` started at 417.582s, with no terminal selector result. The core-ui adapter PID 31257 timed out at 615.076s; runner was cancelled and reaped with exit -9. Producer close rejected the unclosed runner. No accepted UI receipt exists.
- Partial metadata contains no ShareImport assertion text or UI operation log. The closed artifact excludes the unclosed core-ui runner. Neither a product cause nor a successful combined import can be inferred from this trace.
- Main `54a09e6ed5be75e7c757e4f0d5ac083b66592cc9`: run `39360311849`, job `118424715018`, first failing step `Run ./dev test helpers`, exit 1 in 27.986s. No artifacts were uploaded. The job log identifies a runner-local helper log but does not contain its traceback.

## Concrete repair

Reproduced locally with the hosted push/main environment: three PR selection assertions acquire `main-critical-v1`, and two mocked native dispatch tests attempt real main acceptance sealing. The PR `SetupTests` fixtures inherited the host event/ref. They now explicitly declare `pull_request` and a PR merge ref, with cleanup restoring the environment. Production gate logic, test assertions and independent main acceptance tests remain unchanged. This reproduces a main-specific helper defect; the missing remote traceback prevents claiming an exact remote exception match.

Normal merge `ba783ee4` incorporates main's Health changes and installed Mock product guard. No force push, budget increase, selection reduction or gate relaxation.

## Validation and remaining boundary

- `./dev test helpers`: 158 passed before the repair in a normal local environment.
- Hosted push/main environment before repair: 158 tests, three failures and two errors retained.
- First repaired run removed those failures but hit an unrelated temporary Git objects directory cleanup error; its raw evidence is preserved.
- Final `./dev test helpers` under the same hosted push/main environment: 158 passed.
- `./dev lint`: passed, including actionlint. `git diff --check`: passed.
- No local native build, simulator UI or phone operation. The hosted gate remains required. For the unresolved UI failure, the next useful check is the named ShareImport leaf with its original assertions and complete runner operation log; no speculative product or presentation change is justified by metadata alone.
- The <=300s including queue objective remains unmet. Install requires exact green merged main, actual `preflight --for-install`, and matching signed device artifact; PR green alone is insufficient.

Raw logs, zip files, extracted files and hashes are indexed in the primary checkout QA journal, session `ci-hillclimb-20261019-v27`, under `tests/results/ci-hillclimb-20261019/v27-pr123`, `v27-main54` and `v27-*.log`.
