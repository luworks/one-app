# Reconstruction baseline

## Actual source and host

On entry the integration worktree was clean at `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`, branch `t3/today-ios-reconstruction`. The primary checkout was at the same commit. The first checkpoint adds ownership documentation only. Actual commands reported Xcode **27.1 / 27A9275**, Apple Swift **6.4 / swiftlang-6.4.0.34.1**, arm64 host. Deployment is iOS **27.0**. Installed simulator runtime is iOS 27.0; SDK version is resolved separately by Xcode. No CI runner availability is inferred from this Mac.

Raw captures live in primary `tests/results/reconstruction/baseline/`: `source-fingerprint.json`, original `project.json`, `target-contracts.json`, resolved Debug/Release settings, test inventory, command timing JSON and unfiltered build/test logs. This is synthetic development evidence; it contains no exported app user database. The Activity-style QA journal indexes development actions separately from app Activity.

## Existing graph

| Target | Product / module | Identity | Source membership |
| --- | --- | --- | --- |
| One | One.app / One | com.luworks.one | One + Shared |
| TodayWidgets | TodayWidgets.appex / TodayWidgets | com.luworks.one.widgets | TodayWidgets + Shared |
| ShareExtension | ShareExtension.appex / ShareExtension | com.luworks.one.share | ShareExtension + Shared |
| OneUITests | OneUITests.xctest / OneUITests | com.luworks.one.uitests | OneUITests |

The app embeds both extensions. All production targets retain the existing automatic signing configuration and team; no account, certificate or identity setting was changed. App has HealthKit and App Group entitlements; both extensions have the same App Group `group.com.luworks.one`. No explicit Keychain access group exists in these entitlement files. The narrow shared format boundary is JSON widget snapshot/share inbox and JSONL Activity outbox; extensions do not open SwiftData or app Activity SQLite.

The hand-maintained project uses synchronized source folders. The app graph has 141 Swift inputs (including seven Shared files), 11 resource entries (asset catalog, String Catalog, city JSON, eight CAF tones), and two embedded extensions. Widgets have 10 Swift inputs; Share has eight; UI tests have 60. Original production Swift language mode is **5.0**, independent of the installed Swift 6.4 compiler. No external SPM dependency exists. `ios/Package.swift` separately recompiles a manual pure-source whitelist into OneLogic/OneShared; these are not linked production modules yet.

## Compatibility boundary

Preserve bundle IDs above, module identity `One` for SwiftData models, all nine schema types (`OneTask`, `OneEvent`, `OneAlarm`, `OneList`, `Habit`, `ChatThread`, `LedgerEntry`, `AIGrant`, `ShareImportReceipt`), field defaults and serialized values. `Habit` and `LedgerEntry` remain retired compatibility models. Default SwiftData location/configuration, application-private `Application Support/Activity/activity.sqlite`, App Group files `widget-snapshot.json`, `share-inbox.json`, `activity-outbox/`, defaults keys, `today://` links, shortcut IDs and background ID `com.luworks.one.widgetRefresh` must not change as a rename side effect. Storage characterization records exact keys/shapes separately before any model move.

## Initial checks

Source discovery found **75 logic XCTest suites / 661 methods**, **59 UI suites / 319 methods**. Discovery is not execution. Actual baseline `swift test --jobs 2` exited 0 in **33.756 s**, with **661 executed, four skipped, zero failures**; XCTest runtime was 7.383 s. Capture eval printed train 46/46 and test 22/22. The separate Swift Testing footer had zero tests because no Swift Testing declarations existed; it does not invalidate the 661 XCTest executions.

The original generic simulator Debug build, jobs 2 and an isolated cache, exited 0 in **84.719 s** (arm64 and x86_64). It compiled the app and embedded extensions, with existing owned warnings retained in the raw log. This is build evidence; no simulator was booted and no UI journey or physical-device behavior was exercised. Additional original/generated Release and generated Debug comparisons are pending until their command records close.

## Generated entry equivalence checkpoint

`ios/project.yml` and versioned `ios/Config/*.xcconfig` reproduce the original explicit settings with XcodeGen 2.46.0 (official release ZIP SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`). Today/TodayUITests/TodayShare are developer target names; product/module names remain explicit for compatibility at this checkpoint. The old project remains available until actual output checks pass.

`compare_settings.py` compared 2251 resolved Debug and 2235 resolved Release setting entries across all original/generated targets with no differences after documented developer-name/build-path normalization. The full before/after JSON is retained. `compare_project.py` found identical source/resource sets, product types and extension output references. This caught and corrected an initial generated extension-reference mismatch before any old entry was retired. Settings/graph equivalence does not establish binary or runtime equivalence; generated build/output gates follow.
