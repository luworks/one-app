# Full-screen Chat, a new chat per tap, instant open — 2026-10-25

## Change

The bottom "Ask AI or add anything" field opens a full-screen Chat page (ChatGPT-style): a "Show chats" menu button
top-left opens the sidebar, Close top-right returns to the page, and the composer sits at the bottom with the keyboard
up. Every tap starts a new conversation. A chat opened from the sidebar closes back to the sidebar.

Draft and in-flight behavior on Close:

- Unsent draft: dropped (the next tap is a new chat, nothing stale is carried over).
- A conversation with at least one sent message is already saved and stays in the sidebar; an empty or draft-only
  chat saves nothing.
- An undecided capture card is recorded `ignored` when the closed page is torn down (~350 ms after Close).
- An AI reply still in flight is cancelled with the page. Every model path checks cancellation before writing, and
  the direct one-off reminder (`createSubmittedReminder`) is synchronous, so no partial write is possible.

## How opening is made fast

- The next new chat is built hidden (parked below the screen) 250 ms after bootstrap and 350 ms after each Close, so
  a tap only reveals it: queries, suggestion rules, model prewarm and the conversation view are already done.
- The keyboard is warmed once at launch (`KeyboardWarmup`: an offscreen `UITextView` focuses and resigns in one run
  loop turn; keyboard notifications during it are ignored by the shell).
- The editor focuses on the display refresh after the reveal (`CADisplayLink`), so bringing up the keyboard never
  holds back the frame that shows the page.
- The shell ignores keyboard notifications while Chat covers it (no page relayout under the keyboard).
- Suggestion chips are computed with the hidden page; the on-device model words them only once the page is visible
  (no inference per data change while hidden), and "chips shown" Activity events count only visible chips.
- Hidden pages unmount their header and editor: on this iOS version `accessibilityHidden` did not remove the parked
  page's controls from the XCUITest tree (observed: `ask-input`, Close, Open menu at y ≈ 1570–2382).

## Measurement

`ChatOpenLatencyTests/testFirstAndLaterOpenLatency` reads the app's own `PerformanceTrace` `page.ai` sample, which now
carries `first_frame_ms` (first display callback with the page on screen), `composer_laid_out_ms`, `focus_end_ms` and
`keyboard_will_show_ms` / `keyboard_did_show_ms`, all relative to the field's tap action. Three fresh processes, four
opens each; the third process taps as soon as the bar exists.

Owned Simulator via `./dev test ui` (iPhone, iOS 27, 60 Hz so frame times are quantized to ~16.7 ms). The host was
heavily loaded throughout (load average 40–115 from other sessions); process 0 of every run includes Simulator boot
noise and is excluded below. Values are ranges over the quieter processes 1–2.

| | Baseline (floating panel) | Full-screen, prebuilt |
|---|---|---|
| First open: editor laid out | 576–1424 ms | 50–59 ms |
| First open: page first frame | n/a (not traced) | 83 ms |
| First open: keyboard starts | 856–2056 ms | 328–460 ms |
| Later opens: editor laid out | 70–142 ms | 37–50 ms |
| Later opens: page first frame | n/a | 49.5–66 ms |
| Later opens: keyboard starts | 152–513 ms | 183–199 ms (one 347 ms) |

The 20 ms target is not met on the Simulator: about 25 ms is the SwiftUI update from the tap to the editor
(`native_shown_ms`), which re-evaluates the whole shell body; isolating Chat visibility in a small observable is the
next step. Keyboard animation (~400 ms from will-show to did-show) is the system's.

Evidence (primary checkout `tests/results/runs/`): baseline `today-qa-20261025-061438-59556a26`; final
`today-qa-20261025-071508-6e7960d2`; behavior journeys `today-qa-20261025-065928-dfb283c9` (8/8 passed:
ChatOpenLatency, ChatPanel ×3, PopulatedHistory ×2, Sidebar back-to-sidebar, TodayReminderCompletion chat draft);
regression `today-qa-20261025-072318-b486fa94` (16/16 passed before the 600 s runner cap: AIReminderRecovery ×3,
AskCardStays ×7, AskSuggestion ×4, ChatPanel ×2), `today-qa-20261025-073359-dd3df3cf` (ChatPanel tap-to-composer
passed) and `today-qa-20261025-073726-136e9f35` (TabMemory bottom controls passed after updating its stale + menu
and bar-order assertions from #154/#155).

## Not covered

Physical-device timings (Yuan Pro Max), real Foundation Models, VoiceOver traversal of the parked page, visual check
that the launch keyboard warm-up never flashes, and drag-down keyboard dismissal on an empty chat. The full UI suite
was not run; CI's merge gate does not run UI journeys.
