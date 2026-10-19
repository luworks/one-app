# Calendar lane integration

Moved only CalendarView.swift, YearMarksView.swift and EventEditor.swift from `ios/One` into `ios/Sources/Features/FeatureCalendar`. No package/project/model/shared-source edits. Entry points and protocol witnesses are package-visible; implementation helpers remain internal/private.

## Assembly contract

```swift
@MainActor
CalendarView(day: Binding<Date>, mode: Binding<CalendarView.Mode>, calendar: CalendarSync,
             onOpenTask: @escaping @MainActor (OneTask) -> Void,
             onOpenAlarm: @escaping @MainActor (OneAlarm) -> Void,
             onOpenDay: @escaping @MainActor (Date) -> Void)
EventEditor(event: OneEvent? = nil, day: Date = .now,
            start: Date? = nil, end: Date? = nil, calendar: CalendarSync)
CalendarsSheet(calendar: CalendarSync)
YearHolidaysSettingsView()
EventEditor.defaultStart(for: Date) -> Date
```

Shell must supply real task/alarm presentation callbacks on its current modal host, the existing model container and UndoToast environment. Keep Calendar mounted and preserve the selected day/mode when dismissing those editors. No default/no-op editor callbacks remain. Week/Month taps and Edit context actions use their existing `open`/`edit` propagation into CalendarView, which invokes the required callbacks. Local/new events retain the Calendar-owned sheet and original presentation identity strings. System event presentation still uses NativeEvents with occurrence start; empty-slot creation still chooses native versus local editor using the injected CalendarSync. Calendar owns no TaskEditor or AlarmEditor construction or imports.

Root moves NativeCalendarChooser into this target and supplies `init(calendar: CalendarSync)`; this lane already calls that initializer. Settings receives CalendarsSheet and YearHolidaysSettingsView through Shell rather than importing FeatureCalendar. No TaskRow/EventRow construction exists in these three sources; Calendar's private AgendaRow keeps its existing entry actions and open propagation.

## Required lower APIs (root-owned)

- One: package-visible OneEvent/OneTask/OneAlarm and fields queried/read/mutated by these views; OneEvent construction, copy, repeats and duration; CalEntry/Source, fields, span and speech; CalendarEntries.make/on with the existing argument labels/defaults; UndoToast.show/showNotice; Ledger.record and its change kinds; Ringer.isAvailable.
- CalendarSync: usesNativeEditor, isOn, version, setEnabled, delete(OneEvent), save(OneEvent), preserving existing save/delete default recurrence span. Inject the same production adapter used by the shared CalendarEntries merger and native-system bridge. The merger/native bridge implementations remain root-owned; their existing static entry points are retained here.
- One native-system bridge: NativeEvents.edit(identifier:start:) and edit(start:end:), NativeEventEditor.init(start:). Calendar no longer needs OpenedEntry or NativeEventSheet.
- TodayPlannerUI: entryActions(_:pendingDelete:open:edit:) and entryDeleteDialog(_:), preserving real deletion/Undo behavior.
- TodayDesignSystem/Core/Platform: existing PillStyle/PressScale/EventTint, DayLabel, Preferences/SettingsKey, calendar/year/holiday rules, ReminderOffset, TodayClock, performanceDestination and DEBUG YearCacheTrace. FeatureCalendar has no FeatureClock/FeatureHealth dependency.

## Preserved behavior and verification

Occupied rectangle geometry, HitView.point(inside:with:), SlotPressView, alarm markers, pinch/long-press/drag gesture bodies, DST/day arithmetic, recurrence and year mark computation are unchanged. Private WeekView/WeekPage edit/create callbacks are now required; all existing callers already supply them. Existing English UI strings and accessibility identifiers are unchanged.

Ran `swiftc -frontend -parse` on all three moved files and `git diff --check`: passed. A focused source comparison checked interface-only differences and unchanged gesture bodies. Syntax parsing does not establish module type checking, build or UI acceptance. No build, swift test, simulator or device runner was started in this lane. Root owns integrated compilation and targeted Calendar acceptance (alarm marker/editor, occupied hit regions, empty-slot creation, task drag and fixed events).

QA development and verification records use `/Users/yuanlu/code/one-app/tests/results/activity.sqlite`; raw syntax verification output is retained under that canonical results directory.
