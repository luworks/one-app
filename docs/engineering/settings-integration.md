# Settings native integration

## Ownership and source movement

The three complete production sources now live exactly once in
`ios/Sources/Features/FeatureSettings/`: `SettingsView.swift`, `SettingsRows.swift`
and `AppearanceSettingsRow.swift`. Their originals in `ios/One/` are removed.
This lane changes no package manifest, project, model, bridge, Shell, shared row,
Health or Reminders source. `DataReset` remains a separate One operation.

The integration owner must add the real `FeatureSettings` target with dependencies
on `TodayCore`, `TodayShared`, `TodayData`, `TodayPlatform`,
`TodayDesignSystem`, `One` and `FeatureHealth`, and remove the three old executable
source memberships. There is no FeatureClock dependency. `FeatureHealth` is real:
the complete Today section constructs its `HealthMetricsLink`.

## Shell construction

`SettingsView`, its `Selection`, initializer and body have package access. Only
TodayShell's executable entry API should be public. Its constructor is
`SettingsView(selection:calendar:reminders:notifications:diagnostics:calendars:holidays:activityData:shareDiagnostics:reset:)`.

Supply the live `CalendarSync`, `RemindersSync` and notification `Reminders`
instances. `calendars`, `holidays` and `activityData` each return `AnyView` wrapping
their actual moved production destination, configured by Shell. `shareDiagnostics`
receives the exported URL and returns the actual system share presentation.
`reset` receives the current `ModelContext`; production wiring calls
`DataReset.run(context)` there. All services, destination builders, sharing and
reset are required. `selection` alone defaults to `.all`. `AnyView` is limited to
the presentation boundary; there is no global factory dictionary, registration
step or no-op production action.

Pass the same model container and HealthModel environment to Settings and every
presented destination. `HealthMetricsLink` uses the existing Health detail sheet;
Shell supplies the root-owned real HealthModel above the view. Calendar and
Reminders toggles call the injected concrete adapters, including reverting the
switch when access is refused. Notification status/request uses the injected
`Reminders` adapter. Existing Ledger flush, widget rewrite on travel-time changes,
appearance observation, navigation instrumentation and accessibility identifiers
are retained.

## Required lower-level APIs

The integration owner exposes the following existing declarations and used
members with package access. This lane deliberately does not edit their owners:

- One: `CalendarSync.isOn/setEnabled`, `RemindersSync.isConnected/connect/disconnect`,
  `Reminders.authorizationStatus/requestPermission`, `Ringer.isAvailable/isDenied`,
  `Ledger.flush`, `WidgetFeed.rewriteFromStore`, `OneList.order/name`,
  `AIGrant.expires/scope/info`, `GrantStore.setEnabled/revoke`, and the `AlarmSound`
  list's `all/id/name` if it remains in One. Model and operation ownership stays
  with root; no feature-to-feature import is needed for alarm sounds.
- FeatureHealth: `HealthMetricsLink`, its explicit package initializer and body.
  Its existing `HealthDetailSheet` remains Health-owned. Do not reintroduce a
  global Health source factory or create another HealthModel here.
- Smart-list primitives: move the existing `SmartList` and `SmartListLayout`
  declarations to the agreed lower module and expose their used package API.
  Settings needs `SmartList` identity/raw value/title/symbol/color;
  `SmartListLayout.orderKey/hiddenKey`, `init(order:hidden:)`, mutable `order` and
  `hidden`, and `orderString/hiddenString`. Settings imports One/Core/DesignSystem;
  it must not import FeatureReminders. The integration owner chooses the split
  between the model-free values and the model-bound `includes` behavior.
- Move the real `ListGlyph` to TodayDesignSystem with a package constructor
  `init(color:symbol:size:)` and body. Preserve its rendering. No copy is added
  here, and the Reminders lane's files are untouched.

## Real section scenes

SceneCatalog can pass `selection:` to the same fully constructed SettingsView.
The Form renders only the chosen production section, preserving the same state,
controls, confirmation handlers and destination builders as `.all`.

| Scene | Selection or real destination |
| --- | --- |
| settings | `.all` |
| settings.appearance | `.appearance` |
| settings.apple | `.apple` |
| settings.today | `.today` |
| settings.calendar | `.calendar` |
| settings.reminders | `.reminders` |
| settings.smartLists | `.smartLists` |
| settings.alarms | `.alarms` |
| settings.ai | `.ai` |
| settings.activity | `.activity` |
| settings.about | `.about` |
| settings.delete | `.data`, then use the real delete action |
| settings.calendar.holidays | Shell's real holidays destination |
| settings.ai.automaticChanges | `AutomaticChangesView()` |

`AutomaticChangesView`, `DeleteDataConfirmation`, `AppearanceSettingsRow` and the
existing row/section entry types also have explicit package initializers. Remove
SceneRegistry's obsolete private-section blockers when wiring these scenes;
this lane does not own SceneRegistry or SceneCatalog. The complete Today scene
includes Health and all three original headline toggles; it is never replaced
by `TodayTimelineSettings` alone. The complete AI scene retains the seven-day
grant toggle, scope destination, suggestions and archive toggle.

## Explicit diagnostics export

Root retains and starts one `LocalDiagnostics`; Settings only receives it.
About retains the original Version row and adds `Export diagnostics`
(`settings.exportDiagnostics`). Only this button's action calls `exportURL()`.
On success, Settings presents the supplied system-sharing builder with that URL;
on failure it shows `Couldn’t export diagnostics` / `Please try again.` No file
is generated by initialization, appearance, automatic task or scene selection.
No upload or diagnostics instance is created here.

## Evidence and integration gates

This lane ran Swift frontend parsing on the three moved sources, source review,
original string-literal preservation checks and `git diff --check`. These are
syntax/source evidence only. No logic suite, module typecheck, app build,
simulator or physical-device run was performed: those runners belong to root.

Root still owns package/API resolution and integrated verification. Focused
acceptance should retain the real double delete confirmation (including typed
DELETE), refusal-aware Apple toggles, smart-list hide/reorder persistence,
seven-day grant failure warning, inherited appearance/Health environment,
Activity/Holidays navigation, and About export opening system sharing only
after the explicit tap. Existing English copy, preference keys, accessibility
handles and option defaults remain unchanged apart from the new export UI.

Development and verification actions are recorded in the canonical QA database
at `/Users/yuanlu/code/one-app/tests/results/activity.sqlite`, session
`settings-reconstruction`.
