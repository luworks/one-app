# FeatureClock integration contract

Extracted from clean base `a33cc1d1696bd67d64a1430da888c315e8ed40dd`.
The real World Clock, city picker and Stopwatch implementations live here; the app-owned originals are removed.
The integration owner must link this directory as the `FeatureClock` product and update app imports/source membership.
No manifest, configuration or app assembly changes are included in this lane.

## Public entry points

- `WorldClockView(store:now:showUndo:)`: store defaults to `.shared`; now defaults to `TodayPlatform.TodayClock.now`. `showUndo` is required: pass `{ message, undo in toast.show(message, undo: undo) }` using the app's existing toast. This keeps deletion, original insertion-index restoration and Undo in the existing app UI without importing app internals. Do not replace it with an empty production closure.
- `CityPicker(store:now:)`: defaults to the same shared store/production clock. Inject the same store and clock as World Clock in Workbench.
- `WorldClockStore(database:defaults:homeZoneIdentifier:homeCity:arguments:)`: all parameters have production defaults; public `keys` (read-only), `database`, `home`, `others`, `showsGraph`, `contains`, `add`, `remove`, `insert`, `move`, `shared` and `defaultsKey`.
- `StopwatchView(model:)`: defaults to `.shared`, initializes the restored pager from the supplied model.
- `StopwatchModel(defaults:now:arguments:)`: defaults to standard preferences, live action/timeline dates and process arguments; public `state` (read-only), `page`, `startStop`, `lapReset`, `shared`. An injected clock drives actions, both faces and the current lap consistently.

Workbench supplies isolated UserDefaults, a real CityDatabase populated from test support, explicit home/time and `arguments: []`. It can set `showsGraph`/`page`, prepare stopwatch state through model actions and capture the undo closure. No fake city/stopwatch data is introduced in production. The old local preview and `previewFixture` are removed; the main preview scene registry owns deterministic previews.

## Required dependency surface

Import exactly `TodayCore`, `TodayDesignSystem`, `TodayPlatform`.

- Core: public `CityRecord` (initializer and accessed fields), `CityDatabase` (initializer, `decode`, migration/search/display/city/country APIs), `WorldClock` and all accessed nested logic/look values, `StopwatchState`, `StopwatchPage`, `StopwatchDial`/`Metrics`, `LapMark`. The existing time formatting also calls public `AlarmPlan.timeParts(hour:minute:locale:)`; keep its default locale. Do not duplicate its formatting here.
- DesignSystem: public `PressScale` with public zero-argument initializer, `StackedCard.init(fill:horizontalPadding:flat:content:)`, `View.stackedCardRow()` and `RowAction.delete(asksFirst:_:)`. The lane does not need an exported `UndoToast`.
- Platform: public `TodayClock.now` and `View.performanceDestination(_:)`, preserving the `clock.cityPicker` destination.
- App resources: retain `cities.json` in the main bundle. `CityDatabase.shared` remains a main-actor bundle-backed extension in FeatureClock; do not add a conflicting declaration elsewhere.

Preference keys, migration, launch arguments, pager restoration and all accessibility identifiers remain the original ones. The default Stopwatch deliberately uses real Date/timeline dates, as before, rather than the World Clock's UI-testing pinned TodayClock.

## Verification boundary

Swift frontend parsing (Swift 6 language mode, Debug and non-Debug), source-diff review, accessibility/launch-argument preservation and whitespace checks are the intended lightweight checks. Dependency modules are absent in this worktree, so parsing cannot establish cross-module visibility, Swift 6 actor/type correctness, linking, Xcode build or runtime acceptance. Integration must type-check against the actual Core/DesignSystem/Platform implementations and resolve concrete diagnostics there. No unchecked Sendable suppression, Xcode build, simulator run or device run is included.
