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

## Sequential handoff merges

Each accepted branch is merged in issue #32 order. Narrow tests use default simulator signing, named isolated simulators and derived data, serial XCTest execution, and shutdown after completion. After the one-runner baseline, parallel simulator startup caused excessive host load, so subsequent UI validation uses one simulator at a time. Swarm agents prepare source, logic tests and build-only checks; adoption remains sequential.

| Branch | Merge/adoption | Logic | Simulator build | Targeted UI |
| --- | --- | --- | --- | --- |
| health-add-metric-fix | ab96c8e | 458 executed, 1 skipped, 0 failures | Passed | 17 executed, 15 passed, 2 optional screenshot skips |
| settings-and-calendar-prefs | ccb00c9; extra defaults tests 3bc6d41 | 475 executed, 1 skipped, 0 failures | Passed | Initial 34/35 passed; one Suggestions-switch activation transient passed alone unchanged. Both new saved reminder-list and alarm-sound defaults tests passed. |
| year-view-variant-b | 16459da; locator repair 5c68c8d | 493 executed, 1 skipped, 0 failures | Passed | Initial 9/10 passed; remaining test failed alone on an offscreen Year legend. Visible-key locator repair passed alone with all assertions retained. |

Logs/results: `/tmp/today-codex-merge-health-*`, `/tmp/today-codex-merge-settings-*`, `/tmp/today-codex-settings-rerun.*`, `/tmp/today-codex-year-*`. No combined rerun is claimed where a single failure was rerun alone.

The original Year merge retains the original branch's incomplete behavior. Separate reviewed Year/Week/Health completion patches await the seven original branch gates.

### Reminders (fourth branch)

- Original merge `95e1591`; pill helper repair `fba5adf`; corrected accessibility/viewport helper `b7d1d4e`. Product code unchanged by the helper repairs.
- Logic: 500 executed, 1 skipped, 0 failures; simulator build passed. Initial 21-method selection: 9 passed, 12 failed. Every failed method was retried alone unchanged before attribution. The helper incorrectly assumed pill elements were Buttons and checked hittability before finite on-screen geometry; Settings helpers also accepted clipped rows.
- Corrected selection: 16 executed, 14 passed, 2 failed. Both remaining methods passed alone unchanged: Hide/Restore 192.846 seconds, MovePinned menu 417.945 seconds. All 21 original selected methods now have passing evidence across initial, corrected, and isolated runs; this is not a claim of a combined green rerun.
- Logs/results: `/tmp/today-codex-merge-reminders-*`, `/tmp/today-codex-reminders-alone-*`, `/tmp/today-codex-reminders-long-primary-*`, `/tmp/today-codex-reminders-fixed.*`, `/tmp/today-codex-reminders-fixed-alone-{1,2}.*`. An aborted secondary isolation attempt completed no methods and is not counted as a product failure.
- Sole final runner shut down the primary simulator after the isolated runs. No real-phone verification.

## Remaining

Clock, World Clock and Timer sequential gates; branch completion gaps; Health moving averages; Week alarm lane; PR #29; final full UI run; real-device checks listed in issue #32. Reference screenshots requested from the owner; not received yet.
