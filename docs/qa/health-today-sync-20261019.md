# Health sheet → Today synchronization

## Baselines and scope

- Worktree started clean at `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c` and fast-forwarded to current main `c513fe3b12d97c28283f4f88f69dd4f5304f6a04`.
- Phone rollback `9043647676383a4f0839fc1bbcb156fc47189d10` was characterized through `git show` only. No phone access, installation, permission change or HealthKit writes.
- `TodayHealthLine.swift` and `App/OneApp.swift` are byte-identical between 904 and c513. Both assemble separate `HealthLineModel` (cached formatted text, 7-day reads) and `HealthModel` (sheet series, longer chart reads), sharing only the source, selection store and access gate. Opening the sheet calls `HealthModel.load`; dismissing it does not reload the Today line. This is source evidence, not an execution of 904.
- Main's Health changes add the global ordered dashboard, optional record reads and cancellation-state settlement. They retain the separate summary state.
- Synthetic fixture `tests/fixtures/health-today-sync.json` drives one `SequencedHealthSource` through the existing Mock assembly. First Steps query returns 1111; subsequent queries return 2222. The production views and state code are used unchanged for RED. This establishes app synchronization behavior, not actual HealthKit sample delivery.

## Evidence

Persistent root: `/Users/yuanlu/code/one-app/tests/results/health-today-sync-20261019`.
Source SHA-256 fingerprints: `source-fingerprints.json`.
The QA SQLite journal session is `health-today-sync-20261019`; native runner sessions separately index complete xcresults and raw logs.

## First RED

`./dev test ui --only TodayUITests/HealthMetricsTests/testHealthUpdateReachesTodayWithoutReopeningApp`
ran against c513 plus the test-only source/fixture (production state unchanged). Native build succeeded; one UI test failed at the final expected-2222 assertion, after Health's 2222 assertion passed. Runtime 216.607 seconds including the first build; test itself 30.331 seconds.

Full parseable bundle: `tests/results/runs/today-qa-20261019-181622-e27a0262/ui.xcresult`; raw `ui.log`, parsed `summary.json`, screenshots, AX hierarchy and recording retained. Exported attachments are in `health-today-sync-20261019/red-attachments` with manifest. The source sequence can reach 2222 only on the second Steps query; raw app stdout was not included (`xcresulttool get log --type console`: `No console log available`). Explicit synthetic query tracing was added for GREEN rather than inventing console evidence.

The RED Health screenshot shows 2222 Steps; returned Today screenshot and hierarchy show `health.summary`, label `1,111 steps`. This is the reported app-level divergence, with synthetic values only.

## Focused review

One read-only review found that treating a previously loaded long chart as permanently fresh would suppress later foreground refreshes. That intermediate implementation is corrected by keeping existing explicit lifecycle reads lightweight, while rendering/dismissal derives shared state without fetching. Native model tests cover that later short refresh retaining older history, as well as a late old short query rejected after a newer long-window result.

## Change and resource behavior

`HealthLineModel` now holds only the exact `HealthModel` constructed by App/SceneCatalog. Its computed line formats the shared selection/series/units; it starts no query. Health sheet results and Today therefore have the same per-metric owner and generation. Removing the separate selection notification loader also removes its redundant fetches.

The existing Today lifecycle task still performs at most two seven-day metric reads, skipping a metric whose read is already active. Sheet dismissal only reveals derived state. Short refreshes replace their covered dates while preserving older points inside the largest previously loaded window. All reads retain existing asynchronous HealthLoader access/query timeouts, optional HealthQuerySource failures and cancellation behavior. Older generations cannot publish either values or window completeness.

The existing detail request is `HealthModel.days = 180` (chart/trend lookback), rather than a newly introduced 90-day request. The synthetic Steps-only UI source trace records exactly two reads, 7 then 180 days, with the same UUID. No poller, background entitlement, service, observer bus, database, capability, signing or production Health-write change was added.

Native logic verification uses the production HealthModel in `PlannerSessionTests` extensions in `ios/TodayIntegrationTests/HealthSummaryIntegrationTests.swift`:

- `healthSheetUpdateSharesSummaryAndPreservesLongHistory`: 1111 short read → 2222 long read; formatting adds no query; a later explicit lifecycle short read returns 3333 and retains an 80-day historical point.
- `healthLateShortReadCannotOverwriteNewLongWindow`: newer long result arrives before an older short result; both presentations retain 2222 and the older historical point.

