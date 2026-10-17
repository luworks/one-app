# Today — iPhone planner (native app + HTML prototype)

**Today** (formerly "one.") is an AI-native planner for iPhone that puts calendar, reminders and alarms in one app. Direction: data stays local; Apple Calendar and Apple Reminders are the source of truth (EventKit, read/write live); alarms use AlarmKit. Roadmap: **aggregate** (one place, a very good Today tab), then **optimize**, then **surpass**; match Apple Calendar / Reminders gestures and screens before improving on them. Details, rubric and eval: `docs/goal-and-rubric.md`.

The native SwiftUI app in `ios/` is the product and is ahead of the HTML/JS prototype in `src/`, which is a design reference only: fictional data, a fixed clock, no network calls. Habits were removed from both.

## Product principles (do not break these)
1. **AI prepares, the user decides.** AI never sends, moves or creates anything without an explicit tap. Every AI change appears as a preview card (`planCard`, `captureCard`) with Apply/Add and Undo. One approved exception: on a card that only changes Today's own data (planned times of reminders due today), "Always for 7 days" is that tap for a week; matching changes then apply by themselves, each with an Undo toast and an Activity entry. What a grant can never cover (Apple Calendar/Reminders writes, events, deadlines, deletes, anything that reaches other people, overdue items) is decided in one place, `AutonomyPolicy.decide` (unit-tested). Every change, by anyone, is recorded in the Activity ledger (`LedgerEntry`).
2. **Meetings stay fixed by default; tasks flex.** Events are never moved by drag, by plan cards (`DayPlanner` treats them as fixed obstacles) or by AI on its own. Flexible tasks move; linked alarms follow the task. The one exception: the user asks the AI to move a meeting (or taps an AI conflict card), and the AI shows a preview card that says who is affected (e.g. "invitation update goes to 4 attendees"). Only the user's Apply writes it, to this occurrence only, with Undo. Details: `docs/apple-intelligence.md` §2.6.
3. **Planned time ≠ deadline.** Moving work never moves `due`/`dueTime`.
4. **Stopping an alarm ≠ finishing a task.** Only "Mark task done" completes.
5. **Ideas aren't obligations.** Notes never become tasks unless the user taps "Make a task".
6. Overdue items stay visible and are never silently moved.

