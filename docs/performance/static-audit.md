# Static package size and redundancy audit

Snapshot: tracked inputs at `c42b88e6712882f1d627d68d5769913d959bc72c` (2026-10-18); concurrent untracked work is outside the baseline. Read-only inspection of app inputs; this document is the only file written. Read `AGENTS.md`, `CLAUDE.md` and `ios/README.md` first. No build, test, simulator, archive inspection, audio playback or production optimization was performed.

## Interpretation and method

All byte counts below are exact logical file lengths from the checkout, not allocated disk blocks, compiled code, `Assets.car`, localized output, compressed IPA, download size or installed size. Enumerated tracked files with `git ls-files`; checked the live four production source directories against that inventory (same counts and byte totals). Used Python `stat`, JSON parsing, SHA-256 over complete files and CAF audio payloads, and source/call-site inspection. No external research was needed. Source references below are repository-relative paths and line numbers at this revision.

**Result:** audio dominates source resource inputs; no identical production files or audio payloads were found. Shared source membership is broader than each extension's directly observed callers. Several test-only runtime paths are not compile-time excluded from Release. None of those facts establishes a removable installed-byte total.

## Production resource inventory and reachability

The four production directories contain **153 files / 6,829,534 bytes**: **139 Swift files / 1,389,903 bytes** plus **14 non-Swift resource inputs / 5,439,631 bytes**. The latter all live in `ios/One`; neither extension nor `Shared` has its own resource files.

| Resource input | Files | Bytes | Membership and static reachability |
|---|---:|---:|---|
| `ios/One/Sounds/*.caf` | 8 | 5,280,736 | `One` synchronized directory; all eight names occur in `AlarmSound.all`; picker, preview and AlarmKit scheduling consume them |
| `ios/One/cities.json` | 1 | 113,375 | `One`; `CityDatabase.shared` loads this exact bundle resource for World Clock |
| `ios/One/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1 | 42,214 | App icon selected by build setting and catalog filename; 1024×1024 source entry |
| Asset catalog `Contents.json` files | 3 | 815 | Root 63; AccentColor 541; AppIcon 211; compilation metadata, not three additional images |
| `ios/One/AppShortcuts.xcstrings` | 1 | 2,491 | App Shortcuts phrase catalog, 10 keys with 10 `zh-Hans` translations, English source language |
| Custom fonts | 0 | 0 | No tracked TTF/OTF/WOFF/WOFF2; no `UIAppFonts`, `.custom(...)`, `UIFont(name:)` or CTFont registration found in production sources/plists |

References: `ios/One.xcodeproj/project.pbxproj:60–86,143–173,418–480`; `ios/One/AlarmSounds.swift:7–23,32–39`; `ios/One/AlarmEditor.swift:338–360`; `ios/One/Ringer.swift:218`; `ios/One/WorldClockView.swift:3–9,30–37,337`; `ios/One/Assets.xcassets/AppIcon.appiconset/Contents.json:1–13`; `ios/One/AppShortcuts.xcstrings:1–104`; `ios/One/AppIntents.swift:68–94`. AccentColor has light/dark variants in its catalog and is selected by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`; it is not an unreferenced image.

### Audio: verified distinct, already compressed

Audio is **97.08% of resource source bytes**. Every file is **660,092 bytes**, mono **44,100 Hz IMA4**, with **1,234,800 valid frames (28 seconds)**, verified by parsing CAF `desc` and `pakt` chunks. The generator independently specifies 44,100 Hz, 28 seconds and `afconvert -d ima4` (`ios/Tools/make_alarm_sounds.py:11–13,80–108`). Equal duration and container size do not establish duplicate sound content.

| File in `ios/One/Sounds/` | Bytes | SHA-256 prefix (16 hex) |
|---|---:|---|
| `Beacon.caf` | 660,092 | `9455a14bd3468a2a` |
| `Chimes.caf` | 660,092 | `3fbff1f5e42b4c74` |
| `Crystal.caf` | 660,092 | `4a19273ddd6014ff` |
| `Daybreak.caf` | 660,092 | `ce7fedb84e4e3fed` |
| `Glass.caf` | 660,092 | `266ca0a70a901b32` |
| `Marimba.caf` | 660,092 | `644608a20f9167d3` |
| `MorningPiano.caf` | 660,092 | `d0f2f24de2c2e2fa` |
| `Ripple.caf` | 660,092 | `f346f74136ea0cad` |