`./dev test integration` selected these exact two methods. Both passed, 2 executed / 0 missing / no skips. Full native bundle/report: `tests/results/devtools/logs/fe049ba7ae854c20a3aa3ae10380c17b-xcode/TodayTests.xcresult` and `TodayTests.report.json`.

The first attempt to select a new standalone suite was rejected by the existing integration group (no execution). Tests were placed in the already-authorized PlannerSessionTests suite rather than changing the CI/test manifest.

An intermediate UI batch proved the synchronization journey GREEN (27.019 s), then was explicitly interrupted while the unrelated existing Sleep context-menu check waited for XCTest idle. Its native menu screenshot and raw logs remain under `tests/results/runs/today-qa-20261019-182148-7e3d7efb`; this batch is not claimed as passed or a completed full-bundle acceptance. No assertions or product animation were weakened.

## UI product identity blocker and correction

A later final-source UI attempt (`today-qa-20261019-182624-34d465c2`) failed before the first A assertion. AX showed Apple's Health permission sheet and a live wall clock; launch fixtures were ignored. Actual installed product was `One.app` / executable `One`, hash `1c4c76867f098782ec5912c01332e40ef102a3ab71f39bf477f3a9ce29f08475`, matching the live product. Expected Mock executable hash was `6f2a1689f3b653cf2bed86021bc34cb6701da657b0ed041bbbab4f2af1f38c86`. This is not a synchronization failure or GREEN acceptance.

The generated TodayMock xctestrun explicitly selected `TodayMock.app`, but its `DependentProductPaths` contained both `One.app` and `TodayMock.app`, which share the bundle ID. The production target was intentionally present in the scheme. It remains present: no project manifest, CI workflow/policy or signing change.

CI owner v24 released the exact runner/provenance/test hunks. The correction removes only the exact sibling Live `One.app` from the known UI target's installation dependencies, before source/toolchain/product provenance is recorded. Wrong UI app paths, unexpected app siblings, missing Mock module/composition or compilation condition fail closed. Routine UI now uses the existing `ensure_test_products` → `test-without-building` path. Before dispatch, it verifies provenance, installs the exact Mock path, and compares installed executable/payload hashes with the verified product. `mock-product.json` retains source fingerprint, configuration hash, declared `TODAY_MOCK` condition, linked Mock composition/module, exact runner/app paths and installed binary identity.

Meaningful host fixtures retain both compiled-product stand-ins, select only the Mock installation closure, reject a Live target / unexpected sibling / disguised Live payload / missing Mock condition, preserve provenance, and reject wrong installed identity before dispatch. Existing cold/cached/timeout tests remain intact. `./dev test helpers`: 154 passed, 11.518 seconds. Initial helper failures were two old synthetic lifecycle fixtures missing the new identity boundary; their common fixture was adapted once and a negative dispatch case added.

## Final GREEN and boundaries

Final run `today-qa-20261019-183523-3b034336` uses verified installed `TodayMock.app`, module `TodayMockApp`, source fingerprint `0acc7380e5f801b6ec237a2a6e59d953536936189fd23cda65763b039f241ac3`.

- `testHealthUpdateReachesTodayWithoutReopeningApp`: passed, 22.929 seconds. Native screenshots/AX: Today 1111 → Health 2222 → Done → Today 2222.
- `testSettingsOpensTheSameSheet`: passed, 24.192 seconds.
- Final synthetic trace UUID `0F2B766B-0FFD-4669-AA64-791F9E31958B`: query 1, 7 days, 1111 at 01:36:33 UTC; query 2, 180 days, 2222 at 01:36:39 UTC. No third metric query on dismissal. Query scope was Steps only.

Completed full copies of RED/GREEN/model xcresults, raw UI logs, reports, extracted screenshots, query trace, product identity receipt and source hashes are retained in the primary evidence root. The journal indexes these artifacts by path/hash; original runner directories remain intact. No live bundle was moved or finalized.

This proves application state synchronization with an injected deterministic source and native SwiftUI presentation. It does not prove native HealthKit delivery or physical-device behavior. Phone rollback 904 and all phone Health data/permissions remain untouched. Main's separate usability/install gate remains the root owner's acceptance responsibility; this branch does not authorize a phone installation. No full UI suite was run.

