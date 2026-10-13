# one. — goal and scoring rubric

## Goal

A minimal, AI-native, all-in-one personal planner for iPhone: calendar, tasks, alarms and habits in one app.

- **Style:** Notion / Linear / ChatGPT mobile. Calm, dense, monochrome with one accent, system semantic colors, Dynamic Type, no chrome that doesn't earn its place.
- **Coverage:** what people use Apple Calendar, Apple Reminders, OmniFocus and Due for, without their complexity.
- **AI-native:** typing or saying one line is the fastest way to do anything. AI prepares, the user decides: every AI change is a preview the user confirms (see product principles in `CLAUDE.md`).

Target: **10/10** on every dimension below. Each round we score, fix the weakest dimension(s), and re-score.

## Dimensions (each 0–10)

| # | Dimension | 10/10 means | Benchmark |
|---|-----------|-------------|-----------|
| 1 | **Calendar** | Day / week / month views; create, edit, delete events; all-day and multi-day; recurrence; syncs with the system calendar (EventKit) | Apple Calendar |
| 2 | **Tasks** | Inbox; lists/projects; tags; planned date vs. due date; repeat; subtasks/checklist; notes; flag/priority; edit everything; complete/undo | Reminders, OmniFocus |
| 3 | **Alarms & reminders** | Local notifications for timed items; snooze from the notification; Due-style auto-repeat nag until done; alarms that ring through Silent (AlarmKit) | Due, Clock |
| 4 | **Habits** | Daily/weekly habits; one-tap check-in; streaks and history; reminder time | Streaks |
| 5 | **AI** | Natural-language capture (dates, times, repeat, lists, tags) with preview; ask about your day; plan-my-day suggestions; voice | ChatGPT, Todoist NL |
| 6 | **Visual design** | Consistent spacing/type scale, dark mode, empty states, icon, nothing misaligned at any Dynamic Type size | Notion, Linear |
| 7 | **Interaction** | Swipe actions, long-press menus, haptics, undo, fast paths (≤2 taps for common actions), no dead ends | Linear |
| 8 | **Reliability** | Data persists; no crashes; unit tests for parsing and scheduling logic; builds clean | — |

**Overall score** = the average, but the app isn't 10/10 until every dimension is at least 9.

## Scoring log

Scores are recorded per round, with what changed and what's weakest next.

| Round | Cal | Tasks | Alarms | Habits | AI | Design | Interact | Reliab | Avg | Notes |
|-------|-----|-------|--------|--------|----|--------|----------|--------|-----|-------|
| 0 | 3 | 3 | 1 | 0 | 3 | 6 | 5 | 4 | 3.1 | Baseline after Notion-style shell (1609475). No editing, no notifications, no habits. |
