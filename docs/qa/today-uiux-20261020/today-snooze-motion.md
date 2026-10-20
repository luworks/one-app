# Today Snooze clock and reduced motion — 2026-10-20

Baseline: `bdfda813319eff2d092e0cc1d13f4a2be0dc7bcf`, matching freshly fetched origin/main and including alignment PR139. Isolated worktree: `t3-1f842eca`, branch `t3/today-uiux-improvements`.

## Ownership

Original five-item implementation brief was narrowed by subsequent direct ownership coordination. AskView input/reading/Ask motion belongs to the existing Ask owner; UndoToast/Shell/Focus message copy belongs to the existing Undo owner. This PR changes only Today motion and Snooze. An uncompiled Ask draft was preserved as evidence and all overlapping edits were reverted before verification. The primary checkout's source was not edited.

## Behavior

- DayAgenda reads accessibilityReduceMotion for disclosure, Focus state and explicit scroll/day transitions. Normal motion remains snappy. Section order, PressScale, fonts and spacing are unchanged.
- Snooze resolves relative choices against the injected app clock at tap, including a change of day while the sheet is open. The initial picker date and lower bound remain snapshots of opening time.
- A custom time that became past is rejected in place with an actionable message; changing the picker clears that message. The sheet closes only after Focus reports success. A rejected save keeps the sheet operable and shows a retry instruction.
- The existing service independently rejects non-finite or non-future Snooze dates against its injected clock. No source date, planned time, alert or completion writes were introduced. Settle remains on and Snooze off by default.

## Focused evidence

Evidence root: `/Users/yuanlu/code/one-app/tests/results/t3-ios-uiux-implementation-20261020/`.

- `./dev bootstrap`: completed with isolated pinned tools.
- `./dev generate`, `./dev format --check`, `./dev lint`: passed.
- `./dev test unit --only TodayTests/SnoozeSelectionTests --timeout 180`: 3 executed, 0 failures, 0 missing. Tests cover a delayed relative hour, midnight/DST tomorrow morning, and stale custom rejection/correction/non-finite input. Raw log/report: primary `tests/results/devtools/logs/b47964f7e79c4007a62137be44121f6d.{log,report.json}`.
- One independent focused source review: no confirmed defects. The custom UI test was renamed to match its actual assertions. Review is not native runtime proof.
- `./dev resolve --scheme TodayMock`: passed. The native source revision was clean `81a7437efe22c1a0a68e22a5638e14dce43edb31`; the final follow-up commit changes evidence documentation only.
- One `./dev test ui` batch with three explicit selectors: **3 executed, 3 passed, 0 missing, 0 skipped**. Native build passed in 82 seconds; the whole batch took 344 seconds including cold simulator preparation. Methods: `TodayFocusTests/testCustomSnoozeCancelKeepsActiveAndExplicitTapCommits`, `TodayFocusTests/testSnoozeKeepsDeadlineAndSourceAndUndoRestoresActiveRow`, `TodayTomorrowTests/testMorningSectionsStartCollapsedAndExpandAllOfTomorrow`.
- Native evidence: primary `tests/results/runs/today-qa-20261020-144345-aa37e260/`, including `build.log`, `ui.log`, `summary.json`, screenshots in the complete `ui.xcresult`, and `mock-product.json`. Reconciliation uses xcresult results, with no journal errors.
- Toolchain: Xcode 27.1 / 27A9275, simulator SDK 27.1; TodayMock on owned iOS 27.0 `Today-Dev-c65edee1` (`167B11A1-BD52-4066-BDAE-869412500DD0`). The runner shut it down successfully. UI/host resources were directly released back to the Ask owner; no further native run planned.

Important unchecked behavior: stale-custom sheet retention and service-failure retry with a clock advanced while open, Reduce Motion visual behavior on/off, and physical-device interaction. Pure clock tests do not establish those runtime results. No phone install, full suite, workflow dispatch, merge or signing change.