All eight full-file hashes and all eight encoded audio-payload hashes are different. This proves byte distinction, not perceptual distinction. Each CAF contains a `free` chunk with **3,880 bytes** of payload (**31,040 bytes** across eight files; **31,136** including their 12-byte chunk headers). This is verified container padding, not a duplicate tone. Repacking compatibility, archive compression effects and actual savings remain unverified; no files were changed. Both alarm and timer flows share the one tone library rather than separate copies (`ios/One/AlarmEditor.swift:338`, `ios/One/TimerPicker.swift`, `ios/One/TimerController.swift`, `ios/One/Ringer.swift:218`).

### Cities and localization: repeated values are not duplicate records

`cities.json` is a compact JSON array of **952 records**, **952 distinct GeoNames IDs**, **940 distinct English names** and **286 distinct time zones**. There are **zero exact repeated JSON records**, 11 repeated-name groups (12 extra records) and 92 repeated-zone groups (666 extra records). Multiple cities legitimately share names or zones. Identity is the GeoNames ID (`CityRecord.key`); search uses city names, Chinese names, countries and time zones. The coordinates/rank/capital/name fields are decoded, and some support sorting and display. No field is classified unused from this inspection. Removing repeated-zone records would change selectable cities and saved `g<ID>` resolution.

References: `ios/One/CityDatabase.swift:3–40,58–84,108–155,160–189`; `ios/One/WorldClockView.swift:3–9,337–509`; generator `scripts/build_cities.py:115–156`; attribution `ios/README.md` Credits. Source is already serialized with compact separators; reduction through whitespace removal is not supported by evidence.

Only one string catalog and no tracked `.strings`, `.stringsdict` or `.lproj` trees were found. Project regions are `en`, `Base`, `zh-Hans` (`project.pbxproj:274–281`); those region labels are not separate packaged translation copies. `SWIFT_EMIT_LOC_STRINGS = YES` is set on product targets, so catalog input size is not a bound on generated localization/App Intents output. The complete UI localization coverage and generated output were not measured. Repeated English/Chinese strings and Chinese city names serve separate identities and are not established redundant payloads.

## Target membership, extensions and dependencies

**Important:** explicit Sources/Resources/Frameworks phase arrays are empty because this project uses `PBXFileSystemSynchronizedRootGroup`. All four product source groups and `Shared` are synchronized; there are no membership exception sets, source exclusion lists, shell resource-copy phases or custom build rules in the checked-in project. Thus an empty Resources array is not evidence that audio/cities/catalogs are excluded. The resource assignment is inferred from synchronized membership and recognized file types; only a built product could confirm emitted layout.

| Target | Own directory files / bytes | Additional membership | Package role |
|---|---:|---|---|
| `One` | 142 / 6,757,751 | All 7 `Shared` Swift files | App; embeds both `.appex` products |
| `TodayWidgets` | 3 / 24,437 | All 7 `Shared` Swift files | Next Up widgets and AlarmKit Live Activity |
| `ShareExtension` | 1 / 6,019 | All 7 `Shared` Swift files | Text/URL Share sheet reminder capture |
| `OneUITests` | 45 / 376,262 | Only own group | UI test bundle, not embedded by app copy phase |

References: `ios/One.xcodeproj/project.pbxproj:9–49,60–136,143–242,290–355,510–617`; `ios/TodayWidgetsInfo.plist:5–10`; `ios/ShareExtensionInfo.plist:5–23`. `One` has target dependencies on both extensions and an Embed Foundation Extensions phase, so extension executables contribute to eventual app size even though their source directories are small. `SKIP_INSTALL = YES` for extensions does not negate embedding. `OneUITests` depends on the app, not the other way around.

### Shared-source overlap

Every row below is an input to **all three production targets**. `Shared` totals **41,327 bytes**, or **123,981 source-byte incidences across three targets** (82,654 more than storing it once). These are compile-input counts, **not** replicated binary bytes or a savings estimate. No separate shared framework is embedded. Dead stripping, Swift metadata and App Intents extraction can affect what remains.

| Shared file | Source bytes | Observed consumers beyond app | Reachability assessment |
|---|---:|---|---|
| `ActivityOutbox.swift` | 3,547 | Widget refresh; Share submission | Direct calls in both extensions |
| `AlarmActivity.swift` | 2,066 | Widget Live Activity metadata and buttons | App + widget direct; no Share call found; conditional on `canImport(AlarmKit)` |
| `LockScreenNext.swift` | 6,122 | Widget rectangular model | App shared membership; widget direct; no Share call found |
| `NextUpSpeech.swift` | 1,493 | No extension direct caller found | App Siri speech caller; broad extension membership is verified, retained symbols unknown |
| `ShareInbox.swift` | 8,971 | Share capture draft/submit/due | App + Share direct; no widget call found; also includes generic `ShareImport` implementation |
| `TravelTime.swift` | 7,275 | Widget leave-time display and `WidgetItem` formatting | App + widget direct/transitive; no Share call found |
| `WidgetSnapshot.swift` | 11,853 | Widget snapshot loading, selection, links | App + widget direct; no Share call found |

