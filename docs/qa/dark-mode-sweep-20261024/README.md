# Dark mode contrast sweep (2026-10-24)

Simulator: Today-DarkMode-20261024, iPhone 17 Pro, iOS 27, TodayMock with `tests/fixtures/today-dataset.json`. Reviewed Dark and Light appearances, increased contrast, and Smart Invert. Raw screenshots are retained in the primary checkout's `tests/results/dark-mode-sweep-20261024/`, not in Git.

Inspected: Today; Calendar Week, Month, and Year; Reminders overview and Home list, inline new reminder, quick reminder, task editor; Clock alarms, alarm editor, World Clock empty state, stopwatch, and timer; sidebar, Search empty state, Settings overview and Activity data, Activity empty state, plus menu; Chat tidy card. Checked visible colors and relevant SwiftUI color/style expressions in the other requested flows. A full interaction and visual pass of every smart list, Settings subpage, event viewer, Chat capture/change card, swipe action, toast, and Health sheet was not completed.

Fixed visible low contrast: Today free-time secondary text; Reminders inline placeholder and empty due-date controls; quick reminder date control; custom list names and glyphs; Calendar selected/today markers, event icon, draft and now labels; Chat tidy Apply label. Applied the same contrast rule to related Chat capture/change actions, Calendar permission and Clock permission buttons, and other filled labels, and strengthened selected secondary text in Search, Health, World Clock, and capture provenance.

Left outside this change: `AlarmEditor.swift` has white icons on orange Save and repeat-day controls; another thread owns its redesign. Calendar's "Dim past days" behavior is a product choice requiring owner input. Workbench scene capture could not run because the current main branch does not compile its `PlanCard` and `AskNativeActions.applyPlan` references. Manual TodayMock navigation provided the visual evidence here.

Verification: `./dev build Debug --scheme TodayMock` with the test dataset; `./dev format`; CI `checks` and `today-required` are the merge gate. Those CI jobs do not run the UI journeys.
