# Today — iOS app (SwiftUI)

The native app (formerly "one."). It puts calendar, reminders and alarms in one place. Direction: AI-native, data stays on the device, Apple Calendar and Apple Reminders are the source of truth (EventKit), alarms use AlarmKit. The HTML prototype in `src/` is the older design reference; the iOS app is now ahead of it. See `docs/goal-and-rubric.md` for the goal, roadmap and eval.

Requires Xcode 27 and iOS 27.

The display name is **Today**. The bundle id (`com.luworks.one`), the Xcode project and the target names (`One`, `OneUITests`) are unchanged.

## Run it on your iPhone (free Apple ID, no paid account)

1. Open `ios/One.xcodeproj` in Xcode.
2. Xcode → Settings → Accounts → add your Apple ID.
3. Select the **One** target → Signing & Capabilities → Team: pick your "(Personal Team)".
   If Xcode says the bundle identifier is taken, change `com.luworks.one` to something unique, e.g. `com.<yourname>.one`.
4. Plug in the iPhone, unlock it and tap Trust. On the phone turn on Settings → Privacy & Security → Developer Mode (it restarts).
5. Pick the iPhone as the run destination at the top of Xcode and press ⌘R.
6. First launch only: on the phone go to Settings → General → VPN & Device Management → your Apple ID → Trust.

With a free account the install expires after 7 days; just press ⌘R again with the phone connected.

## What's in the app

Four tabs: **Today · Calendar · Reminders · Alarms**, plus a left sidebar, search, and an "Ask AI or add anything" bar at the bottom.

- **Today** — one day: all-day events, overdue (one "N overdue" row that expands), due today, and the timeline with a "now" line. Tapping a day in Calendar opens it here, with a "Back to today" row.
- **Calendar** — modeled on Apple Calendar: Month (default; grid with colored dots and the selected day's events below), Week (time grid) and Year; Day opens the Today tab. Top row: year button, Today, Calendars (Apple's own list; the choice filters every view). With Calendar access on, + opens Apple's own event editor. Events are fixed; flexible tasks can be long-pressed and dragged in Week.
- **Reminders** — the older task list for now: filter chips (All / Inbox / Flagged / lists / tags), Unscheduled / Scheduled / Completed sections. Still labelled "Lists" and still stored locally. Being rebuilt to match Apple Reminders (smart lists, My Lists, live EventKit data); see the rubric.
- **Alarms** — modeled on the Alarms tab of Apple Clock: Edit and + in the bar, big light times with AM/PM, green switches, "Next alarm in …", Add/Edit Alarm sheet (wheel, Repeat, Label, Sound, Snooze). Every alarm is a real AlarmKit alarm that rings through Silent and Focus; items you marked "Ring as alarm" follow in "From reminders and events". AlarmKit only shows alarms this app scheduled: Apple's own Clock alarms cannot be read.
- **Gestures** (follow Apple Reminders / Calendar) — tap the circle to complete; swipe left for Delete (with an Undo toast) and Flag; long-press for Show Details / Flag / Today / Tomorrow / Unschedule / Delete. Apple Calendar events open in Apple's own event viewer.
- **Ask AI** — a typed or dictated line becomes a preview card (reminder or event); nothing is created until you tap Add. Questions get a local answer, and "Plan my day" proposes a schedule you apply or undo. There is no live model yet.
- **Apple Calendar** — sidebar → "Show Apple Calendar" reads system events (and saves new events there). Reminders are not read from Apple Reminders yet.
- **Habits are gone.** No tab, chips or streaks. The `Habit` model remains in the SwiftData schema, unused, so existing installs migrate without losing data.

## Files (`ios/One/`)

- `OneApp.swift` — app entry; builds the SwiftData container (`OneTask`, `OneEvent`, `OneAlarm`, `Habit`); `-uiTesting` uses an in-memory store.
- `Models.swift` — `OneTask` (planned time flexes, `due` never moves) and `OneEvent` (fixed).
- `OneAlarm.swift` — `OneAlarm` model (with its stable AlarmKit id). `AlarmEditor.swift` — the Clock-style row and the Add/Edit Alarm sheet. `AlarmCenter.swift` — live AlarmKit state (ringing, snoozing, authorization).
- `Habits.swift` — retired `Habit` model, kept only for schema migration.
- `Logic.swift` — pure logic with no SwiftUI/SwiftData so it is unit-testable: repeat rules, recurrence, day labels, `DayPlanner`, `ReminderPlan`, `AlarmPlan`.
- `HomeView.swift` — app shell: tab pills, bottom bar (search, Ask AI, new), sidebar drawer. `Drawer.swift` — the drawer drag/slide mechanics (state model + small modifiers, so a drag frame does not rebuild the page).
- `DayAgenda.swift` — the day view used by Today. `CalendarView.swift` — Month, Week and Year; `CalendarEntries.swift` — merges system events, own events and planned tasks for it.
- `TasksView.swift` — the Reminders tab (still the older list). `AlarmsView.swift` — the Alarms tab.
- `Rows.swift` — event and task rows with the swipe and long-press gestures; `TaskActions.swift` — complete, delete and undo toast.
- `Editors.swift` — task and event editors. `SearchView.swift` — search across tasks and events.
- `Capture.swift` — turns "明天下午3点 打电话给 Alex" (or English) into a preview card. `AskView.swift` — the AI page; `VoiceInput.swift` — dictation.
- `CalendarSync.swift` — EventKit bridge for Apple Calendar events, plus wrappers for Apple's own event editor, viewer and calendar chooser. Debug builds accept `-seedCalendarDemo` (`CalendarDemoSeed.swift`) to fill the system calendar with sample events.
- `Reminders.swift` — local notifications (Done / Snooze / Tomorrow actions, overdue badge). Despite the name this is not Apple Reminders. `Ringer.swift` — AlarmKit scheduling for alarms and "Ring as alarm" items.
- `Sidebar.swift` (full-screen conversation history: New chat, past chats grouped by day, Settings), `ChatThread.swift` (saved AI conversations, text only), `ConversationHistory.swift` (pure grouping/title logic), `QuickActions.swift` (Home Screen quick actions), `LaunchTimer.swift`, `SampleData.swift` (first-launch items; sidebar → Delete all data removes them), `DevImport.swift` (debug-only import of a private export).

Tests: `ios/Eval/` (logic unit tests, NL-capture eval, `run-eval.sh`, `cold-start.sh`) and `ios/OneUITests/` (XCUITest journeys). Run `ios/Eval/run-eval.sh` or `ios/Eval/run-eval.sh --ui`.

## Next

Rebuild Reminders like Apple Reminders, then read and write Apple Reminders through EventKit → Apple Intelligence (on-device Foundation Models) behind the composer, always as a preview → widgets.
