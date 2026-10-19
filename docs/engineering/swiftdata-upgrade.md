# SwiftData upgrade characterization

The frozen source baseline is `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`. The isolated harness is in `tests/swiftdata-migration/`; it changes no production model, project, package, signing or app assembly.

## Old implementation writer

The source lock records every baseline input SHA-256 and exact retained model spans. The harness extracts both pure-source lists from the baseline `ios/Package.swift`, then compiles all those files and the real old declarations with macOS SwiftData/SwiftUI using `xcrun swiftc -module-name One -parse-as-library -j 1 -Onone -lsqlite3`. It does not substitute equivalent-looking model definitions. `Models.swift` retains `OneTask`, `OneEvent` and `ShareImportReceipt` while excluding only the bounded `Capture` write extension. `Ledger.swift` retains its beginning through `AIGrant`, including `LedgerEntry.legacyRow`, and excludes the following `Ledger` enum. `OneAlarm.swift`, `OneList.swift`, `Habits.swift` and `ChatThread.swift` remain whole.

The driver creates a file-backed `ModelContainer` with all nine types, inserts 16 synthetic rows, saves final persistent identifiers and dependent encoded references, saves again and exits. A second process opens the same store with saving disabled and compares every persistent field and ID against the saved snapshot. Counts are ordered as follows:

| Type | Rows |
| --- | ---: |
| OneTask | 3 |
| OneEvent | 2 |
| OneAlarm | 2 |
| OneList | 2 |
| Habit | 1 |
| ChatThread | 1 |
| LedgerEntry | 2 |
| AIGrant | 2 |
| ShareImportReceipt | 1 |

The synthetic fixture is versioned inline in `OldWriter.swift`. It covers `listName` membership, chat item IDs, decided-card item/ledger/message references, ledger Undo links, recurrence, planned time distinct from deadline, completed/nil fields, checklist IDs and states, all-day events, alarm identity/configuration, retired Habit and LedgerEntry, active/revoked grants and a share receipt. These old models have no `@Relationship` declarations. UUIDs and dates are fixed where assignable; SwiftData-generated store/row identifiers are saved and compared within each run rather than assumed reproducible across fresh stores.

## Evidence and preservation

Run evidence lives permanently under `/Users/yuanlu/code/one-app/tests/results/reconstruction/swiftdata-old/`, outside this temporary worktree. Each new run refuses an existing directory; writer mode refuses an existing store. No failure handler deletes a store. All extracted inputs, exact command arrays, logs, executable, expected/reopened snapshots, store and sidecars remain as raw files. Their paths, SHA-256 and sizes are indexed through the existing `tests/qa/journal.py` API in `/Users/yuanlu/code/one-app/tests/results/activity.sqlite`. `result.json` is the complete per-run artifact manifest; the versioned `evidence.json` is a compact handoff.

## Remaining acceptance gates

The evidence here establishes macOS host disk persistence under the **old implementation and module `One`**. It does not prove a source move or any replacement module compatible. Before adopting a model move, build the future reader against the **actual integrated model module**, open a copy of the complete retained store family, and compare all counts, persistent IDs, fields and decoded references against `expected.json`. Do not synthesize another model schema as a stand-in for the integrated module. Preserve the original old store and executable, including on reader failure.

An iOS old-install → integrated upgrade/relaunch journey, real app-container/store locations and physical-device behavior remain unverified. No Xcode app build, SwiftPM build, simulator, device, signing, PR or merge is part of this lane. Host persistence evidence cannot close those gates.

## Completed host run

Command: `python3 tests/swiftdata-migration/old-store.py --run-name baseline-e022a7a-05`.

Result: compile, write and independent read-only reopen all exited **0**. All 53 baseline pure files and six retained model source files compiled into module `One`; all nine reflected model names start with `One.`. The expected and reopened snapshots are byte-identical. Exact artifact hashes and toolchain details are recorded in `tests/swiftdata-migration/evidence.json` and the raw run's `result.json`. QA session: `swiftdata-old-baseline-e022a7a-05`.

Four earlier attempts remain retained and journaled: one driver compile error (missing `try`), then three failures of the initial semantic-reference checks. Focused diagnosis isolated the `Set` comparison of decoded persistent identifiers; final verification compares the complete encoded identity per ordered item and also resolves every reference through `ModelContext.model(for:)`. The exact cause of the `Set` behavior is not established. No old-model declaration changed, and full stored-field/ID equality remains required. The diagnostic artifacts are retained in `diagnosis-01` alongside the run directories.
