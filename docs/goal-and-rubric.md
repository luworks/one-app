# one. — goal, eval and hill-climbing plan

## Goal

A minimal, AI-native, all-in-one personal planner for iPhone: calendar, tasks, alarms and habits in one app.

- **Style:** Notion / Linear / ChatGPT mobile. Calm, dense, monochrome with one accent, system semantic colors, Dynamic Type.
- **Coverage:** what people use Apple Calendar, Apple Reminders, OmniFocus and Due for, without their complexity.
- **AI-native:** one typed or spoken line is the fastest way to do anything. AI prepares, the user decides: every AI change is a preview the user confirms (product principles in `CLAUDE.md`).

Target: **10/10 on every dimension.**

## How we measure (eval design)

Method adapted from Anthropic's posts on [eval design and hill-climbing](https://claude.dev/blog/automating-eval-design-and-hillclimbing/) and [making claude.ai faster](https://claude.dev/blog/how-we-made-claude-ai-faster/):

1. **Score checkable claims, not vibes.** Each dimension is 10 yes/no claims. Score = number of claims that pass. A claim passes only when it is demonstrated in the running app (simulator screenshot or test), not when the code "should" work.
2. **Cheapest grader that fits.**
   - *Programmatic* where possible: unit tests for logic (parser, streaks, scheduling), an NL-capture eval with expected outputs, and UI tests for core journeys.
   - *Judge with a checklist* for design: screenshots of every screen in light, dark and the largest Dynamic Type size, checked against the design claims below.
3. **Claims mirror real use.** They come from what people actually do in Apple Calendar, Reminders, OmniFocus, Due and habit trackers, plus Yuan's feedback. No claim is added just because it's easy to pass.
4. **Hold-out set for the AI parser.** NL-capture cases are split into `train` (failures may be read while fixing) and `test` (never read while fixing). A parser change is kept only if both go up.
5. **Core journeys and tap counts** (from the "faster" post: pick the few journeys that cover most use, measure them, ratchet):
   - J1 Add a task with a time from one line
   - J2 See what's left today
   - J3 Complete a task
   - J4 Add an event
   - J5 Check in a habit
   - J6 Get reminded at the right time and act from the notification
   - J7 Find something
   Each journey records taps from the home screen; the budget can only go down.

## Hill-climbing loop

Each round:

1. Run the eval (build, simulator walkthrough of J1–J7, screenshots, tests) and fill the claim checklist.
2. Pick the **weakest dimension**, read its failing claims, and find the root cause.
3. Make **one focused change** aimed at that root cause (not per-case hacks).
4. Re-run. **Keep** if the target dimension goes up and nothing else goes down; otherwise **revert**. For the parser: keep only if train and test both improve.
5. Ratchet: a passing claim, test or tap budget may never regress afterwards.
6. Log the round below and push to PR #1.
7. If the score stalls for 2–3 rounds, stop and audit the eval itself (ambiguous claim, broken test, wrong grader) before changing the app again.

Humans set direction: Yuan decides product questions (what a claim should mean, priorities between dimensions). Claude asks only then.

## Claim checklists (10 per dimension)

### 1. Calendar (benchmark: Apple Calendar)
1. Day timeline with a "now" line
2. Day picker / week strip
3. Week view
4. Month view
5. Create an event
6. Edit an event
7. Delete an event
8. All-day and multi-day events
9. Recurring events
10. Reads and writes the system calendar (EventKit)

### 2. Tasks (benchmark: Reminders, OmniFocus)
1. Create a task from one line
2. Edit title, notes, planned time, deadline
3. Complete and un-complete, with undo
4. Planned time and deadline are separate (moving one never moves the other)
5. Inbox of unscheduled tasks
6. Lists / projects
7. Tags
8. Repeating tasks
9. Subtasks / checklist
10. Flag or priority

### 3. Alarms & reminders (benchmark: Due, Clock)
1. Upcoming timed items listed in one place
2. Local notification fires at the task/event time
3. Notification actions: Done and Snooze
4. Due-style nag: repeats until done or dismissed
5. Snooze presets (5 min, 1 h, tomorrow)
6. Per-item reminder offset (e.g. 10 min before)
7. Alarms that ring through Silent (AlarmKit)
8. Turn a reminder on/off from the list
9. App badge shows overdue count
10. Clear permission prompt with a reason, and a recovery path if denied