References: synchronized memberships `project.pbxproj:161–164,207–210,230–233`; `ios/ShareExtension/ShareViewController.swift:14–20,73–109`; `ios/TodayWidgets/TodayWidgets.swift:34–66,92,161,298–313`; `ios/TodayWidgets/AlarmLiveActivity.swift:13,192–201`; `ios/Shared/WidgetSnapshot.swift:42`; `ios/One/AppIntents.swift` (`NextUpSpeech` caller). “No caller found” is a scoped static observation, not proof of unusedness. Shared types can be referenced transitively or discovered by App Intents. Narrowing membership is a suspected size opportunity requiring binary/symbol evidence, not an approved deletion.

### Dependency/framework audit

No third-party Swift packages are declared: every Xcode target's `packageProductDependencies` is empty, and `ios/Package.swift` declares only local macOS eval targets with no external dependencies. No checked-in `Package.resolved`, Podfile, Cartfile, vendored `.framework`/`.xcframework`, `.a` or `.dylib` was found. Framework phases are empty; Apple Swift imports can autolink SDK libraries, so this is not “no linked frameworks.” `SQLite3` is the system module, not a bundled vendor library (`ios/One/ActivityStore.swift:1–2`). No model weight resources were found; FoundationModels is an SDK import, not an in-repository model download.

| Source scope | Imported SDK/system modules (unique within scope) |
|---|---|
| `One` | AVFoundation, ActivityKit, AlarmKit, AppIntents, BackgroundTasks, Charts, CoreLocation, CryptoKit, Darwin, EventKit, EventKitUI, Foundation, FoundationModels, HealthKit, MapKit, Observation, SQLite3, Speech, SwiftData, SwiftUI, UIKit, UserNotifications, WidgetKit, os |
| `Shared` | AlarmKit, AppIntents, Foundation |
| `TodayWidgets` | ActivityKit, AlarmKit, AppIntents, EventKit, SwiftUI, WidgetKit |
| `ShareExtension` | SwiftUI, UIKit, UniformTypeIdentifiers |

SDK/system framework bytes are **not quantified** by source import counts. Conditional imports and transitive shared sources also matter. Linked load commands, Swift runtime embedding and final framework sizes require a product inspection; none was performed.

## Release exclusions and retained sample/diagnostic paths

Debug defines `DEBUG` (`project.pbxproj:384–391`); checked-in Release configurations do not define it. The conclusions below assume ordinary checked-in Release settings, with no command-line/inherited `DEBUG` override. There is no per-configuration resource exclusion: the production resource inventory is shared by Debug and Release. `COPY_PHASE_STRIP = NO` occurs in both project configurations; Release uses `dwarf-with-dsym`, `wholemodule`, `ENABLE_NS_ASSERTIONS = NO` and no explicit Swift optimization-level/dead-strip override (`project.pbxproj:397–414`). These settings alone do not establish that dSYMs ship or that the final executable contains all source declarations.

