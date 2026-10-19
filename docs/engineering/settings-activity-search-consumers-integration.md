# Settings, Activity and Search consumer integration

Base: `808be87`. Owned source: FeatureSettings, FeatureActivity and FeatureSearch only. This lane changes no service contracts, models, root assembly, package or project files.

## Required root wiring

Install the retained session `PlannerPresentation(runtime:defaults:)` and `.defaultAppStorage(session.defaults)` above every entry point and reinject them at UIKit hosting roots. Search's explicit `defaults` must be the same session defaults. No constructor selects a live service, global clock or standard defaults. SearchMemory owns only the existing six recent terms in the supplied defaults; it has no shared cache.

The final changed entry-point signatures are:

```swift
SettingsView.init(
    selection: SettingsView.Selection = .all,
    calendar: any CalendarService, reminders: any ReminderService,
    notifications: any NotificationService, alarms: any AlarmService, ledger: Ledger,
    openSettings: @escaping @MainActor () -> Void,
    rewriteWidgets: @escaping @MainActor () -> Void,
    diagnostics: LocalDiagnostics,
    calendars: @escaping @MainActor () -> AnyView,
    holidays: @escaping @MainActor () -> AnyView,
    activityData: @escaping @MainActor () -> AnyView,
    shareDiagnostics: @escaping @MainActor (URL) -> AnyView,
    reset: @escaping @MainActor (ModelContext) -> Void
)
AutomaticChangesView.init(ledger: Ledger)
SearchView.init(calendar: any CalendarService, defaults: UserDefaults,
                @ViewBuilder editor: @escaping @MainActor (OpenedEntry) -> Editor)
ActivityDataView.init(
    activity: ActivityCenter,
    exportDestination: @escaping @MainActor (ActivityExportFormat) throws -> URL,
    summary: @escaping @MainActor () -> ActivityCenter.Summary,
    clear: @escaping @MainActor () -> Void,
    export: @escaping @MainActor (ActivityExportFormat, URL) async throws -> URL,
    legacyRowCount: @escaping @MainActor () -> Int
)
```

`ActivityView.init(activity:flush:undo:)` is unchanged. Root must capture its matching ledger/context in `flush` and `undo`, and the matching activity/store/context in ActivityDataView's summary, clear, export and legacy count closures. Export receives the required caller-selected URL: `export: { format, url in try await activity.export(format, to: url) }`. `exportDestination` is evaluated only after the explicit export button tap and must select a destination within that session's export area. No feature creates a default export path. Existing sharing is presented after successful export; failures retain the existing error footer.

Root must supply real calendars, holidays, Activity and editor builders. Search queries the injected CalendarService; native result taps cast that exact instance to NativeCalendarService and call `edit(identifier:start:end:fullOptions:onComplete:)`. If native capability is absent, the existing root editor builder receives `.system(id)`; this feature creates no private alternative editor. Root must handle that case using the session's existing supported destination. Search recurrence, overdue/today filters, labels and alarm time locale use session runtime.

Settings retains every Selection (`all`, `appearance`, `apple`, `today`, `calendar`, `reminders`, `smartLists`, `alarms`, `holidays`, `ai`, `activity`, `about`, `data`), real existing section views, navigation and both Delete All Data confirmations. `openSettings` is an explicit root capability: App may open system settings; Workbench must provide its own controlled callback without calling UIApplication.open. `rewriteWidgets` captures the retained root WidgetFeed. The existing UIKit appearance trait observation remains; it does not open URLs or select services.

App root alone starts its retained LocalDiagnostics. Workbench supplies an unstarted local instance. Settings calls exportURL only from the existing explicit export button and invokes the supplied share builder only for that resulting file; it never starts diagnostics or uploads.

Grant controls require the actual session Ledger and presentation runtime. Both enable/disable and Revoke use throwing GrantStore.setEnabled, retaining save/rollback-before-recording behavior. Revoke turns off active grants of the selected scope, like the toggle. The seven-day planFreeTime scope, persisted grant-derived toggle state, Activity recording warning and existing error copy remain. The Changes/paused enforcement gate stays in AutoPlan; the UI does not synthesize enabled authorization.

Both Activity screens subscribe to `activity.didChange` with `object: activity`. ActivityView still pages and queries undone IDs from that actual activity.store, flushes before reload, uses session retention calendar/time, and retains its supplied Undo operation. No new mutation route requires PlannerActions: existing explicit undo/reset closures and GrantStore's required Ledger own these operations; editor mutations remain in the root-supplied real builders.

## Verification and limits

Focused source review checked injection, scope/error paths, retained query/export/clear behavior and unchanged section/confirmation structure. DEBUG iOS Swift frontend syntax parsing of all seven owned Swift files and `git diff --check` passed. Parsing emits the host macOS sysroot/iOS target warning and does not resolve imports or type-check APIs.

No SwiftPM, Xcode build, simulator, physical-device or authenticated E2E flow ran, per parent ownership. Root must update App/Shell/Development call sites, perform integrated type checking, and verify two-session preferences and notification isolation, native Search open/edit behavior, failed grant save UI, paused/Changes-off automation, actual Activity Undo/clear/export, diagnostics sharing, controlled Workbench callbacks and both delete confirmations. Source checks alone do not prove these runtime journeys.

Retained source evidence: `/Users/yuanlu/code/one-app/tests/results/settings-activity-search-20261018-211537` (`syntax-parse.log`, `diff-check.log`, `source-audit.json`, `bounded.patch`). All ten source checks passed. QA session `consumers-settings-activity-search-20261018` records actions, results and artifact paths/SHA-256 hashes in the primary checkout journal. These assertions prove source structure only.