### 4. Habits (benchmark: Streaks)
1. Create a habit
2. One-tap check-in
3. Streak count
4. Last-7-days history
5. Delete a habit
6. Edit name and icon
7. Weekly targets (e.g. 3× per week)
8. Reminder time per habit
9. Longer history / stats
10. Today's habits shown on the Today page

### 5. AI (benchmark: ChatGPT, Todoist natural language)
1. Understands day words (today, tomorrow, 明天…)
2. Understands times (3pm, 15:00, 下午3点)
3. Preview card; nothing is created without a tap
4. English and Chinese input
5. Weekdays and dates ("Friday", "Oct 20")
6. Repeat ("every day", "weekly")
7. Decides task vs. event vs. habit
8. Answers questions about your day
9. Suggests a plan for the day (preview, user applies)
10. Voice input

NL-capture eval accuracy (train / test) is tracked separately in the log.

### 6. Visual design (benchmark: Notion, Linear) — judged on screenshots
1. One accent color; everything else semantic system colors
2. Dark mode looks right on every screen
3. Largest Dynamic Type: no truncation or overlap on Today and Tasks
4. Consistent 20 pt horizontal margins and row rhythm
5. Every list has a designed empty state
6. No duplicated or redundant labels
7. App icon
8. Top pills and bottom bar match the reference spec
9. Editors and sheets feel native and uncluttered
10. Typography scale is consistent (one title, one body, one caption style)

### 7. Interaction (benchmark: Linear)
1. Swipe to complete
2. Swipe to defer
3. Long-press menu on every item
4. Haptics on key actions
5. Undo after complete / delete
6. Add a timed task in ≤ 3 taps plus typing (J1)
7. Sidebar like ChatGPT/Claude: swipe right from the left edge (or tap the avatar) slides the page over to a drawer
8. Drag to reschedule on the timeline
9. Home Screen quick actions or widget
10. No dead ends: every sheet closes, every tab can return to today

### 8. Reliability
1. Builds with no warnings in app code
2. Data persists across relaunch
3. Unit tests for the capture parser
4. Unit tests for streaks and scheduling
5. UI tests for core journeys
6. No crash walking J1–J7
7. Schema changes migrate without data loss
8. One command runs all tests
9. Cold start measured and under budget
10. Eval runner prints the scores

**Overall** = average of the 8 dimensions. Done when every dimension is ≥ 9 and J1–J7 meet their tap budgets.

## Scoring log

