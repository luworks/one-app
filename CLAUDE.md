# Today — iPhone planner (native app + HTML prototype)

**Today** (formerly "one.") is an AI-native planner for iPhone that puts calendar, reminders and alarms in one app. Direction: data stays local; Apple Calendar and Apple Reminders are the source of truth (EventKit, read/write live); alarms use AlarmKit. Roadmap: **aggregate** (one place, a very good Today tab), then **optimize**, then **surpass**; match Apple Calendar / Reminders gestures and screens before improving on them. Details, rubric and eval: `docs/goal-and-rubric.md`.

The native SwiftUI app in `ios/` is the product and is ahead of the HTML/JS prototype in `src/`, which is a design reference only: fictional data, a fixed clock, no network calls. Habits were removed from both.

## Product principles (do not break these)
1. **AI prepares, the user decides.** AI never sends, moves or creates anything without an explicit tap. Every AI change appears as a preview card (`planCard`, `captureCard`) with Apply/Add and Undo.
2. **Meetings stay fixed; tasks flex.** Events are never moved by AI or drag. Only flexible tasks move; linked alarms follow the task.
3. **Planned time ≠ deadline.** Moving work never moves `due`/`dueTime`.
4. **Stopping an alarm ≠ finishing a task.** Only "Mark task done" completes.
5. **Ideas aren't obligations.** Notes never become tasks unless the user taps "Make a task".
6. Overdue items stay visible and are never silently moved.

## Layout: native app (`ios/`, the source of truth)
- **4 tabs: Today · Calendar · Reminders · Alarms**, plus a left sidebar, search and an "Ask AI or add anything" bar.
- **Today** = one day (any day, opened from Calendar); **Calendar** = Month (default) / Week / Year modeled on Apple Calendar, Day = the Today tab; **Reminders** = modeled on Apple Reminders (smart lists Today/Scheduled/All/Flagged/Completed, My Lists, create lists). Status: still the older "Lists" screen (`TasksView`) on local SwiftData; the rebuild and live EventKit reminders are next. **Alarms** = real alarms (`OneAlarm`, AlarmKit) plus items marked "Ring as alarm"; no nag-until-done reminders.
- **Bottom-right is a +** (target): tap adds what fits the page (alarm on Alarms, event on Calendar, otherwise a reminder), press and hold for the menu. Today it is still a menu button.
- **Gestures follow Apple**: tap the circle to complete; swipe left for Delete (Undo toast) and Flag; long-press menu (Show Details / Flag / Today / Tomorrow / Delete); Apple Calendar events open in Apple's own viewer. Events are never moved by drag; only flexible tasks move.
- Habits are gone (no tab, chips or streaks). The `Habit` SwiftData model stays in the schema, unused, so existing installs migrate.
- See `ios/README.md` for files and how to run on a phone.

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
- `ios/` — the native SwiftUI app (`One.xcodeproj`, sources in `ios/One/`, SwiftData, iOS 17+). See `ios/README.md` for running it on a phone with a free Apple ID.
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

## Conventions / gotchas
- Every state change goes through `commit(label, fn)` so it is undoable and persisted; then `render(true)` keeps scroll positions.
- UI actions are `data-act="..."` attributes dispatched through the `A` map; add new actions there.
- Never use `alert/confirm/prompt` (the claude.ai artifact frame blocks them). Use `openMenu('confirm-…')`.
- Touch drag on iOS must use touch events (see the `TD` handler); pointer events get cancelled when the DOM under the finger is replaced. Don't re-render the dragged element mid-drag.
- Left-edge swipe conflicts with Safari's back gesture; it works from the Home Screen (standalone) and in a native app.
- `localStorage` key `one-v8`; Settings → Reset sample data restores the seed.
- Debug handle: `window.oneV8` (`data`, `go(tab)`, `openDrawer()`, `A`, `parse`, `needs`, `sendAI`, `reset`).

## Where it's going
1. **Aggregate**: Reminders tab like Apple Reminders, then reminders read/written live through EventKit (Apple Reminders is the source of truth); Calendar already syncs via EventKit; alarms via AlarmKit.
2. **Optimize**: Apple Intelligence (on-device Foundation Models) turns typed text into reminders/events and helps tidy overdue items, always as a preview the user confirms. Then WidgetKit + Live Activities, App Intents/Siri, Share extension.
3. **Surpass**: improve on Apple's screens only after parity is demonstrated.

The prototype is not kept in lockstep; it will not get EventKit, AlarmKit or a live model (`aiReply` stays scripted).