## Layout: native app (`ios/`, the source of truth)
- **4 tabs: Today · Calendar · Reminders · Alarms** (pills on top; swipe sideways on the top or bottom bar to switch). Each tab keeps its place when you leave and come back; the tab and the Calendar view also survive a restart (not in UI tests).
- **Today** = one day (any day, opened from Calendar, with "Back to today") as one timeline: an "N overdue" line on top, then events, planned tasks, reminders at their due time, alarms and quiet "Free 1 h 30 min" rows; reminders due that day with no time get a faint "Suggested" time in a free gap (Plan sets the planned time, never the deadline), else "Anytime today". On today it ends with a compact Tomorrow (first 3 items, all of it from 18:00); **Calendar** = Week (default, time grid) / Month / Year modeled on Apple Calendar, Day = the Today tab; which calendars show is a Setting. **Reminders** = modeled on Apple Reminders: small pills (wrapping, no cards, no empty band) for the smart lists Today/Scheduled/All/Flagged/Completed (with counts) and pinned lists, kept above the List so each pill has its own long-press menu, My Lists (color + symbol, create/rename/delete, reorder, pin), no Edit button or edit mode anywhere (long-press menu: Rename / Color & Icon / Pin / Delete; press-hold-drag to reorder; trailing swipe via `RowAction`; which smart lists show and their order is in Settings), list screens with an inline New Reminder row (note, date, flag, repeat, suggestions). Two-way sync with Apple Reminders via EventKit (`RemindersSync`, Apple wins on conflict). **Alarms** = modeled on Clock's Alarms tab: real alarms (`OneAlarm`, AlarmKit) plus items marked "Ring as alarm", split by a quiet switcher into Alarms · World Clock (Overlap-style: home first, time-of-day cards, sideways scrub, overlap chart) · Stopwatch · Timer (the Pomodoro focus timer: kitchen-timer dial, one AlarmKit countdown, plus any number of timers started by voice, "Start a timer in Today for 10 minutes"); no nag-until-done reminders. **Running timers show at the top of the Today tab** (up to 2 live countdown rows + "+N more"; Pause/Resume/Stop by swipe, tap opens the Timer tab). Today only sees timers it started: timers from the Clock app or Siri's built-in "set a timer" are not readable by any app (`docs/research/timer-siri-sync.md`), so the Timer tab says so.
- **Top-left is a menu button** (three lines) that opens the **sidebar**, like ChatGPT/Claude (a swipe from the left edge does too): Search at the top, past AI chats grouped by day (swipe Archive/Delete, long-press Rename, an Archived section; finished chats auto-archive, Settings → "Archive finished chats"), New chat and Settings at the bottom. Search lives only in the sidebar.
- **Bottom bar**: "Ask AI or add anything" (full-screen AI page) and a **+**: tap adds what fits the page (alarm on Alarms, event on Calendar, otherwise a reminder), press and hold for the menu. A new reminder opens the Due-style quick add (`QuickReminderSheet`: one-tap time grid, guesses from your own past reminders, `ReminderSuggest`); a new event uses Apple's own editor when Calendar access is on.
- **Gestures follow Apple**: tap the circle to complete; swipe right-to-left for actions, the same look everywhere (`RowActions`: Delete red and rightmost, full swipe deletes with an Undo toast; Flag, Archive, Pin); long-press menu (Show Details / Flag / Today / Tomorrow / Unschedule / Delete); a repeating event asks "this event or the series?" before Delete; Apple Calendar events open in Apple's own viewer; shake to undo. Events are never moved by drag; only flexible tasks move (Week grid).
- **AI**: on-device Apple Intelligence (Foundation Models) where available, the rule parser (`CaptureParser`) otherwise. One line can propose several items at once (`CaptureStack`); follow-ups edit the preview; edits to existing items ("move the dentist to 4") show a ChangeCard. "Tidy overdue" suggests a new date per overdue reminder (`OverdueTidy`; each row changeable, Apply writes the reminder date keeping its time, Undo). Nothing is written until Add/Apply. The empty Ask page shows 2-3 suggestion chips that are guesses from the user's own data (`AskSuggestions.swift`: rule candidates, each a full sentence that is checked to route to something actionable via `SentenceRoute`; the on-device model only re-ranks and rewords them, `AskSuggestionRanker`, 2 s cap, rules otherwise). Tests that need a particular action type the sentence instead of tapping a chip.
- **Widgets** (`ios/TodayWidgets`): Next Up on the Lock Screen and Home Screen, fed by a JSON snapshot in the App Group (`WidgetFeed`).
- **Share extension** (`ios/ShareExtension`): Share → Today turns text or a Safari page into an editable New Reminder with an optional day; Add puts it in an App Group inbox (`Shared/ShareInbox.swift`) that the app imports when it becomes active, with an Undo toast.
- Habits are gone (no tab, chips or streaks). The `Habit` SwiftData model stays in the schema, unused, so existing installs migrate.
- See `ios/README.md` for files, the test dataset, widgets and how to run on a phone.

## Layout: HTML prototype (`src/`)
- **Home (`ui.tab==='today'`, `vHome`)**: calendar pane on top (week strip, next item, due-today tray, timeline) + resizable split handle (peek / half / full) + conversation pane below. With no messages the calendar pane fills the screen (just the items: one quiet "N overdue" line, the overlap banner, due-today tray, timeline); the split handle and conversation pane appear with the first message. There is no AI brief card (removed on purpose: the page shows items, AI lives in the composer).
- **Composer**: always-visible bottom input (`#ask`). Statements are parsed into a capture card (`parse` → `captureCard`); questions go to `aiReply` (scripted). `isQuestion` decides.
- **Side drawer** (`renderDrawer`): ☰ button or left-edge swipe. Today / Calendar / Reminders / Notes / Alarms (no live summaries), conversations (`threads`), AI activity, Lock Screen & widgets mock, Settings.
- Secondary full views: `vCalendar` (week/month only; the day view is Home), `vTasks` (shown as "Reminders": tasks/projects/notes), `vAlarms` (real alarms only; reminders are a per-item alert, not a list).
- Sheets with detents (`openSheet`/`renderSheet`), iOS action sheets (`openMenu`), ring screen (`showRing`), toasts with Undo.
- `vToday` is the older list-style Today; it is no longer routed but kept for reference.

