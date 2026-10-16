# one. — interactive iOS prototype

An HTML/JS prototype of **one.**, an AI-native all-in-one planning app for iPhone (calendar, tasks, alarms, notes, AI). It is a design prototype, not the production app: fictional data, a fixed clock, no network calls.

## Product principles (do not break these)
1. **AI prepares, the user decides.** AI never sends, moves or creates anything without an explicit tap. Every AI change appears as a preview card (`planCard`, `captureCard`) with Apply/Add and Undo.
2. **Meetings stay fixed by default; tasks flex.** Events are never moved by drag, by plan cards (`DayPlanner` treats them as fixed obstacles) or by AI on its own. Flexible tasks move; linked alarms follow the task. The one exception: the user asks the AI to move a meeting (or taps an AI conflict card), and the AI shows a preview card that says who is affected (e.g. "invitation update goes to 4 attendees"). Only the user's Apply writes it, to this occurrence only, with Undo. Details: `docs/apple-intelligence.md` §2.6.
3. **Planned time ≠ deadline.** Moving work never moves `due`/`dueTime`.
4. **Stopping an alarm ≠ finishing a task.** Only "Mark task done" completes.
5. **Ideas aren't obligations.** Notes never become tasks unless the user taps "Make a task".
6. Overdue items stay visible and are never silently moved.

## Layout (current)
- **Home (`ui.tab==='today'`, `vHome`)**: calendar pane on top (week strip, next item, due-today tray, timeline) + resizable split handle (peek / half / full) + conversation pane below. The first message is the AI morning brief (`briefHTML`), which holds the "needs you" cards.
- **Composer**: always-visible bottom input (`#ask`). Statements are parsed into a capture card (`parse` → `captureCard`); questions go to `aiReply` (scripted). `isQuestion` decides.
- **Side drawer** (`renderDrawer`): ☰ button or left-edge swipe. Today / Calendar / Tasks / Notes / Alarms with live one-line summaries, conversations (`threads`), AI activity, Lock Screen & widgets mock, Settings.
- Secondary full views: `vCalendar` (day/week), `vTasks` (tasks/projects/notes), `vAlarms`.
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
Native SwiftUI app. Prototype concepts map to: AlarmKit (alarms that ring through Silent/Focus), WidgetKit + Live Activities, App Intents/Siri, Share extension, EventKit for calendar sync, a live model behind `aiReply`.
