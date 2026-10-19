# Clock feature integration

The Clock lane moves the complete `AlarmsView.swift`, `AlarmEditor.swift`,
`TimerSection.swift`, `TimerCard.swift` and `TimerPicker.swift` implementations from
`ios/One/` into `ios/Sources/Features/FeatureClock/`. Their originals are removed.
Existing World Clock and Stopwatch sources are unchanged. All five moved files
are iOS-only, matching the existing feature sources.

## Assembly contract

The integration owner must add `One` to FeatureClock's direct package dependencies
and remove the five original paths from app source membership. This lane does not
edit the package manifest, project, configuration, models or Shell.

Same-package entry points are:

```swift
AlarmsView(
    section: Binding<ClockSection>,
    alarms: AlarmCenter,
    timers: TimerController,
    showUndo: @escaping (String, @escaping () -> Void) -> Void
)
AlarmEditor(
    alarm: OneAlarm? = nil,
    showUndo: @escaping (String, @escaping () -> Void) -> Void
)
TimerSection(controller: TimerController, alarms: AlarmCenter)
SoundScreen(sound: Binding<String>)
```

These types, initializers and View bodies use `package` access. `ClockSection`
already belongs to TodayCore and has accessible cases, titles and raw values;
there is no duplicate section enum. The executable enters through TodayShell's
public entry point rather than importing these package views directly.

Shell supplies its existing AlarmCenter, TimerController and real UndoToast show
closure, and applies the same model container above all roots and editor sheets.
There is no default empty action. AlarmsView forwards the required undo action to
WorldClockView and its alarm editor sheets. A unified Shell alarm destination
constructs AlarmEditor with the same action, preserving the presenting sheet.
TimerSection observes the supplied alarm center and initializes its picker from
the supplied controller's most recent timer. Production assembly supplies the
same process instances used by Ringer, FirstRun and AppIntents.

## Bridge visibility needed from integration

The following existing One declarations and used members need package access;
their implementations remain with the integration owner:

- OneAlarm, OneTask and OneEvent, including fields queried/rendered by AlarmsView;
  OneAlarm initialization, copy, timeToday, subtitle, nextRing and setOn; task/event
  reminderDate; alarm scheduling signature, creation date and AlarmKit identifier.
- AlarmCenter, its states/authorization, state(of:), watch(context:) and
  requestAuthorization(); AlarmLiveState cases.
- TimerController and its timers, ringing, log, recents, sound, message, refresh,
  start, pause, resume, cancel and deleteRecent APIs.
- Ringer.sync, stop and isDenied; FirstRun.alarms; Reminders.shared,
  authorizationStatus and requestPermission; Preferences.newAlarmSoundName and
  newAlarmSnoozeMinutes; Ledger.record and alarmTitle.

AlarmActions remains in One and is not duplicated or moved into FeatureClock.
AlarmSound/SoundPreview and TodayClock/performance hooks resolve through
TodayPlatform; timer values, plans and formatting resolve through TodayCore;
PillSwitcher and RowAction resolve through TodayDesignSystem. No FeatureClock
self-import, FeatureHealth import, Shared or Data import remains in the moved
files. Picker, row chrome, cards and editor details stay internal.

## Preserved behavior and verification

The real UIKit hours/minutes/seconds wheels, picker limits and units, timer rings,
Recents presets/load/start/swipe deletion, label/sound controls and Siri note stay
intact. Timer refresh still occurs on appearance, alarm-state updates and active
scene transitions. Alarm permissions, toggle/stop, edit/add sheets, repeat/snooze,
save-before-editor-dismissal, Activity recording, delete and Undo ordering remain
intact. UI strings and accessibility identifiers are unchanged.

Lane checks: Swift frontend syntax parsing for the iOS simulator target, exact
string-literal comparison against the pre-move sources, a focused movement diff
review and whitespace/source-ownership checks. These are source checks only.
No type-check, package/Xcode build, logic test, simulator UI or device run is
claimed. Integration must validate bridge visibility/source membership and run
its selected Clock/Timer journeys using its single owned build/device runner.
QA actions and raw source-check evidence are recorded under
`/Users/yuanlu/code/one-app/tests/results/` through `tests/qa/journal.py`.
