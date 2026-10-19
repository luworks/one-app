# Launch fixture extraction handoff

Base: `edd2210fc5b521b2b3ddf00da087ba0ec57fa985`.
This lane owns only the Appearance launch parser, Preferences launch parser, LedgerMigration legacy seed helper, the new support file and this note. Production preference keys, defaults, readers and `allKeys` are unchanged. Persistent declarations, model initializers, schema, service contracts, package/project configuration and migration/action algorithms are unchanged.

## Exact support API

Import `TodayTestSupport` at developer/test callers. `LaunchTestConfiguration` has no initializer effects or implicit process/defaults lookup.

```swift
public enum LaunchTestConfiguration {
    public static func appearanceOverride(arguments: [String]) -> Appearance?
    public static func applyPreferenceOverrides(arguments: [String], defaults: UserDefaults)
}

// Available only under os(iOS) && DEBUG; imports SwiftData and One under os(iOS).
@MainActor
extension LaunchTestConfiguration {
    package static func seedLegacyLedgerForTests(
        context: ModelContext, arguments: [String], runtime: PlannerRuntime)
}
```

`appearanceOverride` is pure and available to host logic tests and Mock composition. It returns the value for the existing `Appearance.applyConfiguration(_:defaults:)` bridge. `applyPreferenceOverrides` mutates only the supplied defaults; pass arguments/defaults explicitly, including callers that formerly relied on `ProcessInfo.processInfo.arguments` or `.standard`. Both public helpers are available outside DEBUG, as before; the support target remains development-only in the existing dependency graph. The model-bound seed remains package-scoped, main-actor isolated and DEBUG-only.

## Compatibility details

- Appearance: without `-uiTesting`, return nil even with `-appearance`. Use the first `-appearance` and its immediate following token when it is exactly `light`, `dark` or `system`; a valid explicit value wins over `-uiTestingKeepAppearance`. A missing/invalid value falls through to nil with keep, otherwise System. No stored value is read or written by the parser.
- Preferences: without `-uiTesting`, or with `-uiTestingKeepPreferences`, do nothing (keep also ignores explicit overrides). Otherwise remove all 12 known keys before processing the first `-uiTestingPrefs` payload. Missing payload still resets. Keys remain `today.setting.` plus the supplied suffix; unknown keys are ignored. Comma splitting and first-equals splitting retain their existing empty-subsequence omission, no trimming, case sensitivity and ordered duplicate handling. Integers become Bool (`n != 0`) for switches, Int otherwise; nonintegers remain strings. An empty `key=` remains ignored.
- The 12 reset/accepted suffixes are `dimPastDays`, `firstWeekday`, `weekNumbers`, `calendarStart`, `showTomorrow`, `eveningHour`, `showFreeTime`, `suggestTimes`, `newReminderList`, `newAlarmSnooze`, `newAlarmSound`, `askSuggestions`. Switches are `dimPastDays`, `weekNumbers`, `showTomorrow`, `showFreeTime`, `suggestTimes`, `askSuggestions`. Support references the unchanged public Preferences key constants.
- Legacy seed: require `-uiTesting`, the first `-uiTestingLegacyLedgerRows` followed by an integer >= 5, and an empty LedgerEntry fetch count (a count failure retains its original zero fallback). Insert the same four leading rows: AI asked plan, user deletion with the same TaskSnapshot JSON, completion and linked Undo. Filler rows use Siri/created, original titles and minute offsets. Dates still call `runtime.now()` per entry. Existing One.LedgerEntry constructors still allocate identities. Preserve `try? context.save()`, count guard and relaunch behavior; do not add a reset, change failure handling or replace model IDs with runtime IDs.

## Root caller migration checklist

These are all direct callers found on the base revision; this lane intentionally leaves caller compilation pending Root integration.

1. `ios/Development/Support/MockAppComposition.swift`, initializer: replace `Preferences.applyLaunchOverride(arguments:defaults:)` with `LaunchTestConfiguration.applyPreferenceOverrides(arguments:defaults:)`; replace `Appearance.launchOverride(arguments:)` with `LaunchTestConfiguration.appearanceOverride(arguments:)` inside the existing Appearance.applyConfiguration call. It already imports TodayTestSupport.
2. `ios/Eval/Tests/OneLogicTests/AppearanceTests.swift`, `testLaunchOverrideOnlyUnderUITesting`: import TodayTestSupport and replace all five Appearance.launchOverride calls with LaunchTestConfiguration.appearanceOverride. Keep the original assertions.
3. `ios/Eval/Tests/OneLogicTests/PreferencesTests.swift`, `testUITestingStartsFromTheDefaultsAndAppliesRequestedValues` and `testARealLaunchLeavesThePreferencesAlone`: import TodayTestSupport and replace the three Preferences.applyLaunchOverride calls with LaunchTestConfiguration.applyPreferenceOverrides. Existing Preferences.allKeys assertions still work unchanged.
4. `ios/Sources/TodayShell/HomeView.swift`, `bootstrap()`: remove the DEBUG LedgerMigration.seedLegacyForTests call from the production shell. Root must invoke LaunchTestConfiguration.seedLegacyLedgerForTests from developer composition's existing model-preparation seam, with the same ModelContext, explicit arguments and session runtime, before LedgerMigration.run. Preserve prepareData failure short-circuiting, first-launch fixture preparation and migration/prune ordering. Do not add a TodayTestSupport dependency to TodayShell or One.

App entry/Mock preparation wiring belongs to Root. No direct parser calls exist in `ios/App` on the base. LedgerMigration.run stays in One and the shell still owns the real import/prune lifecycle. Existing service contracts and PlannerTestServices need no change for this helper.

## Validation and limits

Only focused source audits, Swift frontend syntax parsing and `git diff --check` run here. Source comparison checks each migrated method body against the base after the necessary API rename/key qualification. This establishes textual preservation, not type checking or runtime acceptance. Raw parse/audit output and file hashes are retained under the primary checkout's `tests/results/launch-fixture-extraction-20261018-ea805aff/` and indexed in the QA SQLite journal.

No SwiftPM build/test, Xcode build, simulator or physical-device operation runs in this lane. Root exclusively owns integration changes and heavy verification, including exact reset/keep precedence, invalid arguments, isolated defaults, legacy first launch/relaunch and migration ordering. The intentionally untouched callers must be adapted before an integrated build can pass.
