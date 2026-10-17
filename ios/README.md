# Today — iOS app (SwiftUI)

The native app (formerly "one."). It puts calendar, reminders and alarms in one place. Direction: AI-native, data stays on the device, Apple Calendar and Apple Reminders are the source of truth (EventKit), alarms use AlarmKit. The HTML prototype in `src/` is the older design reference; the iOS app is now ahead of it. See `docs/goal-and-rubric.md` for the goal, roadmap and eval.

Requires Xcode 27 and iOS 27.

The display name is **Today**. The bundle id (`com.luworks.one`), the Xcode project and the target names (`One`, `OneUITests`) are unchanged.

## Test environment

One named simulator per session that runs tests (`Today-<purpose>`, iPhone 18 Pro Max, iOS 27) with its own
`-derivedDataPath`, so nobody queues; never run tests on another session's simulator. **Today-Dogfood**
(`341B8786-E55B-4ECE-8720-BF1F2DF73899`) is the main session's; the commands below use it.

The test dataset lives in `tests/fixtures/today-dataset.json`: lists, reminders (flagged, overdue, completed, repeating,
one that rings), events (repeating, all-day, across the week), alarms (on, off, repeating, once) and chats (one archived).
Dates are relative to the day it loads. Load it into a fresh in-memory store (Apple Calendar / Reminders sync stays off):

```bash
xcrun simctl launch 341B8786-E55B-4ECE-8720-BF1F2DF73899 com.luworks.one -uiTesting -dataset "$PWD/tests/fixtures/today-dataset.json"
```

UI tests use it with `app.launchArguments = TestData.launchArguments`.