| Input / path | Source bytes where separable | Release assessment and evidence |
|---|---:|---|
| `One/TestDataset.swift` | 5,008 | Entire file guarded `#if DEBUG` (lines 1–121); caller guarded in `HomeView.swift:320–328`; dataset is supplied by path, not app resource membership |
| `One/CalendarDemoSeed.swift` | 4,918 | Entire file guarded `#if DEBUG` (1–85); calendar debug hooks guarded in `HomeView.swift:330–342` |
| `One/DevImport.swift` | 5,087 | Entire file guarded `#if DEBUG` (1–120); import caller guarded in `HomeView.swift:308–319` |
| `One/HealthDebugSeed.swift` | 3,192 | Entire file guarded `#if DEBUG` (1–55); caller guarded in `OneApp.swift:39–41`; Health write permission text is Debug-only in project settings |
| Activity benchmark / legacy-row diagnostics | Mixed production file | UI and benchmark functions guarded in `ActivityDataView.swift:111–125,157–183`; legacy seeding call guarded in `HomeView.swift:346–348` |
| Timer/Recents seeding and fake-AlarmKit activation | Mixed production file | `TimerController.swift:51–92` uses DEBUG guards; not all `-uiTesting` handling in that file is excluded (e.g. line 264) |
| `One/SampleData.swift` | 2,511 | **Release reachable**: explicit `#else` calls `SampleData.insertIfNeeded` (`HomeView.swift:326–328`); first-launch events/reminders are intentional documented product behavior, not a leaked test JSON |
| `One/HealthSource.swift` + `HealthSampleSeries.swift` | 2,344 + 3,728 | **Release source paths retained**: simulator selects mock; physical-device branch can select mock on `-uiTesting`; stall wrapper is runtime gated, not DEBUG (`HealthSource.swift:11–26,35–42`); `HealthLoading.swift:248` contains the scripted wrapper |
| `One/LaunchTimer.swift` | 1,007 | Only breadcrumb print is DEBUG (15–19); `markFirstFrame` and kernel elapsed-time code remain (8–12,21–29); called unconditionally and runtime `-uiTesting` overlay remains (`HomeView.swift:361–365`) |
| Store/test override helpers | Mixed production files | `-uiTesting` in-memory store and `-uiTestingStore` temporary `.store` path both retained in `OneApp.swift:46–63`; Activity settings reset and `.activity.sqlite`/memory selection also retained (`ActivityCenter.swift:20–40`); reminder seed helper runtime gated, not DEBUG (`HomeView.swift:261–266,343`); preferences/appearance test overrides similarly runtime gated (`Preferences.swift:153–159`, `AppearanceLogic.swift:47–52`) |
| Widget placeholder/gallery samples | Mixed widget file | **Intentionally Release reachable**: placeholder and preview snapshot call `sample` (`TodayWidgets.swift:41–49,98–105`); cannot classify gallery content as unused debug fixtures |
| `Habit` and legacy `LedgerEntry` model | 593 for `Habits.swift`; Ledger mixed | Retained for SwiftData migration/schema compatibility (`OneApp.swift:61–62`, `Ledger.swift:4–10`); naming/retirement does not authorize removal |

The DEBUG-only Share persistence probe is separate from those retained store paths (`HomeView.swift:718–756`, including its `-uiTestingStore` lookup at line 734); the Activity synthetic-row seed starts under DEBUG at `ActivityCenter.swift:47–49`. Neither guard encloses `OneStore.container` or Activity store location selection.

The four entirely DEBUG-gated files total **18,205 source bytes**. This is an exclusion in compilation, not an 18,205-byte installed saving. Retained runtime test hooks above are verified source reachability findings; their binary cost and normal-user impact are unmeasured. They do not run merely because the code is present.

### Fixtures and non-product content outside app membership

| Directory / input | Tracked files | Bytes | Packaging evidence |
|---|---:|---:|---|
| `tests/fixtures/` | 9 | 133,762 | Outside every Xcode synchronized group; no copy phase references it |
| `ios/Eval/` | 101 | 912,689 | Outside product groups; includes logic tests, eval JSON and recorded outputs |
| `ios/OneUITests/` | 45 | 376,262 | Separate test target; not embedded by the app |
| `src/` | 3 | 170,492 | HTML prototype outside Xcode membership |
| `dist/` | 5 | 516,718 | Built web prototype outside Xcode membership |

`ios/Package.swift:20–25` copies only `Eval/Tests/OneLogicTests/capture-cases.json` into its macOS **test target**. The Xcode app has no package dependency on those eval targets. No production copy step for fixture JSON, web output, eval results or private developer import data was found. Repo bytes must not be reported as app bytes. External test data used through an argument is distinct from embedded resources.

## Verified findings versus hypotheses

| Classification | Finding | Supported byte statement |
|---|---|---|
| Verified | No SHA-256-identical files across the 153 production input files; no identical encoded CAF payloads | **0 verified duplicate-file bytes** in that scope; does not test perceptual or semantic duplication |
| Verified | CAF `free` padding exists | 31,040 payload bytes, 31,136 including chunk headers; package reduction unverified |
| Verified | Seven shared sources enter app + both extensions | 41,327 unique source bytes; 123,981 compile-input incidences; binary overlap unmeasured |
| Verified | Four full debug fixture/seed/import implementations are guarded | 18,205 source bytes excluded under ordinary Release compilation |
| Verified | Sample data, mock Health paths, store flags and launch probe remain reachable in Release source | Source references above; no asserted binary savings |
| Suspected only | Narrower extension membership or further compile-time gating could reduce output | Need linked symbols, App Intents metadata and compatible product behavior before sizing or changing |
| Unsupported | Same-size tones, same-zone cities, retired migration models or gallery samples are unused | No deletion recommendation follows from names, equal lengths or repeated values |

No production optimization or removal is proposed as completed. To turn this baseline into installed-size evidence, the companion artifact inspection in this baseline needs per-bundle resource sizes, linked images/symbols and compressed archive measurements, while preserving alarm choices, saved city identity, widget previews and migrations. This audit deliberately stops at static evidence.