## Files
- `src/app.js` — all logic and rendering (vanilla JS, no framework). Seed data in `seed()`. Demo clock: `D0='2026-10-12'`, `NOW=9:41`.
- `src/style.css` — tokens on `:root` + dark mode (`prefers-color-scheme` and `[data-theme]`).
- `scripts/build.py` — inlines src into `dist/index.html`, `dist/artifact.html` (claude.ai artifact variant, no doctype/head) and `dist/worker.js` (self-contained Cloudflare Worker with a hashed CSP). Standard library only.
- `scripts/serve.mjs` — local preview of the built worker on :8787.
- `ios/` — the native SwiftUI app (`One.xcodeproj`, sources in `ios/One/`, SwiftData, Xcode 27 / iOS 27); `ios/TodayWidgets/` is the widget extension, `ios/Shared/` is compiled into both. See `ios/README.md` for running it on a phone with a free Apple ID.
- `ios/Eval/` — logic unit tests and the NL-capture eval (`run-eval.sh`); `ios/OneUITests/` — XCUITest journeys.
- `tests/fixtures/today-dataset.json` — the iOS test dataset (lists, reminders, events, alarms, chats; dates relative to the day it loads).
- `tests/e2e_home.py`, `tests/e2e_core.py` — Playwright (Python) end-to-end checks at iPhone size with real touch events.

## Workflow
```bash
python3 scripts/build.py          # always rebuild after editing src/
node scripts/serve.mjs            # http://localhost:8787  (open on phone via your LAN IP for real touch)
BASE=http://localhost:8787 python3 tests/e2e_home.py
BASE=http://localhost:8787 python3 tests/e2e_core.py
npx wrangler deploy               # from dist/ (wrangler.toml lives there) → one-calm-v8 worker
```
Test setup once: `pip install playwright && python3 -m playwright install chromium`.

iOS: one named simulator per session that runs tests (`Today-<purpose>`, iPhone 18 Pro Max, iOS 27; `xcrun simctl create Today-<purpose> com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0`) and its own `-derivedDataPath`, so nobody queues. Never run tests on another session's simulator. **Today-Dogfood** (`341B8786-E55B-4ECE-8720-BF1F2DF73899`) is the main session's.
```bash
ios/Eval/run-eval.sh              # logic tests, NL-capture eval, build warnings
ios/Eval/run-eval.sh --ui         # plus the XCUITest journeys
xcrun simctl launch 341B8786-E55B-4ECE-8720-BF1F2DF73899 com.luworks.one -uiTesting -dataset "$PWD/tests/fixtures/today-dataset.json"
```

## Conventions / gotchas
iOS app:
- `-uiTesting` = fresh in-memory store; add `-dataset <path>` to load the test dataset (debug builds only; Apple Calendar / Reminders sync stays off). UI tests use `TestData.launchArguments`; the tests that need Apple Calendar pass `-uiTestingCalendarSync`.
- Logic that can be unit-tested lives in plain Swift with no SwiftUI/SwiftData (`Logic.swift`, `ConversationHistory.swift`, `Dialogue.swift`, `QuickTime.swift`, `TimerDial.swift`, `Shared/WidgetSnapshot.swift`) and runs under `swift test` from `ios/` (tests in `ios/Eval/Tests/OneLogicTests`).
- Swipe actions come from `RowActions.swift` so every list looks the same; reminder changes go through `TaskActions` (Undo toast + shake to undo), list changes through `ListActions`.
- Settings → Delete All Data never touches Apple Calendar or Apple Reminders (the sync link is forgotten first).

HTML prototype:
- Every state change goes through `commit(label, fn)` so it is undoable and persisted; then `render(true)` keeps scroll positions.
- UI actions are `data-act="..."` attributes dispatched through the `A` map; add new actions there.
- Never use `alert/confirm/prompt` (the claude.ai artifact frame blocks them). Use `openMenu('confirm-…')`.
- Touch drag on iOS must use touch events (see the `TD` handler); pointer events get cancelled when the DOM under the finger is replaced. Don't re-render the dragged element mid-drag.
- Left-edge swipe conflicts with Safari's back gesture; it works from the Home Screen (standalone) and in a native app.
- `localStorage` key `one-v8`; Settings → Reset sample data restores the seed.
- Debug handle: `window.oneV8` (`data`, `go(tab)`, `openDrawer()`, `A`, `parse`, `needs`, `sendAI`, `reset`).

## Where it's going
1. **Aggregate** (done): Reminders tab like Apple Reminders with two-way EventKit sync (complete, rename, delete and repeat tested both ways), Calendar via EventKit, alarms, world clock, stopwatch and a focus timer via AlarmKit.
2. **Optimize** (in progress): on-device Apple Intelligence capture and edit and "Tidy overdue", always as a preview the user confirms; Lock Screen / Home Screen widgets with background refresh; Live Activities for the timer and snoozing alarms; Siri / Shortcuts (App Intents); a Share extension. Next: a full eval run on the rubric.
3. **Surpass**: improve on Apple's screens only after parity is demonstrated.

The prototype is not kept in lockstep; it will not get EventKit, AlarmKit or a live model (`aiReply` stays scripted).
