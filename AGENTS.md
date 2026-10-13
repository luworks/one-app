# AGENTS.md — handoff for coding agents (Codex)

You are taking over **one.**, a native SwiftUI iPhone app that Yuan (GitHub `luworks`) is building for personal use. Until 2026-10-13 it was developed by Claude Code; this file is the handoff. Read it fully before changing anything.

> `CLAUDE.md` at the repo root describes the **older HTML prototype** (`src/`, `dist/`, `scripts/`, `tests/`). Its *product principles* still apply to the iOS app; its layout, file list and workflow do not. The iOS app lives in `ios/`.

## 1. Working with Yuan

- Yuan writes in Chinese. Reply to Yuan in Chinese.
- **Everything in the app and repo is English:** UI strings, placeholders, sample data, docs, commit messages.
- Yuan sets direction; ask only for real product decisions. Otherwise pick a sensible default, say which, and keep going.
- Keep updates short: report the score per round and what changed. No play-by-play.

## 2. Product goal and style

A **minimal, AI-native, all-in-one personal planner** for iPhone: calendar, tasks, alarms, habits.

- **Coverage target:** what people use Apple Calendar, Apple Reminders, OmniFocus and Due for, without their complexity.
- **Style:** Notion / Linear / ChatGPT / Claude mobile. Calm, flat lists, one accent color (brand orange, from the app icon), system semantic colors, Dynamic Type, dark mode.
- **AI-native:** one typed or spoken line is the fastest way to do anything.
- **Goal:** 10/10 on the rubric in `docs/goal-and-rubric.md`, reached through iterate → test → score loops (§6).

### Product principles (never break)
1. **AI prepares, the user decides.** AI never creates, moves or sends anything without an explicit tap. Every AI change is a preview card with Add/Apply and Undo.
2. **Events stay fixed; tasks flex.** Neither AI nor drag moves an event. Only tasks move.
3. **Planned time ≠ deadline.** Moving a task never changes `due`.
4. **Stopping an alarm ≠ finishing a task.** Only an explicit "Done" completes.
5. **Ideas aren't obligations.** Notes never become tasks without a tap.
6. Overdue items stay visible and are never silently moved.

## 3. Decisions already made (don't relitigate)

