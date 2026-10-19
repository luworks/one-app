# Local diagnostics, privacy and licenses

Audit baseline: clean `f497c5a8c47a5b7d72944f0ba8a44106ef9d39e7`, 2026-10-18. Read together with [architecture](architecture.md) and [upstream research](upstream-research.md). This is a source audit and bounded implementation, not App Store, device, or whole-app privacy acceptance.

## LocalDiagnostics integration contract

`ios/Sources/TodayPlatform/LocalDiagnostics.swift` provides `@MainActor public final class LocalDiagnostics`. The application assembly must retain one instance and call `start()` at launch. Repeated start is idempotent; `stop()` removes the subscription. Only an explicit Settings export tap may call `try diagnostics.exportURL()` and then present the returned file through the system share sheet. It must not be called from launch, background refresh, automatic error handling or a timer. Root owns those call sites, target membership and resources; no lifecycle/Settings/project/signing change is made here.

The subscriber reads real MetricKit typed properties, synchronously on the callback queue, and transfers only immutable checked `Sendable` numeric structs to the main actor. There is no `@unchecked Sendable`, payload transfer across actors, arbitrary-key parsing, raw JSON/dictionary representation, networking, upload, stack export or OSLog archive export. `MXDiagnosticPayload` is deliberately ignored. Logs/signposts carry fixed lifecycle/export event names and a numeric received-report count. Existing `PerformanceTrace`, `AIResponseTrace`, `YearCacheTrace` and `PageResourceTrace` remain the performance probes; no launch timer, sampling loop or duplicate resource probe is introduced.

The export schema contains `schemaVersion` and `samples`. Each sample can contain only:

| Export value | SDK source | Unit / sanitization |
| --- | --- | --- |
| `cpuSeconds` | `MXMetricPayload.cpuMetrics.cumulativeCPUTime` | Converted to seconds; absent, negative or nonfinite values omitted. |
| `peakMemoryBytes` | `MXMetricPayload.memoryMetrics.peakMemoryUsage` | Converted to bytes; absent, negative or nonfinite values omitted. |
| `launchTimeToFirstDraw` | `MXMetricPayload.applicationLaunchMetrics.histogrammedTimeToFirstDraw.bucketEnumerator` | At most 64 buckets, each numeric `lowerSeconds`, `upperSeconds`, `count`; invalid ranges/nonpositive counts omitted. No fabricated average or percentile. |

At most the latest seven nonempty **reports**, not seven days, survive in memory. Missing delivery yields an empty array. No timestamps, app version, hardware/device IDs, OS metadata, titles, calendars, Health values, chat/text, source names, paths or error descriptions enter the report. Restart drops the in-memory reports. Only export writes one atomic file at the fixed app-temporary path `TodayDiagnostics/today-diagnostics.json`, replacing the previous export; iOS applies complete file protection. It is a user-requested temporary snapshot, retained until replacement/system temporary-file cleanup. A caller should share it immediately rather than retain this reusable URL for multiple concurrent share sessions. This class does not select a recipient or send the file.

