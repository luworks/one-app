# Planner consumer integration

Base: `808be87f59136fbddd54edaa5dd9e8627fe6cee2`.

This implementation changes only TodayPlannerUI, FeatureToday, FeatureCalendar, FeatureReminders and this note. Persistent declarations, service/action implementations, contracts, package/project/configuration, OneStore, intents, executable composition, Shell, Health, Clock and Ask remain root/other-lane owned. Existing behavior tests and fixtures are untouched.

## Required session composition

The executable root must install the required `PlannerPresentation` with `.environment(presentation)` above each actual feature tree, navigation destination and sheet/hosting root. There is no environment default and no live service lookup. Use the same presentation instance for the constructor arguments below and the environment. Root should also install `.environment(\.calendar, presentation.calendar)`, `.environment(\.locale, presentation.locale)`, `.environment(\.timeZone, presentation.calendar.timeZone)` and `.defaultAppStorage(presentation.defaults)` for shared DesignSystem controls and system pickers.

Feature entries receive the retained `PlannerActions` and install it around their real content, sheets and navigation; nested task rows, entry menus, recurring-delete dialogs and drag controls read `@Environment(PlannerActions.self)`. List actions receive required ledger/reminder/runtime parameters. Event recording, quick-add usage recording, and review Undo retain the supplied Ledger/ActivityCenter rather than selecting a static service. A toast must retain the same actions/ledger instance as its originating feature.

Today receives `CalendarService`, `TimerService`, `ReminderService`, Ledger and the existing platform `TravelTimeProviding`. Calendar receives `CalendarService`, PlannerActions, Ledger and AlarmService. Reminder entry points receive only their needed mutation/read capabilities. No new service bag, protocol or live constructor default is introduced. Rows use `TravelTimeProviding.label(... now:)`; root selects its actual platform implementation.

Feature entry AppStorage values use the explicitly supplied defaults; nested calendar/row AppStorage inherits the same store through the entry's `defaultAppStorage` modifier. Preferences helpers explicitly receive presentation.defaults. Consumer-relative Today/overdue/deadline/suggestion/recurrence math uses the session calendar and clock. Consumer formatting and event/entry VoiceOver labels use runtime locale/calendar/time zone. PlannerConsumerTime contains small presentation projections of the existing model movement, subtitle and speech policies so model convenience properties cannot silently read wall-clock time.

## Preserved journeys and native boundary

The original Today timeline/overdue/Tomorrow/review, Timer rows, Calendar Week/Month/Year layouts, reminder pills/list navigation/inline add, editors, context menus, swipes and repeating-delete confirmation remain in place. Year day taps still select `cal.startOfDay(for: tappedDate)` in Month and its agenda. Month title taps still use landingDay with explicit today/calendar. Flexible task movement changes plannedStart only and now dispatches through PlannerActions. Completion/reopen uses the existing action implementation, preserving its Apple commit-before-local mutation and expected-receipt Undo fence; consumer code does not implement a competing completion algorithm.

Native event presentation dispatches only through an injected `NativeCalendarService`, with explicit identifier/start/end/fullOptions/onComplete arguments. New-event NativeEventEditor receives that same instance. There is no replacement EventKit store or static NativeEvents presenter. NativeCalendarChooser and its coordinator retain the supplied native capability. Actual CalendarsSheet selects native UI only when the injected calendar has the native capability; a non-native enabled calendar lists and toggles the actual service's calendar values, without constructing EventKit UI. The disabled-calendar UI and Turn On behavior are preserved. Native unchanged/changed save handling remains in the existing injected adapter and is not reimplemented here.

Quick reminder creation writes ledger/usage success and dismisses only after successful local save; failed saves preserve the draft and show an error. Task/event editor creation also avoids success recording/dismissal on failed local save. No owned file calls Capture.insert/insertRecorded: the throwing capture Add/Added/Undo migration belongs to the Ask/root lane. That lane must `try actions.insert` before marking Added and use that same actions instance for Undo.

## Root integration work

- Adapt `TodayShell/HomeView.swift` feature/quick-add/event constructor sites and `TodayShell/Destinations.swift` task/event/holidays destinations to the signatures below. Replace inferred `.shared` there with retained injected capabilities. Pass `openTimer` by label because the required dependencies follow it.
- Pass root's explicit open-settings callback to RemindersView and keep its existing requestAccess closure; consumer code no longer calls UIApplication.shared or resets process-wide UI-test preferences. Test preference seeding/reset belongs in root development assembly.
- Root-owned shared `TodayDesignSystem/WeekStrip.swift`, `RowChrome.swift` (TimeColumn/NowRow), `TodayCore` repeat-label helpers, and platform travel label formatting may still contain system-relative rendering. This bounded consumer migration does not claim complete closure isolation; root must finish those seams. The new consumer helper file is automatically included by SwiftPM's directory target; root owns any explicit Xcode source membership changes.
- Non-native CalendarService deliberately has no native edit capability. Existing system-event tap/edit dispatch is capability-checked; development scenarios needing native editor behavior must use the native live adapter, while non-native scenarios must verify their supported actions rather than claim EventKit acceptance.

## Final constructors

All dependency arguments below are required. Defaults are existing behavior inputs only. PlannerPresentation is defined in TodayDesignSystem; PlannerActions and model-bound services remain in One; TravelTimeProviding remains in TodayPlatform.

### DayAgenda.swift