| Decision | Detail |
|---|---|
| Native SwiftUI | No more HTML prototyping. iOS 17+ deployment target, SwiftData storage. |
| Distribution | Sideload with Yuan's **free Apple ID** (Personal Team). No paid developer account. Installs expire after 7 days; re-run from Xcode. |
| Language | English UI. User *data* is mostly Chinese, so CJK layout must look right. |
| Name and icon | Display name **"one."**; icon option **C** (dark background, white "1", orange period). Sources in `design/icon/` and `/mnt/project-files/design/icon/c-one.*`. |
| Top navigation | Notion-style **pill tabs at the top**: Today / Calendar / Tasks / Alarms. Custom-drawn, no system TabBar, no large titles. Tap to switch (tab swiping was removed so it doesn't fight the sidebar gesture). |
| Bottom bar | Always visible: 🔍 search circle, **"Ask AI" capsule** (opens the full-screen AI page), ✎ new-item circle. `glassEffect` on iOS 26, `.regularMaterial` fallback. |
| Sidebar | ChatGPT/Claude style: **swipe right from the left edge** or tap the avatar; the page slides right to reveal the drawer (view counts, new chat, settings, "Show Apple Calendar" toggle). |
| Lists | Plain style, no dividers, small grey collapsible section headers, swipe right = complete, swipe left = move to tomorrow (tasks only), long-press menu, press scale + haptics. |
| AI page | ChatGPT/Claude layout: greeting + suggestion chips, user bubbles only, AI replies unbubbled, growing rounded input with 🎤 / ↑. Captures appear as preview cards above the input. |

Full design spec (Chinese, with measured sizes and SwiftUI snippets): `/mnt/project-files/design/mobile-ui-reference.md` in the project files (not in the repo). Section 0 is the one-line summary, section 9 the implementation checklist; both are already implemented.

## 4. Repo layout

```
ios/
  One.xcodeproj           app + UI test targets, shared scheme "One", bundle id com.luworks.one
  OneInfo.plist           usage strings (Calendars, Microphone, Speech, AlarmKit), Home Screen quick actions
  One/                    app sources (~4k lines)
    OneApp.swift          entry; SwiftData container (OneTask, OneEvent, Habit); -uiTesting → in-memory store
    Models.swift          OneTask (planned time flexes, due never moves), OneEvent (fixed), Habit
    HomeView.swift        top pill tabs, Today page, bottom bar, sidebar host
    DayAgenda.swift, CalendarView.swift   day timeline with now line; Day / Week (time grid, drag tasks) / Month
    TasksView.swift, TaskActions.swift, Rows.swift   lists, tags, flags, repeat, checklist, swipe actions, undo
    AlarmsView.swift, Reminders.swift, Ringer.swift  notifications, Due-style nags, snooze, AlarmKit ring-as-alarm
    Habits.swift          editor, weekly targets, streaks, history, reminders
    AskView.swift         AI page, "Plan my day" preview card, scripted answers from local data (no LLM yet)
    Capture.swift         natural-language parser (EN + ZH) → preview card. Foundation-only.
    Logic.swift           pure logic: recurrence, reminder plans, streaks, DayPlanner. Foundation-only.
    CalendarSync.swift    EventKit read/write of system calendar events (events only, not Reminders)
    VoiceInput.swift      dictation via Speech
    QuickActions.swift, SearchView.swift, Sidebar.swift, Editors.swift, SampleData.swift, LaunchTimer.swift
    DevImport.swift       DEBUG-only importer for Yuan's real data (see §7)
  OneUITests/             XCUITest: JourneyTests (J1–J7 + sidebar), CalendarSyncTests, AlarmTests (device-only), LaunchTests
  Package.swift           SwiftPM eval package: compiles Capture.swift + Logic.swift for macOS
  Eval/
    run-eval.sh           one command: logic tests + NL-capture scores + build warnings (+ --ui)
    cold-start.sh         cold start budget (< 1000 ms)
    Tests/OneLogicTests/  CaptureEvalTests (train/test split, ratchet), HabitMathTests, capture-cases.json
docs/goal-and-rubric.md   goal, 8×10 claim rubric, hill-climb loop, round-by-round scoring log
design/icon/              icon sources
src/ dist/ scripts/ tests/  old HTML prototype (reference only; don't extend)
```

`Capture.swift` and `Logic.swift` must stay Foundation-only (no SwiftUI/SwiftData/UIKit), because `swift test` compiles them for macOS. Put new testable logic there.

## 5. Build and run (Yuan's Mac)

Checkout: `/Users/yuanlu/code/one-app`. Toolchain: **Xcode 27** with the iOS 27 simulator runtime; Xcode 27's **Device Hub** replaces Simulator.app. Builds only work on the Mac (cloud containers have no Xcode).

**Simulator**
1. Open `ios/One.xcodeproj`, pick an iPhone simulator (e.g. "iPhone 18 Pro Max"), ⌘R.
2. CLI equivalent: `ios/Eval/run-eval.sh` builds for the simulator; `--ui` also runs the UI tests on the first available iPhone simulator.

**iPhone (free Apple ID)**
1. Xcode → Settings → Accounts has Yuan's Apple ID; target One → Signing & Capabilities → Team = Personal Team.
2. iPhone connected, Developer Mode on, run destination = the phone, ⌘R.
3. First launch: Settings → General → VPN & Device Management → developer → Trust, then **Verify App**. Verification needs the phone online and able to reach Apple (Wi‑Fi, VPN/DNS filters off).
4. **Current blocker:** as of 2026-10-13 the phone is still stuck at "Unable to Verify App", so the latest build is installed but won't launch. Ask Yuan to tap Verify App before any device testing.

`ios/README.md` has the same steps (parts of its "What's in it" section are outdated; trust this file).

## 6. Scoring rubric and hill-climb loop

Source of truth: `docs/goal-and-rubric.md`. Summary:

- **8 dimensions × 10 yes/no claims:** Calendar, Tasks, Alarms & reminders, Habits, AI, Visual design, Interaction, Reliability. Score = claims passing. A claim counts only when **demonstrated** in the running app (simulator screenshot or test), never because the code "should" work.
- **Cheapest grader that fits:** unit tests for logic, NL-capture eval with a frozen **train/test split** (never read test failures while fixing; keep a parser change only if both go up; `CaptureEvalTests.ratchet`), XCUITest journeys J1–J7 with tap budgets, screenshot checklist for design (light, dark, largest Dynamic Type).
- **Loop per round:** run eval → pick weakest dimension → one focused root-cause change → re-run → keep only if target goes up and nothing regresses, else revert → ratchet → log the round in the scoring table → commit "Round N: …" and push. If the score stalls 2–3 rounds, audit the eval before touching the app.
- **Done** = every dimension ≥ 9 and J1–J7 within tap budgets. Target is 10 everywhere.

### Current score: 9.6 / 10 (round 18)

| Cal | Tasks | Alarms | Habits | AI | Design | Interact | Reliab |
|---|---|---|---|---|---|---|---|
| 10 | 10 | **8** | 10 | **9** | 10 | 10 | 10 |

Last full run: 12 UI tests pass, 1 device-only skipped; logic + NL eval green (train 24/24, test 22/22).

**What's left for 10/10 — all three are built but can only be verified on the iPhone:**
1. **Alarms 3** — notification Done / Snooze actions actually work from a delivered notification.
2. **Alarms 7** — AlarmKit "Ring as alarm" rings through Silent (the simulator always reports `.denied`; `AlarmTests` skips there).
3. **AI 10** — voice input (the simulator's audio input deadlocks).

Also open: the NL-capture eval is **saturated** (both splits at 100%). It needs new cases from Yuan's real phrasing (Chinese and English) — ask Yuan for sample sentences, add them to `capture-cases.json` (split them into train/test *before* fixing), then climb again.

## 7. Real data (private)

Yuan's real Calendar + Reminders export, used to develop against realistic data:

- File: `/Users/yuanlu/code/one-app-data/calendar-reminders.json` (~780 KB, outside the repo). Schema: `/Users/yuanlu/code/one-app-data/SCHEMA.md`.
- **Private. Never commit it, copy it into the repo, paste its contents (titles, notes, locations) into commits, PRs, issues, logs, screenshots you publish or chat.** Aggregate counts are fine.
- Load into the simulator (DEBUG builds only): launch with `-importData /Users/yuanlu/code/one-app-data/calendar-reminders.json` (Xcode scheme → Run → Arguments, or `xcrun simctl launch <sim> com.luworks.one -importData <path>`). It **replaces** all tasks and events in the store.
- Re-export (permissions already granted, no prompts):
  `open -n /Users/yuanlu/code/one-app-data/exporter/OneExport.app --args /Users/yuanlu/code/one-app-data/calendar-reminders.json 30 60`
  (30 days back, 60 ahead). Fallback CLI: `/Users/yuanlu/code/one-app-data/exporter/one-ekexport <out.json> 30 60`.
- Shape (America/Los_Angeles): 4 calendars, 458 event occurrences from 123 series (recurrences pre-expanded; key = id + occurrenceDate), 141 all-day, 8 multi-day. 6 reminder lists with **numbered Chinese names used as a GTD order** (`00 …` inbox through `05 …` someday): sort by the numeric prefix, display without it. 277 reminders, 76 open, 13 overdue, 40 recurring; priority never used. EventKit gives no subtasks, tags, flags or sections. Edge cases: one event in GMT; all-day events have null timeZone.

## 8. Prioritized next steps

1. **Device verification (needs Yuan).** Get the phone past Verify App, install, verify Alarms 3, Alarms 7, AI 10, update the log → 10/10 on the current rubric. Fix whatever breaks on the device.
2. **Apple Reminders sync (EventKit `.reminder`).** Yuan's tasks live in Reminders, but only Calendar events sync today. Read lists and reminders (respect the numbered GTD list order), write back completions and new tasks. Add claims to the rubric first.
3. **New real-world eval cases** for the parser from Yuan's sentences (see §6); re-run the ratchet.
4. **Schema migration.** SwiftData models have no `VersionedSchema` / migration plan yet; add one before the next model change so Yuan's on-device data survives updates (Reliability 7 must stay true).
5. **A live model behind the AI page.** Today `AskView` answers from local data with scripted logic and the parser is rule-based. Keep the preview-card contract (principle 1). Discuss provider/API key handling with Yuan before adding any network call.
6. **WidgetKit + Live Activities, App Intents / Siri, Share extension** — listed as the product's direction; each needs rubric claims before building.
7. Housekeeping: refresh `ios/README.md`; close draft PR #2 (icon assets, already merged into PR #1's branch); eventually raise the rubric bar (the current one is nearly saturated).

## 9. Git and PRs

- Repo `luworks/one-app`. All iOS work is on branch **`claude/project-thread-6mqxfv`**, draft **PR #1** ("Add native SwiftUI app skeleton"). Commit per round (`Round N: <change>`), push to that branch, update the scoring log in the same commit.
- Don't rewrite history on that branch (merge, don't rebase or force-push).
- Before pushing: `ios/Eval/run-eval.sh` (and `--ui` for UI changes) must be green with no new warnings in app code, and the cold start must stay < 1000 ms.
- Check `git status` before committing: nothing from `one-app-data/`, no screenshots containing real data.
