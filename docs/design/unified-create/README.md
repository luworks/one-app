# Unified creation: design checkpoint

Status: retired 2026-10-29. The unified composer (rounds 7–9, PRs #214, #231–#233) was removed at the
user's request; creation reuses Apple's own designs instead: + opens New alarm / New reminder / New event;
a new event uses Apple's own event editor (EventKitUI) when Calendar access is on, a new reminder opens
the Apple Reminders-style details form (`TaskEditor`), and a new alarm opens the Clock-style Add Alarm
sheet without custom quick picks. iOS offers no embeddable system editor for reminders or alarms. This page
remains as design history. These images are generated mockups, not
screenshots of implemented UI or evidence of device behavior. This checkpoint
originally changed documentation only. The round 7 implementation updates the
creation flow introduced in PR #214 while retaining its explicit commit boundary.

## Round 9 implementation: closer to Apple

Chosen from the round 9 review (decisions 1B, 2B, 3B, 4A; green accent in the
composer). The five-operation budget still holds and is tested.

- iOS 26 sheet pattern: ✕ (cancellation) and a tinted ✓ (confirmation, the
  explicit Create) in the navigation bar; the Reminder / Event / Alarm segmented
  control sits under it, as in Calendar's New sheet. Titles: New Reminder, New
  Event, Add Alarm. The dock above the keyboard is one row (two for events:
  duration and calendar).
- Reminder: Apple Reminders' Date and Time rows (graphical date, 24-hour time
  wheel with the ±10 min…±1 day nudges inside it), List and Flag. The quick row
  shows Today / Tomorrow / This Weekend / Next Week / No Date / Date & Time, and
  after a day is picked switches to 09:30 / 12:00 / 18:30 / 22:00 / Time… (‹
  goes back). The due date is shown once.
- Typed timing is highlighted in the title (`CreateTitleField`, a UITextView,
  because a SwiftUI TextField cannot colour ranges). The summary line and a
  `Keep as text` button appear only while something is understood; tapping the
  highlight or the button restores the previous timing, keeps the words in the
  title and stops parsing until the title is cleared.
- All-day events use a one-column day wheel in the same row style as the timed
  day · hour · minute wheel.

## Round 8 implementation: five operations or fewer

Goal: every common, typical and hard Reminder, Event and Alarm is created in at
most five operations, counted from + to Create (one tap, one Return, one wheel
column or one typed entry each). `CreateStepBudgetTests` runs eleven such
journeys on the simulator and fails above five.

- A fixed dock sits above the keyboard (and at the bottom without it): the one
  `Create reminder` / `Create event` / `Create alarm` button, this type's quick
  choices, then a Reminder / Calendar / Alarm segmented control. It replaces the
  header type menu and checkmark. The header keeps Close and a Hide keyboard
  button while typing.