Final static checks: `./dev format --check` and `./dev lint` passed. The formatter only wrapped/indented the four changed Swift files after native tests; no logic changed and passing functional tests were not repeated for formatting. `ui-tested-source-hashes.json` and `final-source-hashes.json` distinguish those exact byte variants; the tested Mock receipt is not asserted reusable after formatting. Normal provenance validation will require matching current sources before any later native dispatch. This is not final integrated-main or phone-install acceptance.

## PR122 required CI failure at 88b0f94

Hosted run `39354744329`, job `118406845309`, failed on PR head `88b0f9425a2e773af82646b1742259b8da71b8be` (integrated merge source `f29a680b2db806fae8cb5d2bbdadeb9ee0e67c8f`). Helpers passed; format/lint and 701 business checks passed. The native build command exited 0 in 91.874 seconds, but the build adapter rejected its installation dependency closure with `ValueError: Ambiguous Live/UI installation dependency`. Native tests executed: 0. Neither discovery nor a Health synchronization assertion ran.

The original job log and artifact ZIP are retained under the primary evidence root as `ci-39354744329-job-118406845309.log` and `ci-39354744329-artifact.zip`. ZIP SHA-256 `f35c5903e6f31757340199322cf1c2c81d357e7d7696c2c927dc634661eb6067` matches GitHub's upload digest. Extracted failed structured reports and manifests remain in `ci-39354744329/`. The hosted upload contains no raw native build log, xctestrun or xcresult; those missing files are not claimed as retained remote evidence.

A local diagnostic using the same TodayCI scheme reproduced the exact rejection after a successful 80.590-second build. Raw build log and the unnormalized xctestrun are retained in `local-ci-dependency-red/`. This plist repeats all three targets' aggregate dependencies in each target, including `TodayTestHost.app`, the isolated host for TodayTests and TodaySnapshotTests. The original guard allowed only Mock and its UI runner, so it incorrectly rejected that declared native test host. This is an observed combined-scheme issue, not an inferred recurrence of the earlier wrong-Live launch.

The narrow correction accepts the exact isolated host only when a known native test target declares it, validates its executable/bundle identity, and compares dependency paths after resolving the supported TESTROOT/TESTHOST tokens. Equivalent paths to the same owned product are canonicalized and deduplicated. Foreign paths, missing products, symlinked products, unknown app siblings, incorrect native host identity and a Live UI target remain rejected. The pre-existing normalization still removes only the known sibling Live product from the UI installation closure; ordinary validation rejects an unnormalized Live/Mock mixture. No workflow, scheme, project manifest, signing or app source changed.

`./dev test helpers`: 156 passed in 12.353 seconds, including the actual three-target closure regression and paired same-Mock aliases versus distinct Live/foreign/symlinked paths. Existing stale source/product and installed identity regressions remain passing. The source changes invalidate earlier product provenance; the subsequent native UI run must build/validate against the updated fingerprint.

The corrected guard was verified through `TODAY_CI_SYNTHETIC=1 TODAY_CI_NATIVE_BATCH=1 ./dev test ui` with only the two original Health methods. Completed run `today-qa-20261019-185050-6ffaaa2b` used `TodayCI_iphonesimulator27.1-arm64.xctestrun`, rebuilt successfully in 9.634 seconds, and completed in 116.033 seconds:

- `testHealthUpdateReachesTodayWithoutReopeningApp`: passed, 22.718 seconds.
- `testSettingsOpensTheSameSheet`: passed, 26.156 seconds.
- Native xcresult authority: 2 expected, 2 executed, 0 missing, 0 skips. Owned simulator `324064A3-ABF7-4CEE-96FB-15C4B1054850` shutdown succeeded.

`todayci-guard-green/` retains the complete finished run (including parseable `ui.xcresult`, raw build/UI logs, screenshots/AX, installed Mock identity receipt, summary) and normalized combined xctestrun. Installed executable SHA-256 `792d7e36acf79f5ec99b263c880d59fd09b6bfb93dd873b1240ca7723bd4f568`, payload SHA-256 `c75592a93354cfc8a14e631108e13fb1aa2ccc82d3c2b6c958795e6b2c878d3b`, source fingerprint `2f156857580fe75007f1d9dc41fbd918e5adf07021eeb10ef0f74401bb5f2daa`. `guard-tested-source-hashes.json` records the exact tested runner/test bytes; no source changes followed this run. This is local combined-scheme UI proof, not hosted CI, integrated-main or physical-device acceptance. The earlier 2/2 model result remains the app-state logic evidence; no app logic changed in this guard repair.
