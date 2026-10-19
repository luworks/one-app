# Deterministic rendering integration

Base: `afa1b98faed49b54f9d393aa154b04b850c7801a`. Ownership is limited to TodayDesignSystem `WeekStrip.swift` / `RowChrome.swift`, TodayCore `Capture.swift` / `HealthMetrics.swift`, and this note. No persistent declaration, Date/UUID model default, contract, configuration, fixture or existing test was changed.

## Required presentation environment

`WeekStrip(selected:)`, `TimeColumn(date:)` and `NowRow(date:)` keep their constructors, layout, English copy and accessibility identifiers. They now require `@Environment(PlannerPresentation.self)` with no fallback. Root must install the retained session presentation above every actual feature tree, sheet, preview and UIKit hosting root:

```swift
.environment(presentation)
.environment(\.calendar, presentation.calendar)
.environment(\.locale, presentation.locale)
.environment(\.timeZone, presentation.calendar.timeZone)
.defaultAppStorage(presentation.defaults)
```

All owned display date styles explicitly use presentation calendar, locale and calendar time zone. WeekStrip reads the injected clock once per body evaluation for today's highlight, uses the injected calendar for day numbers and navigation, and retains its existing Monday-first layout. No live adapter is resolved here. Root must still migrate other shared controls, including CaptureCards, outside this lane.

## Capture overloads

Existing properties and parser compatibility APIs remain. Root's explicit paths should call:

```swift
capture.plannedStart(calendar: runtime.calendar) -> Date?
capture.taskTiming(calendar: runtime.calendar) -> (plannedStart: Date?, due: Date?, alertMinutesBefore: Int?)
capture.alertsAtTime(calendar: runtime.calendar) -> Bool
capture.isReadyToAdd(calendar: runtime.calendar) -> Bool
capture.summary(now: now, calendar: runtime.calendar, locale: runtime.locale) -> String
status.accessibilityLabel(for: capture, now: now, calendar: runtime.calendar, locale: runtime.locale) -> String
```

`now` should be one runtime clock snapshot for the rendering/action pass. The CardStatus overload is an extension in Capture.swift; its original API and persisted StoredCard declarations are untouched. Root must adopt the explicit timing path in One capture persistence conversion and explicit summary/accessibility paths in Ask/CaptureCards. Legacy properties intentionally still use system context for source compatibility and are not deterministic session APIs.

Readiness retains exactly `!ringsAsAlarm || hour != nil`; the calendar overload does not add validation or infer a time. Task timing keeps due-time alerts at offset zero, working time/alarm plans, and day-only due dates. Summary retains midnight time suppression, relative Today/Tomorrow/Yesterday labels, all-day/duration/repeat copy and fixed English recurrence labels. Explicit formatting uses the supplied calendar time zone and locale. CaptureParser, draft mapping and prompt compatibility defaults are unchanged.

## Health selection composition

```swift
@MainActor public init(defaults: UserDefaults)
@MainActor public init(defaults: UserDefaults, initialSelection: HealthSelection)
```

The production initializer only reads its required defaults. There is no `shared`, no zero-argument/default-store constructor, no `arguments:` constructor and no production process-argument parser. Retain one store per session, sharing the same injected defaults as that session's presentation. The explicit initialSelection initializer persists the seed immediately (including an empty selection), without posting a save notification during construction. Later `save` persists and posts `didChange` with `object: self`.

Root Development assembly owns parsing `-uiTesting`, `-uiTestingKeepHealthMetrics` and `-uiTestingHealthMetrics`, including the prior unknown-id filtering. For a clean test launch, seed `.default` or the parsed selection through `initialSelection:`. For keep/relaunch behavior, use `init(defaults:)` so saved choices survive. No parser needs to be restored to production.

Update TodayHealthLine's observer to filter on its injected store:

```swift
NotificationCenter.default.addObserver(
    forName: HealthSelectionStore.didChange,
    object: selectionStore,
    queue: .main
) { /* existing refresh */ }
```

Legacy HealthMetricsTests currently pass `arguments:`. Root must adapt those effective tests to explicit production reload and Development seeding/reset behavior, preserving their assertions rather than deleting coverage. Root also owns integrated two-session notification/defaults isolation checks.

## Evidence and remaining acceptance

Only Swift frontend DEBUG iOS syntax parsing, focused source review, 11 corrected synthetic source assertions and `git diff --check` ran. Syntax parse exits 0 with a host macOS sysroot/iOS target warning; it does not resolve imports or type-check APIs. No build, SwiftPM tests, simulator, physical device, PR or push ran, as requested. Root owns integrated compilation and behavioral checks for non-system calendar/time-zone/locale, midnight/DST boundaries, captures/VoiceOver, reload persistence and independent session notifications.

Durable evidence: `/Users/yuanlu/code/one-app/tests/results/deterministic-rendering-20261019-042535-956136`. QA journal session: `deterministic-rendering-afa1b98`. Logs, patch and audit JSON are indexed by path/hash in the primary checkout's `tests/results/activity.sqlite`. The original source audit is retained: its global/arguments rule matched a comment; `source-audit-corrected.json` audits code and passes all 11 assertions. These are synthetic source checks, not runtime acceptance.