- The title understands timing ("Pay rent tomorrow 18:30", "Dinner fri
  19:00-21:00", "6:30 weekdays", "in 20 min") through the existing
  `CaptureParser`. It only fills the fields and the summary line under the
  title; the understood words are left out of the saved title. A chip tapped
  afterwards wins until the typed timing changes. Return creates a complete
  draft (an explicit action, like Create); otherwise it closes the keyboard.
- Reminder dock: Today / Tomorrow / This Weekend / Next Week / No Date / Date…,
  then 09:30 / 12:00 / 18:30 / 22:00 / Time… (a 24-hour wheel).
- Event: one 24-hour day · hour · minute wheel replaces the Starts popovers;
  dock chips set 30 min / 1 h / 2 h / All-day and the writable calendar. A dated
  event with no time is all-day. Ends, location, repeat, alert, availability,
  URL and notes remain below.
- Alarm opens without the keyboard: the label is optional (saved empty, shown
  as "Alarm"), and the wheel and the round 7 Repeat card (presets plus tappable
  weekday circles) are visible at once. A bare typed hour is a morning hour.

Modelled counts and KLM time estimates for the alternatives are in the QA
results (`designs/create-round8-20261029`).

## Round 7 implementation

- Independent shared name section and circular close/checkmark header. The type
  menu preserves shared text and independent per-type settings. Keyboard Done
  and Hide keyboard dismiss input without submitting.
- Alarm has a native 24-hour wheel, without name suggestions or time shortcuts.
- Alarm and Reminder share Monday-first M T W T F S S buttons, weekday presets
  and a persisted Monday/Sunday start preference. Stored weekday identities
  never change when display order changes. Full weekday accessibility labels
  distinguish the repeated initials.
- Reminder retains the 12-cell date/time grid, List, Flag, arbitrary date picker,
  existing recurrence options and notes. Its due summary uses 24-hour time.
- Local Today notifications persist Sound / Snooze / Snooze Duration, carried
  through copies, recurrence and Undo. Snooze only schedules after an explicit
  notification action. Synced reminders remain Apple-owned and do not get
  duplicate Today notifications; these controls are disabled with an explanation
  when Apple Reminders is connected.
- Event exposes start/end, all-day, selected writable calendar, repeat, alert,
  location, URL, availability and notes. Existing native event-edit routes remain.
- Creation errors retain drafts and remote receipts. Alarm authorization remains
  asynchronous. No device install or local simulator run is part of this change.

CI owns unit/helper checks and compilation. The required merge checks do not
execute UI journeys; neither the mockups nor a green compile prove pixel parity,
notification delivery, Dynamic Type usability or physical-device behavior.

## Adjacent iteration review

Compare each new iteration with the immediately preceding one: three previous
images and three current images. Round 4 establishes the aligned layout with
the keyboard dismissed. Round 5 explores explicitly tapping the name field and
opening the keyboard. Each exported image is 390 × 844 pixels.

| Iteration | Alarm | Reminder | Calendar event |
| --- | --- | --- | --- |
| Round 4 | ![Round 4 Add Alarm](round4-alarm.png) | ![Round 4 Add Reminder](round4-reminder.png) | ![Round 4 Add Event](round4-calendar.png) |
| Round 5 | ![Round 5 Add Alarm](round5-alarm.png) | ![Round 5 Add Reminder](round5-reminder.png) | ![Round 5 Add Event](round5-calendar.png) |

## Shared design rules

- Use one header pattern: circular close control on the left, centered
  `Add Alarm`, `Add Reminder` or `Add Event`. Since round 8 the explicit submit
  is the dock's Create button (or Return on a complete draft).
- Put the name in an independent first section. Keep its typography, margins
  and height consistent across all three types.
- Use the same Repeat component for Alarm and Reminder: a readable summary,
  `Weekdays`, `Weekends` and `Every day` presets, and seven directly selectable
  weekday circles. Order weekdays according to the user's calendar settings.
  This weekly pattern does not impose a seven-day scheduling limit. Preserve
  other supported reminder recurrence choices when implementing the component.
- Use the same `Sound`, `Snooze` and `Snooze Duration` presentation for Alarm and
  Reminder. Remove Reminder's separate bell and Repeat utility icons; retain
  its List and Flag actions.
- Snooze behavior is explicitly confirmed: after the user taps Snooze, alert
  again after the selected duration. Weekly recurrence and this manual snooze
  interval are separate. Automatic repeated alerts until completion are outside
  this design.
- Align the header and name sections across all three types. Align the shared
  Repeat and sound/snooze groups across Alarm and Reminder. Event retains its
  own single-row Repeat and event-specific field structure.

The typography and spacing targets are a 17-point semibold header, 20-point
medium name, 17-point body, 44-point control targets, 20-point side margins,
16-point corners and 16-point section gaps. Raster mockups illustrate the
direction; these are not measured or verified SwiftUI dimensions.

## Preserve the type-specific tools

| Type | Existing tools to retain |
| --- | --- |
| Alarm | Expanded native time wheel, usual times, nap shortcuts, name suggestions, seven-day repeat and sound/snooze settings. |
| Reminder | Date summary and picker, day shortcuts, all twelve time-grid buttons, List and Flag, supported recurrence choices, and the requested shared repeat/snooze presentation. |
| Event | Location, all-day, start/end, recurrence, writable calendar selection, alerts, availability, URL and notes. |

Reminder's four-column time grid remains:

| 09:30 | 12:00 | 18:30 | 22:00 |
| --- | --- | --- | --- |
| +10 min | +1 hr | +3 hr | +1 day |
| −10 min | −1 hr | −3 hr | −1 day |

## Keyboard interaction target

1. Explicitly focusing a name opens the keyboard and shows the insertion point.
   This is not a requirement to automatically focus the name when opening every
   type of creation screen.
2. Keep the shared header and focused name visible. The settings below remain
   a scrollable form at their normal sizes. Lower settings continuing below the
   keyboard viewport have not been removed.
3. Use the same `Hide keyboard` accessory on all three screens. It dismisses the
   keyboard and retains the draft, selections and scroll position. The keyboard
   `Done` key has the same dismiss-only role; it does not create an item.
4. The header checkmark remains the explicit submit action. After keyboard
   dismissal, return to the full form represented by Round 4.

## Implementation boundaries and open validation

The mockups do not establish that Reminder's create/save pipeline already
persists or delivers the requested sound and snooze settings. Those capabilities
need an implementation and validation before being presented as working.

Event's shared header is a visual target. Customization of Apple's native
`EKEventEditViewController` has not been validated; do not use private APIs or
claim the system editor already supports this chrome. Resolve that constraint
while preserving the existing event creation and selection behavior.

Any later implementation must preserve explicit submission, duplicate-submit
protection, drafts on failure, real persistence receipts, Activity and Undo,
existing-item editors, calendar-slot and deep-link routes, and nonblocking alarm
authorization. This checkpoint does not authorize AI/model changes, broader
recurrence behavior, provisioning changes or phone installation.

Actual keyboard input, scrolling, dismissal, save behavior, accessibility,
Dynamic Type, dark mode, localization and physical-device usability have not
been tested for these designs.

## Provenance

The board was generated with ImageGen. The individual images are static HTML
window exports of the aligned boards; no app or device was used to capture
them. [manifest.json](manifest.json) records their hashes and dimensions.
Full prompts, intermediate boards and QA journal artifacts remain in the primary
checkout's `tests/results/designs/create-round4-20261029/` and
`tests/results/designs/create-round5-20261029/`. This compact checkpoint includes
only the six review images and the agreed design rules.