Tests that need Apple Calendar (`CalendarSyncTests`, `CalendarDeleteSyncTests`, `CalendarRecurringDeleteTests`) add
`-uiTestingCalendarSync` and use the simulator's own calendar, never a real one. Debug-only launch hooks for them
(handled in `HomeView`'s launch task, implemented in `CalendarSync`):

- `-debugCreateSystemEvent <title>` — a one-off event at the top of the current hour, as if made in the Calendar app.
- `-debugCreateRepeatingEvent <title>` — a daily event at the top of the current hour, starting yesterday.
- `-debugDeleteSystemEvent <title>` — deletes every event with that title (a whole series too), as if deleted in the
  Calendar app. Tests also use it to clean up.
- `-uiTestingStore <name>` — keeps the test store in a file, so a second launch sees what the first saved.

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

Four tabs: **Today · Calendar · Reminders · Alarms** as pills on top (swipe sideways on the top or bottom bar to switch tabs), a menu button top left that opens the sidebar, and an "Ask AI or add anything" bar with a **+** at the bottom. Each tab keeps its place when you switch away and back; the tab and the Calendar view survive a restart.

- **Today** — one day: all-day events, overdue (one "N overdue" row that expands), due today, and the timeline with a "now" line. Tapping a day in Calendar opens it here, with a "Back to today" row. Settings can hide overdue or alarms and turn off scrolling to now. On today, a quiet health line sits on top ("6,240 steps · slept 7 hr 12 min", read-only from Apple Health; tap for the Health sheet with steps, weight and sleep; Settings → Today → Health summary; HealthKit access is asked the first time it would show; sample data under `-uiTesting` and on the simulator). From 18:00 the Tomorrow section starts with **Review today**: done vs planned, what is left with Keep / Tomorrow / Later / Drop per item (a preview; Apply writes it, one Undo reverts; `due` never changes), and tomorrow's first items. Files: `TodayHealthLine.swift`, `HealthView.swift`, `HealthSource.swift`, `HealthLogic.swift`, `EveningReview.swift` (logic, unit-tested), `EveningReviewSheet.swift`. Tests: `HealthReviewTests`; screenshots in `docs/qa/health-review/` (`TEST_RUNNER_HEALTH_SHOTS=1`).
- **Calendar** — modeled on Apple Calendar: Week (default; time grid), Month (grid with the selected day's events below) and Year; Day opens the Today tab. One control row: the view switcher. Which calendars show is chosen in Settings. With Calendar access on, + opens Apple's own event editor and system events open in Apple's viewer. Events are fixed; flexible tasks can be long-pressed and dragged in Week.
- **Reminders** — modeled on Apple Reminders: small wrapping pills for the smart lists (Today, Scheduled, All, Flagged, Completed) with counts, then pinned lists (long-press a pill: Hide, or the list menu); My Lists with color and symbol, Add List. No Edit button: press and hold a list for Rename / Color & Icon / Pin / Delete, press, hold and drag to reorder, swipe from the right for Delete / Info / Pin. Settings picks and orders the smart lists (a pill's long-press menu can also hide one). A list screen has a big colored title, a collapsed Completed section and an inline **New Reminder** row (note, date, flag and repeat buttons, suggestions). Two-way sync with Apple Reminders through EventKit (`RemindersSync`): Apple wins on conflict, nothing is written before you connect, a pass never deletes more than 10 Apple items, planned time stays local.
- **Alarms** — modeled on the Alarms tab of Apple Clock: big light times with AM/PM, green switches, "Next alarm in …", Add/Edit Alarm sheet (wheel, Repeat, Label, Sound from bundled tones, Snooze, Snooze Duration). Every alarm is a real AlarmKit alarm that rings through Silent and Focus; items you marked "Ring as alarm" follow in their own section. AlarmKit only shows alarms this app scheduled: Apple's own Clock alarms cannot be read. A quiet switcher under the top bar splits the tab like Clock: **Alarms · World Clock · Stopwatch · Timer** (the last one is kept across tab switches and restarts). **World Clock** is modeled on the app Overlap: home (the device's time zone, starred) first, then your cities as cards tinted by the time of day there (night indigo, morning/evening blue, working hours 9–18 green) with "+N hrs · weekday, date"; drag sideways to move every clock in 15-minute steps (the capsule at the bottom says "3 hours from now", tap it for Now); Overlap shows a wave of who is working and the hours everyone overlaps; no Edit button: long-press a city for Move Up / Move Down / Delete, or press, hold and drag to reorder; + adds a city from a searchable list. **Stopwatch** like Clock's (Lap/Reset, Start/Stop, best lap green, worst red) keeps running across tabs and relaunches (it stores its start date). **Timer** is the Pomodoro card. + is hidden on Stopwatch and Timer. Logic: `ClockLogic.swift` (unit-tested).
- **Focus timer** — a restrained Pomodoro card on top of Alarms: turn the dial right to add time, left to take it away (one turn = 5 min, up to 90 min), or tap a chip (Focus 25 / Short break 5 / Long break 15), then Start; a custom dial value counts as Focus. One AlarmKit countdown at a time on the card (timers started by voice run next to it, see Siri below): it rings full-screen even with the app closed, with Pause / Resume and Cancel; the alert and Live Activity say "Focus" or "Break". A Focus round counts only when its countdown runs out (not when cancelled); today's rounds show as dots (●●●○, groups of 4) and start over at midnight. After a countdown ends the card offers one next step ("Start 5-min break", every 4th round "Start 15-min long break", after a break "Focus again") and a quiet "Done for now". No stats, no task linking. Logic: `Pomodoro.swift` (unit-tested).
- **+ (bottom right)** — tap adds what fits the page (alarm on Alarms, event on Calendar, otherwise a reminder); press and hold for New reminder / New event / New alarm. A new reminder opens the Due-style quick add: type what, set when with one tap on the grid (times of day, +/− nudges, days), with guesses from your own past reminders (on the device). Editing a reminder opens the full editor.
- **Sidebar** — like ChatGPT / Claude (menu button or a swipe from the left edge): Search at the top (reminders, events in the whole system calendar, alarms), past AI chats grouped by day (swipe Archive / Delete, long-press Rename, an Archived section), New chat and Settings at the bottom, and an **Activity** row under the title. Finished chats archive themselves (a week without a message, or an hour after everything they added is done); off in Settings → "Archive finished chats".
- **Gestures** (follow Apple Reminders / Calendar) — tap the circle to complete; swipe right to left for actions, which look the same in every list (Delete red and rightmost, a full swipe deletes with an Undo toast; Flag, Archive, Pin); long-press for Show Details / Flag / Today / Tomorrow / Unschedule / Delete. Deleting a repeating event asks "this event or the series?" first. Shake to undo.
- **Ask AI** — a typed or dictated line becomes preview cards; one line can hold several items, each with Add / Skip, plus Add all. Uses the on-device Apple Intelligence model where available and the rule parser otherwise; follow-ups edit the preview ("make it 4pm", "the second one"), and "move / delete X" on existing items shows a change card. Questions get a local answer, and "Plan my day" proposes a schedule you apply or undo. "Tidy overdue" (a chip, or "整理过期") suggests a new date for each overdue reminder: flagged and recent ones first, three a day, then tomorrow and next week; one-offs older than a month lose their date. Change any row (Today / Tomorrow / Next Week / No Date / Keep), Apply writes the reminder date keeping its time of day, and Undo puts it back. Nothing is written until you tap Add / Apply.
- **Activity** (sidebar) — the ledger of every change: who (You, Today AI, Siri, Share, Apple Reminders / Apple Calendar seen in sync), what, before → after, approved / automatic, grouped by day, filter chips All / AI / You / Agents, and Undo for reminder changes Today can put back (complete, plan, move, new date, add, delete). Append-only (an undo is a new entry), kept 1 year by default (Settings: 90 days / 1 year / forever), 150 rows per page with "Show more". It reads the Activity data store (see below); one line at the bottom says it is stored only on this iPhone.
- **Automatic changes** — the plan card ("Plan my day") offers Apply and "Always for 7 days". Under that grant, reminders due today without a time take their suggested free time by themselves when the app opens or comes back (and when you ask "Plan my day"), with a toast ("Planned 2 reminders into free time · Undo") and an Activity entry each. Only Today's own planned time changes. Overdue items, ones that ring as alarms, ones you placed yourself and ones the AI changed in the last 24 hours still ask. Settings → AI → Automatic changes lists grants with their end date and Revoke. The one policy: `AutonomyPolicy.swift` (unit-tested).
- **Settings** (from the sidebar) — **Appearance** first (System / Light / Dark, default System, saved as `today.appearance`; applies at once to the whole app including sheets and Apple's event editor; widgets and Lock Screen follow the system; files `Appearance.swift`, `AppearanceLogic.swift`, tests `AppearanceTests`, `AppearanceUITests`; screenshots of every screen in both modes: `TEST_RUNNER_APPEARANCE_SHOTS=<folder>`), Apple Calendar and Apple Reminders switches, the calendars list, Today options, AI → Automatic changes, Activity (count, Clear with confirmation), chat auto-archive, and Delete All Data (two confirmations; never touches Apple Calendar or Apple Reminders).
- **Settings, continued** — Apple Calendar and Apple Reminders switches, the calendars list, Today options, AI → Automatic changes, Activity → Activity data (what is recorded and where, pause, a switch per category, how long changes are kept, export, clear), chat auto-archive, and Delete All Data (two confirmations; never touches Apple Calendar or Apple Reminders).
- **Habits are gone.** No tab, chips or streaks. The `Habit` model remains in the SwiftData schema, unused, so existing installs migrate without losing data.

## Files (`ios/One/`)

- `OneApp.swift` — app entry; builds the SwiftData container (`OneTask`, `OneEvent`, `OneAlarm`, `OneList`, `ChatThread`, `Habit`); `-uiTesting` uses an in-memory store, `-dataset <path>` fills it from the test dataset (`TestDataset.swift`).
- `Models.swift` — `OneTask` (planned time flexes, `due` never moves) and `OneEvent` (fixed). `OneList.swift` — reminder lists and their palette; `ListActions.swift`, `ListEditor.swift` — create, rename, delete, color and symbol.
- `OneAlarm.swift` — `OneAlarm` model (with its stable AlarmKit id). `AlarmEditor.swift` — the Clock-style row and the Add/Edit Alarm sheet. `AlarmCenter.swift` — live AlarmKit state. `AlarmSounds.swift` — bundled tones. `TimerCard.swift`, `TimerDial.swift`, `TimerController.swift`, `TimerList.swift`, `TimerRows.swift`, `TimerPhrase.swift` — the timers.
- `Habits.swift` — retired `Habit` model, kept only for schema migration.
- `Logic.swift` — pure logic with no SwiftUI/SwiftData so it is unit-testable: repeat rules, recurrence, day labels, `DayPlanner`, `ReminderPlan`, `AlarmPlan`. Also pure: `ConversationHistory.swift`, `Dialogue.swift`, `QuickTime.swift`, `TimerDial.swift`.
- `HomeView.swift` — app shell: tab pills, menu button, bottom bar (Ask AI, +), sidebar drawer, each tab's kept place. `Drawer.swift` — the drawer drag/slide mechanics.
- `DayAgenda.swift` — the day view used by Today. `CalendarView.swift` — Week, Month and Year; `CalendarEntries.swift` — merges system events, own events and planned tasks for it.
- `RemindersView.swift` — the Reminders tab (smart lists, My Lists, Edit). `ReminderListScreen.swift` — one list with the inline New Reminder row (`NewReminderDraft.swift`). `QuickReminderSheet.swift` — Due-style quick add; `ReminderSuggest.swift` — its guesses; `ListGuess.swift` — which list a new reminder belongs to. `AlarmsView.swift` — the Alarms tab.
- `Rows.swift` — event and task rows with the swipe and long-press gestures; `RowActions.swift` — the shared swipe buttons; `EntryActions.swift` — the same gestures on calendar entries; `TaskActions.swift` — complete, delete, Undo toast and shake to undo.
- `Editors.swift` — task and event editors. `SearchView.swift` — search across reminders, events and alarms. `SettingsView.swift` — Settings. `FirstRun.swift` — first-run access to Calendar, Reminders and alarms.
- `Capture.swift` (rule parser), `Understanding.swift` and `AICapture.swift` (on-device model), `CaptureStack.swift` (several items from one line), `Editing.swift` (move / delete existing items), `Dialogue.swift` (follow-ups). `AskView.swift` — the AI page; `VoiceInput.swift` — dictation.
- `CalendarSync.swift` — EventKit bridge for Apple Calendar events, plus wrappers for Apple's own event editor, viewer and calendar chooser. Debug builds accept `-seedCalendarDemo` (`CalendarDemoSeed.swift`). `RemindersSync.swift` — two-way sync with Apple Reminders; debug-only hooks `-uiTestingAppleOp`, `-uiTestingAppOp` and `-uiTestingSyncDump` let `RemindersSyncBothWaysTests` change either side and read both back. `OverdueTidy.swift` — the tidy-overdue suggestions (unit-tested).
- `Ledger.swift` — `Ledger` (record, batched write into the Activity store, prune, Undo, `protectedRefs`), `LedgerMigration` (the one-time import), `GrantStore`, `AutoPlan`, the `AIGrant` model, and the old `LedgerEntry` model (kept in the schema, unused since the store took over, like `Habit`). `LedgerLogic.swift` (actors, filters, formatting, undo rules) and `AutonomyPolicy.swift` (what a grant may cover) are pure and unit-tested. `ActivityView.swift` — the Activity screen. UI tests: `LedgerTests` (`-uiTestingGrant` starts with the grant; screenshots in `docs/qa/ledger/`), `ActivityDataTests`.
- Activity data store — see "Activity data" below. Pure (compiled into `swift test`): `ActivityEvent.swift`, `ActivityStore.swift`, `ActivityRecorder.swift`, `ActivityLedger.swift`, `ActivityEvents.swift`, `ActivityExport.swift`; `Shared/ActivityOutbox.swift` (the only file extensions use). App side: `ActivityCenter.swift`, `ActivityDataView.swift`.
- `Reminders.swift` — local notifications (Done / Snooze / Tomorrow actions, overdue badge). Despite the name this is not Apple Reminders. `Ringer.swift` — AlarmKit scheduling for alarms and "Ring as alarm" items.
- `Sidebar.swift` (search, chats, New chat, Settings), `ChatThread.swift` (saved AI conversations, text only), `ChatAutoArchive.swift`, `QuickActions.swift` (Home Screen quick actions), `WidgetFeed.swift` (writes the widget snapshot), `LaunchTimer.swift`, `SampleData.swift` (first-launch items), `DevImport.swift` (debug-only import of a private export).

## Widgets (`ios/TodayWidgets/`, `ios/Shared/`)

One widget, **Next Up**: the next three things today (events, reminders with a time, alarms), merged and sorted by time,
all-day first. Lock Screen: rectangular (the next item only, readable at half width: a bold "15:00 · in 24:59" line with a live
timer, "Now · until 16:00", "Leave 14:20" or "All day", and a small "+2" for what else is left, then the title on up to two lines;
words in `Shared/LockScreenNext.swift`; or "Nothing else today" plus tomorrow's first item),
circular (next time in a ring of how much of today is done) and inline (above the clock). Home Screen: small (next item,
"in 2 hr") and medium (next three, each row opens Today on its day via `today://today?day=YYYY-MM-DD`).

- The app writes `widget-snapshot.json` (today, tomorrow and the day after, so "Tomorrow" still has data after midnight)
  into the App Group `group.com.luworks.one` (`WidgetFeed.swift`, called after data changes, when Apple Calendar changes
  and when the app goes to the background), then reloads timelines. It waits until the EventKit store is warm, so the
  first write after launch never drops system events. The snapshot also carries the Apple Calendar on/off switch and
  the hidden calendars.
- The extension never opens SwiftData. When Today has Apple Calendar on and the extension has full calendar access
  (inherited from the app), it reads Apple Calendar itself on every timeline and replaces the snapshot's Apple Calendar
  events (including Today's mirrored ones) with the live ones (`NextItems.merge`); otherwise it shows the snapshot as is.
  Timelines reload hourly and at midnight.
- Background refresh (`com.luworks.one.widgetRefresh`, a `BGAppRefreshTask` booked when the app goes to the background and
  re-booked by each run, about every three hours and never later than just after midnight): pulls Apple Reminders and rewrites the snapshot without the app being opened. iOS decides
  when it actually runs.
- `Shared/WidgetSnapshot.swift` is compiled into both targets (and into `swift test` as `OneShared`): the snapshot model,
  `NextItems` (selection, order, tomorrow fallback, live merge, timeline and reload dates), `WidgetItem.eventRows` and
  `WidgetLink`.
- Add it: long-press the Lock Screen → Customize → Lock Screen → tap the widget area under the clock (or the date line
  above it) → pick **Today** → Next Up. Home Screen: long-press → Edit → Add Widget → Today.

## Share extension (`ios/ShareExtension/`)

Share → **Today** from Safari or any app that shares text: the page title (or the text's first line) becomes the title, the
link and the rest of the text the note; pick No Date / Today / Tomorrow / Next Week; nothing is added until you tap Add.
The extension never opens SwiftData: it appends to `share-inbox.json` in the App Group (`Shared/ShareInbox.swift`, with a
file coordinator), and the app takes everything there when it becomes active, adds the reminders (which sync to Apple
Reminders when that is on) and shows an Undo toast. Tests: `ShareInboxTests` (logic), `ShareImportTests` (the app side,
via `-uiTestingShare <title>`) and `ShareSheetTests` (end to end through Safari's real Share sheet; skips without network).

## Activity data (`One/Activity*.swift`, `Shared/ActivityOutbox.swift`)

One app-private SQLite file, `Application Support/Activity/activity.sqlite` (system `SQLite3`, no dependency, WAL, `PRAGMA user_version` migrations), holds everything Today records about its own use. Research, schema reasons and numbers: `docs/research/activity-data-store.md`. It is the home of the Activity ledger (tier 1) and of the AI, usage and system events around it.

**What is recorded (four tiers).** 1 Changes: the ledger (`change.<action>`, `grant.*`) with before → after, approval, Undo links and Undo snapshots. 2 AI: `ai.turn` (intent, route, language, length; no text unless "Keep the text of my messages" is on), `ai.card.shown` / `ai.card.resolved` (applied, edited, skipped, cancelled, ignored; edited fields by name in `props`, the words before and after in the `content` table), `ai.chips.shown` / `ai.chip.tapped`, `ai.undo`. 3 Usage: `ui.screen.open` (tab changes), `ui.quickadd.commit` (ms). 4 System: `sys.share.import`, `sys.share.add`, `sys.widget.refresh`, `sys.intent.run`, `sys.sync.conflict`. Defaults: all four on; changes kept 1 year (Settings: 90 days / 1 year / forever); AI decisions 180 days, usage 30 (counts rolled up per day first), system 90, Undo snapshots 30. The policy's "you chose this time" look-back stays 90 days whatever the setting.

**Rules.**
- Only the app process opens the file. The Share extension and the widget append one small JSONL file each to the App Group folder `activity-outbox/` (`ActivityOutbox`); the app imports them when it becomes active, in one transaction, then deletes them (same idea as `ShareInbox`). App Intents run in the app process and record normally.
- Personal content stays in its own places: `title` / `before_txt` / `after_txt` columns, the `content` table (edited-card words, optional chat text) and the `snapshot` table; `props` never holds free text. `ActivityEvent.redacted()` drops all of it.
- Rows are immutable and carry a UUID and a device id (Undo is a new row with `undo_of`), so they can be merged by union later. Reads are paged by a `(ts, id)` cursor (the Activity screen loads 150 rows at a time); every query has an index (a test checks the query plan); writes are batched (the recorder buffers about 1.5 s or until the app goes to the background).
- Paused, or a category switched off: events are dropped before they are buffered. Because an automatic change without an Activity entry and an Undo would break "AI prepares, the user decides", nothing applies by itself under a grant while Changes is off or recording is paused.
- The old SwiftData `LedgerEntry` rows are copied into the store once at launch (`LedgerMigration` → `LedgerImport`: batches of 500, keyed on the entry's UUID, so it is idempotent and resumes after a crash; the flag `ledger_migrated` is set only when every old row is in the store). The old rows are deleted only in a later launch than the verified copy. The model stays in the schema, unused, so existing installs migrate. A file SQLite cannot read is moved aside (`.damaged-<time>`), never deleted.
- Settings → Activity → Activity data: what is recorded and where, pause, a switch per category, keep chat text, retention, Export (JSON Lines: every field including snapshots and card diffs; CSV: one flat row per event, RFC 4180) through the share sheet, Clear (names the count; also the old rows). Delete All Data clears it too. The Activity screen carries one line saying it is stored only on this iPhone.

**Tests.** `swift test` from `ios/`: `ActivityStoreTests` (schema and migrations, paging, filters, search incl. Chinese, retention and rollups, snapshots, export formats, query plans, corrupt file), `ActivityRecorderTests` (buffering, settings, event shapes, outbox round trip across the extension/app boundary), `ActivityLedgerTests` (mapping, import, dry run, resume). UI: `ActivityDataTests` (Settings page, pause, Clear, paging 400 rows, export sheet, paused ⇒ no automatic changes, and the real import of old `LedgerEntry` rows across two launches) and `LedgerTests`. Debug launch hooks: `-uiTestingActivityRows <n>` (n synthetic changes), `-uiTestingLegacyLedgerRows <n>` (n old SwiftData ledger rows, to test the import), `-uiTestingActivityPaused`, and `-uiTestingStore <name>` also keeps `<name>.activity.sqlite` in the temp folder.

**Speed.** `ACTIVITY_BENCH_ROWS=100000 swift test --filter testBenchmarkLarge` prints insert and query timings on the Mac. On a phone, debug builds have Settings → Activity data → "Run speed test (100,000 rows)", which does the same in a throwaway file and shows SQLite's version, whether FTS5 and the JSON functions exist, and the timings. Mac numbers (Apple Silicon, `swift test` debug build, 100,000 rows, including building the events in Swift): insert about 42,000 rows/s (2.4 s, 47 MB file), newest page of 150 in 1.8 ms, a page 10,000 rows down in 1.6 ms, a one-day count in 0.1 ms, a `LIKE` search over titles in 29 ms; SQLite 3.51, FTS5 and the JSON functions present. The research document's release-build figure for raw inserts was 270,000 rows/s. No iPhone number exists yet: it needs a Debug install on a phone.

**Export formats.** One event per JSONL line: `uid, device, ts` (unix ms), `tz` (minutes east), `day`, `tier`, `kind`, `actor`, `channel`, `session`, `thread`, `subject_kind`, `subject_ref`, `approval`, `undo_of`, `title`, `before_txt`, `after_txt`, `before_ts`, `after_ts`, `props` (object), `v`, plus `snapshot` (base64) and `content` (`[{field, before, after}]`). Unknown keys are ignored when reading.

### Later (not built; needs the paid Apple Developer account or our own backend)
- **iCloud / CloudKit sync.** A free Apple ID cannot use CloudKit or push (verified in the research document). The schema is ready: `uid` is the record name, rows are immutable with a `device` id, `sync` (0 = local only) marks what was uploaded, `props` is a JSON string. Plan: `CKSyncEngine` over tiers 1 and 2 into a private zone, encrypted fields for `title` / `before_txt` / `after_txt` / `props` / `content`, tombstones for Clear, zone delete on Delete All Data; usage and system events stay on the device. The JSONL line above is the payload shape.
- **Redacted upload to the product team.** A separate pipeline that does not exist: our own backend, `ActivityEvent.redacted()` (drops titles, text, thread, refs; coarsens time to the hour) shown to the user before sending, explicit opt-in, and a rewording of "data stays local" in `CLAUDE.md`. Decision deferred (document §7.3).
- Phase 3 to 5 of the document: coalescing and a rollup job beyond what prune does, local learning loops (chip ranking from tap history, "Save as eval case" for edited cards), a diagnostics export with preview.

## Siri, Spotlight and Shortcuts (`One/AppIntents.swift`)

App Shortcuts, English phrases in code and Simplified Chinese in `One/AppShortcuts.xcstrings`: **Add Reminder**
(a title or one sentence, read by `CaptureParser`; always a reminder), **Start Timer** ("Start a timer in Today", "Set a
Today timer": Siri asks "How long?" and `TimerPhrase` reads "ten minutes", "an hour and a half", "十分钟", "半小时"),
**Start Timer for…** ("Start a timer in Today for 10 minutes": the length is one of a few presets so Siri hears it in one
breath), **What's Next Today** (the Next Up widget's three items, spoken plus a snippet) and
**Open Today** (the `today://today` link). They run in the app's process on the app's store (`OneStore` in `OneApp.swift`).
Pure parts: `One/IntentLogic.swift`, `Shared/NextUpSpeech.swift` (tested in `IntentTests`).

**Timers** (`TimerController.swift`, `TimerList.swift`, `TimerRows.swift`, `TimerIntents.swift`): every timer Today starts is a
real AlarmKit countdown, as many as you like (the Pomodoro card keeps one Focus/break timer; voice timers run next to it).
They show on the Today tab as up to two live rows at the top (`Text(timerInterval:)` counts down on its own; swipe for
Pause/Resume/Stop, tap to open the Timer tab, "+N more") and in a list under the Pomodoro card. End times live in
`TimerStore` (UserDefaults), because AlarmKit has no fire date; `TimerController.refresh()` lines them up with
`AlarmManager.alarms` on launch, foreground and every AlarmKit update (`TimerList.reconcile`), so a timer started by Siri
while the app was closed is there at once. Debug UI tests: `-uiTestingTimers 600:Pasta,1500,300:Tea:paused` seeds timers and
swaps AlarmKit for a fake (the simulator denies AlarmKit); see `TodayTimerTests`. Also adopts the iOS 27 **Clock schema**
(`@AppIntent(schema: .clock.createTimer / pauseTimer / resumeTimer / cancelTimer`, `.clock.timer` entity) so Siri can hand
"set a timer" to Today. What iOS allows and what it does not (timers made in the Clock app or by Siri's built-in "set a
timer" cannot be read by any app): `docs/research/timer-siri-sync.md`.

Tests: `ios/Eval/` (logic unit tests, NL-capture eval, `run-eval.sh`, `cold-start.sh`) and `ios/OneUITests/` (XCUITest journeys). Run `ios/Eval/run-eval.sh` or `ios/Eval/run-eval.sh --ui`.

## Next

A full eval run on the rubric (scores restart from the re-scoped dimensions) → climb the weakest dimension.
