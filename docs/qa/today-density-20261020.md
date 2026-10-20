# Today density — 2026-10-20

Today uses less vertical space without reducing the schedule's text size or changing its contents. Free time is a noninteractive caption, All day is an inline header with its VoiceOver header trait, and Today item insets are tighter. Calendar source text, durations, repeat markers, list names and independent deadlines remain. Repeated calendar/lock glyphs are omitted only in Today. Reminder completion has a 44 × 44 pt target; removing the surrounding horizontal gaps keeps the title's x position at 122 pt.

The Free setting, gap calculation, planner, source payloads, Focus actions, top/bottom navigation and trailing section order are unchanged. Calendar's minimum row/section spacing and ordinary shared-row presentation retain their previous values. No cards, density preference or shared styling framework were added.

## Controlled native comparison

Baseline production source: `02802a4473c99d39dde6d2118ba7c751c233fc14`. Candidate: that source plus this presentation diff. The delegated checkout started at `a56646b2` and was cleanly fast-forwarded before work; no root dirty patch was copied. Delivery-time main was `2aabb25a`; its policy files matched the baseline. Navigation/Search changes remain owned by their existing owners.

Both normal captures use TodayMock (verified `TODAY_MOCK`, executable/module and installed-app identity), the versioned `tests/fixtures/today-density.json`, app/status-bar time 10:30, `en_GB`, Light appearance, `UICTContentSizeCategoryL`, the same deterministic Health summary and disabled auto-scroll. The same iPhone 18 Pro Max / iOS 27.0 simulator produced 1320 × 2868 PNGs (440 × 956 pt, 3×). Title/detail styles remain the existing body/caption styles. Counts use complete fixture-item cells in the unobscured y=122…854 pt region; captions, Health and disclosures are not items.

| Native measurement | Before | After |
| --- | ---: | ---: |
| Complete schedule items, of 11 | 10 | 11 |
| Each Free caption cell | 24 pt | 14.33 pt |
| Four Free captions combined | 96 pt | 57.33 pt |
| Short interactive item cell | 46 pt | 44 pt |
| All day caption | 26 pt | 19.67 pt |
| Long reminder cell | 59.67 pt | 57.67 pt |
| Last item bottom y | 873.67 pt | 786.67 pt |

The last item moves up 87 pt and becomes completely visible. The four gap labels, including their start times, are identical before/after. Normal long Chinese and English titles remain readable on up to two lines. This is an eleven-item fixture comparison, not a claim that an arbitrary 200-item day fits on screen.

Dark / `UICTContentSizeCategoryAccessibilityL` was also captured and visually reviewed. The full long Chinese title remains reachable, grows to 159.67 pt high in a 192 pt row, retains `Due 16:45 · Work`, and opens its editor. Free captions grow naturally to 31.33 pt at this size. No fixed-height clipping or new color/motion treatment was introduced.

## Verification and preserved failures

- `./dev format --check` and `./dev lint`: passed on the final files.
- `./dev test ui --only TodayUITests/TodayDensityTests/testBilingualScheduleGeometryAndReminderEditor`: baseline 1/1 passed; final candidate 1/1 passed. Candidate assertions cover caption height, completion target size, deadline text, editor/Cancel, Settle/Snooze/Delete swipe controls, actual completion and no accidental editor opening.
- `./dev test ui --only TodayUITests/TodayDensityTests/testBilingualScheduleGeometryAndReminderEditor --only TodayUITests/TodayDensityTests/testAccessibilityTextGrowsAndKeepsLongTitle`: dark/large leaf passed; normal leaf failed at a new test-only swipe-dismiss step. Its passing large leaf was reused, not rerun.
- First build failed before boot because the new measurement harness used unavailable `NSStringFromCGRect`; numeric frame JSON fixed it. The normal candidate later failed because swiping right on a title shifted by trailing actions opened the global sidebar (raw hierarchy moved the whole page to x≈343). Tapping the noninteractive date header dismisses native swipe controls; the original disappearance/completion assertions remain. Only that normal method was rerun.
- About 10.5 minutes of native commands across these attempts, including the two focused harness repairs. No coverage expansion or full suite. One focused review found the missing inline-header trait; it was corrected. No separate local logic run was needed for this presentation-only change.

## Retained evidence

Primary directory: `/Users/yuanlu/code/one-app/tests/results/today-density-20261020/`, indexed through `tests/qa/journal.py` under session `today-density-20261020`.

- `before-normal.png`, `after-normal.png`, `after-dark-large-top.png`, `after-dark-large-title.png`: exact exported native PNG bytes, not generated mockups. `metrics.json` records their SHA-256 hashes and per-cell geometry; `final-provenance.json` records source hashes, unchanged gap labels, app identity and complete run summaries.
- `before/`, `after-first/`, `after-final/`: original attachment manifests, PNGs, geometry and accessibility hierarchies. Failed-run attachments/video are retained as well.
- Complete raw logs and closed `ui.xcresult` bundles remain in primary `tests/results/runs/`: `today-qa-20261020-110050-55eeaef5` (build failure), `today-qa-20261020-110238-c9457191` (baseline), `today-qa-20261020-110710-46858df6` (large pass / normal gesture failure), `today-qa-20261020-111100-59bb9f30` (final normal pass).

Owned simulator `D01C64DB-B523-4252-B252-D75FDBEBA08F` / `Today-Dev-b43d3880` and cache `b43d38804ff7875bfe3f` were reused. Final shutdown=0, host/cache locks released and Device panel closed; the phone delivery owner received the actual release. Protected Today-UI `203E49F9-2B3D-4079-A10E-E2C6DA518473` stayed booted and untouched.

No phone installation, signing change, real EventKit write, full accessibility audit, largest-category sweep or Reduce Motion runtime toggle was performed. Source/Focus invariance follows the unchanged action and planner paths; these simulator checks do not establish physical-device acceptance.