| Round | Cal | Tasks | Alarms | Habits | AI | Design | Interact | Reliab | Avg | Change |
|-------|-----|-------|--------|--------|----|--------|----------|--------|-----|--------|
| 0 | 3 | 3 | 1 | 0 | 4 | 5 | 5 | 2 | 2.9 | Notion-style shell (1609475) |
| 1 | 5 | 4 | 1 | 5 | 5 | 6 | 6 | 3 | 4.4 | English UI, habits, task/event editors (0d78750) |
| 2 | 5 | 4 | 1 | 5 | 5 | 6 | 6 | 6 | 4.8 | Eval harness: `ios/Eval/run-eval.sh`, logic unit tests, NL-capture eval. Capture train 6/15, test 5/14 |
| 3 | 5 | 4 | 6 | 5 | 5 | 6 | 6 | 6 | 5.4 | Reminders: local notifications (verified firing in simulator), Due-style nags, Done/Snooze/Tomorrow actions, per-item offset, bell toggle, badge, permission card. Actions not yet demonstrated, so claims 3–5 not counted |
| 4 | 5 | 4 | 6 | 5 | 5 | 8 | 7 | 6 | 5.75 | Sidebar (Yuan's ask), app icon "one." (C) and brand orange accent |
| 5 | 5 | 9 | 6 | 5 | 5 | 8 | 7 | 7 | 6.5 | Tasks: lists, tags, flag, repeat (next occurrence on complete, verified), checklist, filter chips, undo toast. Undo not yet demonstrated end-to-end (tool latency), so Tasks 3 / Interaction 5 not counted. RepeatRule unit tests |
| 6 | 9 | 9 | 6 | 5 | 5 | 8 | 7 | 7 | 7.0 | Calendar: Day / Week (time grid) / Month views, all-day and multi-day events, repeating events (occurrences expanded everywhere), event editor with all-day/repeat. Recurrence unit tests. EventKit still missing |
| 7 | 9 | 9 | 6 | 5 | 8 | 8 | 7 | 7 | 7.4 | AI parser rewrite (prepositions, weekdays, dates, repeat, noon, bare hours, time ranges) and task/event/habit detection with a switch on the preview card. NL eval v1: train 6→15/15, test 5→14/14. v2 cases (kind, duration) written before the code: train 24/24, test 22/22. Eval now saturated: next cases should come from Yuan's real inputs |
| 8 | 9 | 9 | 6 | 9 | 8 | 8 | 7 | 7 | 7.9 | Habits: editor (name, 20 icons, weekly target, reminder time), 5-week history, current/best streak, "x/3 this week" for weekly goals, habit chips on Today, habit reminders with Check in action. weekCount/bestStreak tests |
| 9 | 9 | 10 | 6 | 9 | 8 | 8 | 8 | 9 | 8.4 | XCUITest journeys J1–J7 + sidebar, all 8 pass on a fresh in-memory store (`run-eval.sh --ui`). Undo now demonstrated (J3). Taps: J1 2, J2 0, J3 1, J7 1. New-item editors and search open with the keyboard ready. Dev region set to English |
| 10 | 9 | 10 | 6 | 9 | 8 | 9 | 8 | 9 | 8.5 | Design pass: dark mode checked on Today; largest accessibility text size: checkbox overlap and truncated details fixed, top/bottom chrome capped at XXXL; fade under the floating bar. Habits empty state still plain |
| 11 | 9 | 10 | 6 | 9 | 8 | 9 | 8 | 9 | 8.5 | AlarmKit "Ring as alarm" on tasks/events (iOS 26+), usage string via OneInfo.plist, denied-state copy. Simulator always answers .denied, so ringing must be verified on a device: AlarmTests skips on simulator. Not counted yet |
| 12 | 9 | 10 | 8 | 9 | 8 | 9 | 9 | 9 | 8.9 | Reminder plan (first fire + 5/10/20-min nags, snooze 10 min / 1 h) moved to Logic.swift with unit tests (Alarms 4, 5). Home Screen quick actions Ask AI / New task / New event, verified in the simulator (Interaction 9) |
| 13 | 10 | 10 | 8 | 9 | 8 | 9 | 9 | 9 | 9.0 | EventKit: sidebar toggle "Show Apple Calendar"; system events appear in Today / Week / Month; events created in one. are saved to the system calendar (with repeat) and deduplicated. CalendarSyncTests round-trips an event through the system calendar. Full suite: 10 UI tests pass, 1 device-only skipped |

Round 1 failing claims, weakest first: Alarms (2–10), Reliability (3–5, 8–10), Calendar (3, 4, 8–10), Tasks (3 undo, 6–10).

## How to run the eval

```bash
ios/Eval/run-eval.sh       # logic tests, NL-capture train/test scores, app build warnings
ios/Eval/run-eval.sh --ui  # plus the UI journeys J1–J7 on a simulator
```

The NL-capture cases live in `ios/Eval/Tests/OneLogicTests/capture-cases.json` (split fixed; never read test failures while fixing). The ratchet is `CaptureEvalTests.ratchet`.

## Plan

- ~~Round 2 — eval harness~~ done.
- ~~Round 3 — Alarms~~ done (AlarmKit and demonstrating notification actions still open).
- ~~Round 4 — Sidebar + icon~~ done. Tab swiping was dropped so the edge swipe can open the sidebar.
- ~~Round 5 — Tasks~~ done.
- **Next — UI tests (XCUITest)** for J1–J7 so undo, notification actions and journeys are demonstrated by a program, not by hand.
- ~~Round 6 — Calendar~~ done (EventKit still open).
- ~~Round 7 — AI parser~~ done. Saturated; needs new real-world cases.
- ~~Round 8 — Habits~~ done.
- ~~Round 9 — UI tests~~ done.
- ~~Round 10 — Design~~ done.
- ~~Round 11 — AlarmKit~~ built; needs a device run (blocked on the iPhone's Verify App step).
- ~~Round 12 — reminder logic tests, quick actions~~ done.
- ~~Round 13 — EventKit~~ done.
- **Round 14 — AI:** plan-my-day preview; voice input. **Interaction:** drag to reschedule.
- Device-only: AlarmKit ringing, notification actions (needs the iPhone verified).

- Then re-score and keep climbing whatever is weakest.
