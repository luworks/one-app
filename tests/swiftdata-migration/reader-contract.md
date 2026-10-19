# Integrated One reader contract

`ios/TodayIntegrationTests/StoreUpgradeTests.swift` is an iOS Swift Testing test of the actual `One` module. It uses `@testable import One`, the nine actual model declarations in `ios/Sources/One`, and the old writer's complete field projection. It declares no models and compiles no shadow reader source. The target must be part of package **TodayModules**, because the models have package visibility. Parent integration owns target membership, resource wiring, model/configuration changes and simulator execution.

## Test resource wiring

The durable fixture catalog entry for this lane is `tests/fixtures/swiftdata-upgrade/`. Its `provenance.json` records the source run, baseline, seed/driver hash, artifact sizes/hashes, immutable SQLite checks and MIT license. All rows are synthetic. The folder contains only `old.store`, `expected.json`, `provenance.json` and `LICENSE`.

Expose that folder as a **test-only resource** named `swiftdata-upgrade` under `Bundle.module.resourceURL`; preserve the folder name when copying. The test target needs `One`, SwiftData, Testing and CryptoKit; it must compile with package name `TodayModules` and testability enabled for One. Do not place fixtures in production resource folders or link them into Today/TodayMock app resources. A missing or hash-mismatched fixture is a failure, never a skip or permission to create a replacement store. `#if os(iOS)` reflects the actual module's platform constraint; a host test discovery run cannot establish this gate.

## Frozen writer provenance

- Baseline source commit: `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`.
- Finished canonical run: `/Users/yuanlu/code/one-app/tests/results/reconstruction/swiftdata-old/baseline-e022a7a-05`.
- Seed: `OldWriter.swift`, SHA-256 `22504d1adb594026c78a4250fae8189cc3d0d053116713f7915b85e2f1828529`; epoch `1792281600`, fixed synthetic UUID suffixes, final SwiftData-generated persistent identifiers preserved.
- Main store: 122,880 bytes; SHA-256 `c7ff329418508d67f1c7acd6d4eac44c45daec80a39282433cf049d2eeba751b`.
- Expected snapshot: 13,963 bytes; SHA-256 `81c687e1bb70aed37f93bd85f809799db5ad37c87a647ecf99da317629c5b64a` (identical to the old verifier's reopened snapshot).

Both writer and verifier had exited successfully. Inspection found no open store handles, a zero-byte WAL and a 32,768-byte SHM. Opening the main file through SQLite `mode=ro&immutable=1` returned `integrity_check=ok` and the exact nine-model row counts without consulting sidecars. Thus the main file already contains all committed transactions. Only its unchanged bytes and expected JSON are packaged; the empty WAL has no transactions and SHM is transient coordination state. Original sidecars, executable, sources, logs and manifests remain untouched in the canonical run. No checkpoint or SQLite write was performed on that evidence. Before/after hashes of all original regular files matched. If any future fixture has a nonempty WAL or external binary files, this main-file-only packaging is invalid: preserve and validate the complete quiescent family instead.

## Assertions and lifecycle

The test requires exact reflected names `One.*` through comparison with the old manifest, opens an explicit existing copied file URL with the exact nine-type schema and CloudKit disabled, and verifies counts `[3,2,2,2,1,1,2,2,1]`. It compares every stored field and complete encoded persistent ID for tasks, events, alarms, lists, retired Habit, chat, retired LedgerEntry, AI grants and Share receipts. JSON encoding uses the old writer's Date/Data/optional encoding and sorted row projection. This includes exact raw chat/card/item/snapshot blobs, recurrence strings, checklist values, nullable/default fields, external identifiers, AlarmKit identifiers/signatures, Habit checkins/reminder fields and active/revoked grants.

Additional semantic checks decode chat messages/items/cards, resolve item IDs through `ModelContext.model(for:)`, and verify list membership, card target/ledger/message links, ledger Undo links, checklist UUIDs and the receipt shared UUID. Complete encoded identity is used rather than Set/native equality for decoded PersistentIdentifier, matching the diagnosed old-writer contract. This is a receipt preservation assertion; it does not exercise the production share-import transaction or acknowledgment path.

Each invocation copies the fixture into its own UUID-named temporary directory and prints that path. It opens/verifies, releases the scoped context/container, opens/verifies again, then changes only the recurring task's note and planned start by 900 seconds, explicitly saves, and compares against the baseline with only those expected fields adjusted. Two subsequent scoped opens compare every field and ID again. The deadline must remain unchanged. Each actual snapshot is written beside the candidate database before comparison. Missing/open/migration/decode/save/mismatch failures propagate; there is no fresh-store fallback, recovery/reset, deletion or cleanup handler. The bundled source is never opened by SwiftData and its bytes are rechecked after success.

Retain the printed candidate directory, including any generated WAL/SHM/external files and JSON snapshots, into canonical `/Users/yuanlu/code/one-app/tests/results/` after the test process exits, then index the complete evidence and xcresult through `tests/qa/journal.py`. Do not archive a live family. Temporary candidate files are diagnostic outputs, not reusable test inputs. The reusable fixture is versioned under `tests/fixtures/`.

## Evidence boundary

Implementation verification here is limited to source/fixture checks, immutable SQLite integrity/count inspection, SHA-256 validation and `git diff --check`; no Swift command, app build, simulator or device was run by this implementation lane. The parent must execute the actual iOS simulator integration test and retain its result. Scoped container reopen occurs within one test process; it does **not** prove independent-process relaunch, installed-app upgrade/store location, Activity migration, extension concurrency, import failure/acknowledgment, or physical-device behavior. The old independent-process writer/reopen evidence remains separately preserved. No production model edits are authorized by this contract.
