# Codex handoff validation

## Baseline (2026-10-17)

- Read issue #32, `CLAUDE.md`, and `ios/README.md` before changes.
- Main checkout: `/Users/yuanlu/code/one-app`. Preserved seven pre-existing modified files in stash `pre-codex-main-baseline-2026-10-17`, then fast-forwarded main to `ab682ee`. The stash is not applied to the test baseline.
- Device: only `Today-Codex`, iPhone 18 Pro Max, iOS 27.0, `E0F10CAC-EA88-4F7F-83FC-A041EF7AA1F0`; Xcode 27.1 (27A9275). Derived data: `ios/.build/Today-Codex`. Serial testing, no other xcodebuild runner.
- `swift test` from `ios/`: 445 tests executed, 1 skipped, 0 failures. Capture: train 46/46, test 22/22. Log: `/tmp/today-codex-baseline-swift.log`.
- One full UI baseline at `ab682ee`: 196 tests executed, 181 passed, 9 skipped, 6 failed methods (7 assertion failures), 7435.989 seconds. Log: `/tmp/today-codex-baseline-ui.log`; result: `/tmp/today-codex-baseline.xcresult`. This first run incorrectly disabled simulator code signing with `CODE_SIGNING_ALLOWED=NO`, so App Group-dependent failures were not trusted as product regressions.
- Each failing method was rerun alone, with a separate xcodebuild invocation and simulator shutdown afterwards. Logs/results: `/tmp/today-codex-rerun-{1...6}.{log,xcresult}`.
  - `CRUDTests/testAlarmCreateEditToggleDelete`: passed alone in 57.652 seconds. Full run had repeated 60-second animation-idle waits and missed the Undo toast; no product change based on this transient result.
  - `HealthMetricsTests/testSettingsOpensTheSameSheet` and `HealthReviewTests/testSettingTurnsTheLineOff`: failed alone before scrolling to lazy Form controls. Fixed the test helper to reveal the row before asserting it exists.
  - `JourneyTests/testSettingsExplainsEachOptionUnderItsRow`: failed alone using old `Shows today` copy. Updated to the actual Health description and the shared row-reveal helper; retained privacy and relative-position assertions.
  - `ShareImportTests/testSharedReminderArrivesOnce` and `ShareSheetTests/testShareAPageFromSafariAddsAReminder`: failed alone in the unsigned build, then passed without product changes using the default simulator signing/build configuration, which processes simulated App Group entitlements. No project signing settings or certificates changed.
- Corrected targeted run: all five settings/Share tests passed, 0 failures, 161.227 seconds (`/tmp/today-codex-baseline-fixes.log`, `/tmp/today-codex-baseline-fixes.xcresult`). No claim of a second full green suite.
- Xcode prints `invalidDigitCount(94232)` but executes tests. Failure diagnostics can wait for `simctl diagnose --timeout=600`; stopped only the completed run's extra diagnostic collector when stuck. Later targeted runs use `-collect-test-diagnostics never`, retaining XCTest logs, screenshots, and results.
- Simulator confirmed Shutdown after runs. No real-iPhone verification in this baseline.

## Remaining

Seven branch merges and their validation; branch completion gaps; Health moving averages; Week alarm lane; PR #29; final full UI run; real-device checks listed in issue #32. Reference screenshots requested from the owner; not received yet.
