# Exact old SwiftData writer

Run from any working directory:

```sh
python3 tests/swiftdata-migration/old-store.py --run-name YOUR_NEW_UNIQUE_NAME
```

This lane uses one `xcrun swiftc -j 1` process, not SwiftPM or an Xcode app build. It requires macOS with an Xcode toolchain containing SwiftData, SwiftUI and the `#Index` macro. No simulator, signing or device is involved.

`source-lock.json` pins baseline `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`, every baseline input SHA-256, model extraction boundaries and extracted SHA-256. The extractor reads both pure-source target lists from that baseline's `ios/Package.swift`; it does not use the checkout's current app sources. All pure files are compiled unchanged. Model files are also unchanged, except the explicitly bounded exclusion of the `Capture` extension in `Models.swift` and truncation of `Ledger.swift` before the `Ledger` enum and its leading comment. Supporting declarations within those retained spans remain exact. There are no shadow model definitions. Never regenerate the lock to accommodate a source mismatch without investigating it.

`OldWriter.swift` is the durable synthetic fixture/driver. It compiles alongside these exact declarations in **module `One`**. The writer uses a file `ModelContainer` containing all nine old schema types. Its 16 rows exercise populated and nil/default fields, list-name membership, final persistent identifiers, chat item/card references and message anchors, recurrence, distinct planned/deadline/completion dates, checklist IDs and completion, event/alarm fields, both retired models, active/revoked grants and a share receipt. UUIDs and dates are fixed where the old types allow assignment; SwiftData chooses store UUIDs and persistent row IDs, which are captured after save. This schema has no SwiftData `@Relationship` properties; its relevant relationships are names and encoded references.

The executable first saves the fixture and writes `expected.json`, then exits. A second process opens the same file read-only (`allowsSave: false`), checks counts and semantic links, fetches all persistent fields and IDs, writes `reopened.json`, and requires byte equality with the sorted expected snapshot. No source replacement, in-memory container or same-context reopen substitutes for the disk test.

Each run creates a new directory under `/Users/yuanlu/code/one-app/tests/results/reconstruction/swiftdata-old/`. Existing run directories, stores and expected snapshots are refused, never deleted or reused. The directory retains the executable, all extracted sources, copied driver, exact command arrays, logs, snapshots, actual store/sidecars and a hash manifest. The existing QA journal API indexes every completed artifact in `/Users/yuanlu/code/one-app/tests/results/activity.sqlite`. Do not move or prune this directory during worktree cleanup. Only code, input hash lock and compact evidence are versioned.

A future integrated-module reader must use a **copy of the entire completed store family** and compare against `expected.json`; keep this original writer/store intact. This harness establishes macOS old-writer persistence only. Integrated new-reader compatibility, iOS upgrade/relaunch, app-container locations and physical-device acceptance remain separate gates; see `docs/engineering/swiftdata-upgrade.md`.