Apple primary references inspected live (the installed iPhoneOS 27.1 SDK headers additionally confirm property names/types): [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager), [launch](https://developer.apple.com/documentation/metrickit/mxapplaunchmetric), [CPU](https://developer.apple.com/documentation/metrickit/mxcpumetric), [memory](https://developer.apple.com/documentation/metrickit/mxmemorymetric), [histogram](https://developer.apple.com/documentation/metrickit/mxhistogram). Apple's manager documentation describes daily on-device reports and explicitly directs testing callbacks on a **physical device**. Simulator delivery absence is unverified, never synthetic-payload acceptance. Test numeric inputs verify serialization only.

## Required-reason API inventory

The authoritative [Apple category/reason table](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [reporting requirements](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) were retrieved live. The category table's documentation JSON contains the complete enumerations (its Markdown rendition omits them). Raw references are retained in primary-checkout `tests/results/diagnostics-20261018/required.json` and indexed in QA SQLite. Reasons below are selected for actual repository use, not speculative future functionality.

| Category | Observed production use | Manifest reason |
| --- | --- | --- |
| User defaults | `Preferences`, `AppearanceLogic`, timer/stopwatch stores, `ActivitySettings`, `CalendarSync`, `RemindersSync`, `@AppStorage` settings; app-private preferences/state. | `CA92.1`: app-only values. No production `UserDefaults(suiteName:)`/shared defaults found, so no `1C8F.1`; test throwaway suites do not justify a production reason. |
| File timestamps / metadata | `ActivityStore.fileSize()` reads app-private database and WAL `.size` via file attributes. SQLite's filesystem accesses also require final binary inspection. | `C617.1`: app/app-group container file size/metadata. No user-selected arbitrary-file timestamp or timestamp-display reason is claimed. |
| System boot time | Existing `DispatchTime.now().uptimeNanoseconds` elapsed-event measurements in `PerformanceTrace`, `AIResponseTrace`, `YearCacheTrace`, `CalendarView`; DEBUG `PageResourceTrace`. Direct `ProcessInfo.systemUptime` appears in UI test files only. Dispatch's monotonic uptime is treated conservatively as underlying boot-time access, not a newly added probe. | `35F9.1`: elapsed time between app events/timer calculations. New diagnostics export contains none of the existing raw uptime values. |
| Available disk space | No `statfs`, `statvfs`, `volumeAvailableCapacity*`, `volumeTotalCapacity`, `systemFreeSize` or `systemSize` use found in Swift/C/ObjC repository source. Database file size is not volume free space. | Not declared. |
| Active keyboards | No `activeInputModes` use found. | Not declared. |

`ios/PrivacyInfo.xcprivacy` declares tracking false, no tracking domains and no developer-collected data categories for this local-only path. This is not a privacy entitlement or a claim that an integrated archive was audited. Root must include the manifest in every executable/library bundle that actually needs it, review the generated per-bundle report and linked SDK manifests, and repeat the source/binary audit after moves/dependency integration. Shared extensions currently contain no direct defaults/uptime/metadata calls identified by this audit; framework/runtime implementation and actual resource membership remain archive-level gates. Do not add a reason merely because another bundle declares it. Root must check any future network/data collection against App Store disclosures separately.

### Existing out-of-lane findings

New diagnostics are sanitized; the application as a whole is **not yet** certified sanitized. `EntryActions.swift:70` publicly logs `entry.title`; `CalendarSync.swift:315,322,350` logs event/calendar/source titles, and `:279` logs an event identifier. Error paths in CalendarSync/HealthKitSource log localized errors publicly; `TodayCore/HealthLoading.swift` logs metric names publicly. `RemindersSync.debugLog` emits personal titles under DEBUG. `HealthDebugSeed` logs selected metric names under DEBUG. These existing writers are root-owned; remove/redact them before claiming a whole-app sanitized logging boundary. Diagnostics export never reads them. Existing performance console logs include raw uptime; `35F9.1` does not authorize exporting raw boot-time signals (only elapsed app-event durations have its off-device exception).

## Permissions and Release boundary

Source inventory, not generated/archive Info.plist proof:

- Both app configurations currently set `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSHealthShareUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` in the Xcode project. Widgets also declare calendar access. `ios/OneInfo.plist` contains `NSAlarmKitUsageDescription` and `NSLocationWhenInUseUsageDescription`. This lane leaves the existing English copy unchanged.
- `HealthKitSource.requestAuthorization(toShare: [], read: …)` is live read-only access. No diagnostics path receives Health samples. `HealthDebugSeed.swift` is entirely `#if DEBUG`; its explicit `-seedHealth` hook requests sample write access and saves fake samples. Its `OneApp` call is also DEBUG guarded. `NSHealthUpdateUsageDescription` currently exists in the Debug configuration only, with test-only seeding copy. Root must preserve this exclusion in generated Release settings and verify the archived executable/resources.
- Notifications request authorization through UserNotifications rather than an invented usage-description key. Location/MapKit travel routing and speech are existing product system-service paths; the diagnostics lane adds no permission or external request. Review their actual service behavior independently of the local diagnostics claim.
- `ios/One/Localizable.xcstrings` is an empty English source catalog foundation. No new keys, translations or product copy changes. Root wires membership and future exact English extraction.

## Licenses and resource obligations

Production app source is [MIT](../../LICENSE), copyright 2026 luworks. Preserve its copyright and permission notice when distributing copies/substantial portions. MIT does not relicense third-party resources.

The production World Clock city database derives from [GeoNames](https://www.geonames.org/export/) under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), as recorded by `scripts/build_cities.py` and the existing README/picker credit. Retain attribution to GeoNames, its URL, the license link and an indication of modifications: Today filters/transforms source data into the bundled city list and incorporates selected alternate names. Do not imply endorsement. Root must preserve that visible credit and include the complete applicable notice/license link with the shipped resource; this document alone does not prove that the generated app bundle includes it.

Tool/source-license evidence and exact dated pins live in [upstream research](upstream-research.md) and its primary license links. Keep the following scopes distinct:

| Component | License / obligation | Allowed placement |
| --- | --- | --- |
| SnapshotTesting | [MIT](https://github.com/pointfreeco/swift-snapshot-testing/blob/1.19.6/LICENSE); retain notices with redistributed copies and account for any actual transitive dependencies. | Test targets only; no Release dependency/resource inclusion. |
| XcodeGen, SwiftLint, fastlane, mise, Ruff, actionlint | MIT per linked upstream license files in research; preserve bundled third-party notices (including Ruff's). | Development/CI tools only; inspect actual redistributed binary archives independently. |
| Apple/Swift swift-format | [Apache 2.0 with Swift runtime exception](https://github.com/swiftlang/swift-format/blob/604.0.0/LICENSE.txt); retain license/required notices and modification notices when redistributing. Bundled Xcode executable version is not assumed equal to this source tag. | Tooling only. |
| Element X | [AGPL / commercial boundary](https://github.com/element-hq/element-x-ios/blob/734c0678fa2affe485746126458fca888639e608/LICENSE); file headers can say AGPL-3.0-only OR LicenseRef-Element-Commercial. | General architecture concepts only; no copied source/assets/tests. |
| IceCubes | [AGPL v3](https://github.com/Dimillian/IceCubesApp/blob/98098b9c4b5928f89f338203193c2bf40ab7f38c/LICENSE). | General concepts only; no copied source/assets/tests. |
| isowords | [Custom license](https://github.com/pointfreeco/isowords/blob/main/LICENSE.md), not MIT; commercial whole-app reuse restricted. | Ideas only; no source, assets, snapshots or tests copied. |

No upstream code is copied in LocalDiagnostics. Root owns final dependency graph, app notices UI/resources and Release resource inspection. No license compatibility claim substitutes for checking actual distributed material.

## Verification and evidence

Run `python3 tests/diagnostics/run_checks.py`. It acquires the existing nonblocking shared dev-host lock, compiles the production file plus host-only checks with Swift 6 complete concurrency checking and warnings as errors, runs serialization/export data checks, then typechecks that production file against the installed iPhoneOS SDK. It uses no Xcode build, simulator, signing, network delivery or app launch. Lock contention stops immediately. Raw command logs/executable and Apple references stay under primary-checkout `tests/results/diagnostics-20261018/`, with hashes indexed through `tests/qa/journal.py`. The host-only check source is durable in `tests/diagnostics/SerializationChecks.swift` (small inline numeric cases, no external fixture required).

Host checks cover unavailable/invalid values, bucket validation, retention bounds, unit-preserving numeric output, nested text rejection, stable JSON and actual explicit local-file export with empty delivery. They do not fabricate SDK payloads or claim callback acceptance. See [bounded evidence](../../tests/diagnostics/evidence.md) for the observed outcome and remaining gates.