```swift
package init(day: Binding<Date>, showsWeekStrip: Bool, openTask: @escaping @MainActor (OneTask) -> Void, openEvent: @escaping @MainActor (OneEvent) -> Void, openTimer: @escaping @MainActor () -> Void, actions: PlannerActions, calendar: any CalendarService, timers: any TimerService, reminders: any ReminderService, ledger: Ledger, travel: any TravelTimeProviding, presentation: PlannerPresentation)
```

### EveningReviewSheet.swift

```swift
package init(id: AnyHashable, time: Date?, title: String)
package init(now: Date, tomorrow: Date, peek: [ReviewPeek], actions: PlannerActions, reminders: any ReminderService, ledger: Ledger)
```

### TimerRows.swift

```swift
package init(controller: any TimerService, open: @escaping () -> Void)
```

### CalendarView.swift

```swift
package init(day: Binding<Date>, mode: Binding<Mode>, calendar: any CalendarService, actions: PlannerActions, ledger: Ledger, alarms: any AlarmService,
                 onOpenTask: @escaping @MainActor (OneTask) -> Void,
                 onOpenAlarm: @escaping @MainActor (OneAlarm) -> Void,
                 onOpenDay: @escaping @MainActor (Date) -> Void)
package init(calendar: any CalendarService)
```

### EventEditor.swift

```swift
package init(event: OneEvent? = nil, day: Date? = nil, start slotStart: Date? = nil, end slotEnd: Date? = nil,
                 calendar: any CalendarService, actions: PlannerActions, ledger: Ledger, alarms: any AlarmService, presentation: PlannerPresentation)
```

### NativeCalendarChooser.swift

```swift
package init(calendar: any NativeCalendarService)
```

### YearMarksView.swift

```swift
package init(presentation: PlannerPresentation)
package init()
```

### RemindersView.swift

```swift
package init(isPushed: Binding<Bool>, path: Binding<[ReminderTarget]>,
                 sync: any ReminderService, actions: PlannerActions, ledger: Ledger, alarms: any AlarmService, presentation: PlannerPresentation, openSettings: @escaping @MainActor () -> Void, requestAccess: @escaping @MainActor () async -> Void)
```

### ReminderListScreen.swift

```swift
package init(target: ReminderTarget, actions: PlannerActions, ledger: Ledger, reminders: any ReminderService, alarms: any AlarmService)
```

### QuickReminderSheet.swift

```swift
package init(listName: String = "", actions: PlannerActions, ledger: Ledger, alarms: any AlarmService, activity: ActivityCenter, presentation: PlannerPresentation)
```

### TaskEditor.swift

```swift
package init(task: OneTask? = nil, actions: PlannerActions, ledger: Ledger, reminders: any ReminderService, alarms: any AlarmService, presentation: PlannerPresentation)
```

### ListEditor.swift

```swift
package init(list: OneList? = nil, ledger: Ledger, reminders: any ReminderService, onCreated: (@MainActor (OneList) -> Void)? = nil)
```

### Rows.swift

```swift
package init(event: OneEvent, start: Date? = nil, pendingDelete: Binding<CalEntry?> = .constant(nil), open: @escaping @MainActor (OneEvent) -> Void, calendar: any CalendarService, travel: any TravelTimeProviding)
package init(task: OneTask, showsTime: Bool = false, time: Date? = nil, showsList: Bool = true, compact: Bool = false, suggested: Date? = nil, agendaDay: Date? = nil, open: @escaping @MainActor (OneTask) -> Void)
package init(alarm: OneAlarm, date: Date)
```

### ExternalEventRow.swift

```swift
package init(event: ExternalEvent, pendingDelete: Binding<CalEntry?>, calendar: any CalendarService, travel: any TravelTimeProviding)
```

Other changed required APIs:

```swift
EventEditor.defaultStart(for day: Date, now: Date, calendar: Calendar) -> Date
View.entryActions(_:pendingDelete:open:edit:swipes:calendar:) // required any CalendarService
View.deleteListAlert(_:reminders:ledger:) // required any ReminderService and Ledger
SmartList.includes(_ task: OneTask, now: Date, calendar: Calendar) -> Bool
```

## Validation boundary

Only Swift frontend DEBUG iOS syntax parsing, source ownership/dependency checks, focused source review and `git diff --check` ran in this lane. Syntax parsing emits the host macOS sysroot/iOS target warning and exits successfully; it does not resolve modules or type-check constructors/protocol conformances. No SwiftPM, Xcode build, simulator, physical device, browser E2E or security/signing command ran, as requested. Root owns integrated type checking and functional verification, including Year exact-date navigation, native unchanged/changed save, context-menu edit, recurrence deletion/completion/Undo, multiple session defaults/ledgers, and quick-add failure behavior. Phone EventKit/AlarmKit acceptance remains separate.

Canonical evidence and the QA journal session are recorded below after final audit. No raw historical evidence was overwritten or deleted.

Final audit evidence: `/Users/yuanlu/code/one-app/tests/results/planner-consumers-20261019-042100-084ebb13`. QA journal session: `planner-consumers-761c320a`. The audit JSON distinguishes source assertions from runtime acceptance.

Corrected source audit: `source-audit-corrected.json` has all 13 checks passing. The original audit and logs are retained: its clock/defaults pattern falsely matched `clearDate()` and a stale comment. Identifier boundaries were corrected; syntax validation was not rerun for the audit-rule correction.
