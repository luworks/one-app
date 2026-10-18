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

### Clock (fifth branch)

- Original Clock WIP branch compiled before acceptance. Prepared merge `854489b`, navigation-only test repair `5d55898`; adopted after Reminders as `85e849a` with the corrected Reminders helpers preserved exactly.
- Prepared source: 515 logic tests, 1 skipped, 0 failures; simulator build passed. UI: 29 unique methods, 27 non-optional methods have passing evidence, 2 optional screenshot skips. One initial Stopwatch swipe failure passed alone unchanged; 30 total attempts, 27 passed, 2 skipped, 1 initial failure.
- Actual integrated main: 515 logic tests, 1 skipped, 0 failures; simulator build passed; Stopwatch Start/Lap/Stop/Reset and TabMemory both passed (2/2). Primary shut down afterwards.
- Evidence: `/tmp/today-codex-clock-sequential-report.md`, `/tmp/today-codex-clock-sequential-*`, `/tmp/today-codex-main-clock-{swift,build,smoke}.log`, `/tmp/today-codex-main-clock-smoke.xcresult`. No physical ringing or reference pixel comparison claimed.

### World Clock (sixth branch)

- Prepared merge `81cbf7f`; actual main adoption `e1c104c`, retaining earlier main validation and helper fixes. Package source union retained.
- Actual main logic: 537 executed, 1 skipped, 0 failures; default-signing simulator build passed.
- Prior high-load keyboard-focus failure rerun alone unchanged: Add/Delete City passed. Remaining 9 methods: 8 passed, 1 optional screenshot skip, 0 failures (403.034 seconds). Thus 10 unique methods, 9 passed, 1 skipped. City English/Chinese search, delete/Undo, long-press sorting, scrub, overlap graph, Stopwatch and section retention covered.
- Evidence: `/tmp/today-codex-main-world-{swift,build,add-alone,remaining}.log`, corresponding two xcresults, progress JSON. Primary shut down. Original interrupted secondary run remains partial evidence only; no fix was made for its non-reproduced keyboard failure.
- Original owner screenshots still missing; no Apple/Overlap pixel or real-phone comparison claimed.

### Timer (seventh branch, focused acceptance)

- Prepared source `d1e4d5a`; actual original Timer adoption `7e3b714`. Logic: 543 executed, 1 skipped, 0 failures; default-signing simulator build passed.
- Initial 23 selected UI methods: 12 passed, 11 failed, 743.274 seconds. Owner then narrowed verification scope (below); no claim that all 23 passed.
- Runtime evidence identified absent Recent Button metadata, a stale visual-versus-spoken caption lookup, first-second countdown expectations, picker component/container comparisons, and the helper selecting a hidden sidebar CollectionView. Focused fixes `09e82ba`, `aca75a0`, `4e2f7ca` preserve Recent count/order/controls and explicit timer actions.
- Five representative methods: Focus caption and stacked-card geometry passed; after targeting `timer.list`, own Recents and immediate play/reorder/countdown also passed. The remaining footer failure video shows all copy visibly above the composer; static text was incorrectly required to be hittable. The helper now requires full visibility for text and hittability for controls; footer assertion is included in the next integrated batch.
- Evidence: `/tmp/today-codex-main-timer-{swift,build,ui,core,list-fixed}.log`, matching xcresults; runtime JSONs and `/tmp/today-codex-timer-footer-failure.png`. Primary shut down after each batch. Physical ringing/Live Activity/Siri sharing remain unverified.

## Revised verification scope (owner direction, 2026-10-18)

The owner reported that development was too slow and explicitly requested proportionate checks rather than exhaustive verification. Root `AGENTS.md` records the standing policy (`913033d`). Earlier per-failure-isolation/full-suite plans are narrowed accordingly: reproduce one representative failure per common cause, repair together, run a small set of core journeys, and stop after meaningful checks pass. No additional full UI run is scheduled without a renewed requirement. Unchecked behavior remains explicitly unverified, rather than a delivery gate.

For Timer, the first 23-method selection completed with 12 passed / 11 failed (743.274 seconds). Focus caption failed alone unchanged; the remaining equivalent rerun queue was stopped under the revised scope. Direct runtime inspection found missing `timer.recent` metadata and footer clipping; fixes target those causes and stale timing/container assertions. Five representative checks replace exhaustive repetition.

## Owner phone checkpoint (2026-10-18)

At owner request, built current source `07e800d` with the exact issue #32 phone command, using `ios/.build/xcode-device` and `-allowProvisioningUpdates`. Build succeeded. Installed `com.luworks.one` over Wi-Fi on Yuan Pro Max (`00008140-0014301A363B001C`); devicectl reported `App installed`. Launch result is recorded in `/tmp/today-codex-phone-current-launch.log`. This checkpoint includes seven handoff branches, Timer repairs and Year/Week/Health completion; PR #29 integration follows later. Installation/launch does not establish HealthKit, ringing, widgets or other phone-only functional checks.

Logs: `/tmp/today-codex-phone-current-{build,install,launch}.log`. No signing configuration changes, destructive migrations or test-dataset arguments were used for the phone.

## Final integrated result (2026-10-18)

- All seven specified original branch tips and original PR #29 head `4af2247` are ancestors of main. Reviewed gap integration: `07e800d`; PR integration: `1ea3f5e`; final focused test repairs: `ec849f2`, `72859dc`. Existing Habit and LedgerEntry schemas were retained; no destructive migration or signing configuration changes.
- Actual integrated logic at `1ea3f5e`: **590 executed, 1 skipped, 0 failures**, capture train 46/46 and test 22/22. `/tmp/today-codex-main-pr29-swift.log`. Later changes are UI-test selectors/assertions only.
- Default-signing simulator build and UI execution succeeded. **15 unique representative UI methods have passing evidence across batches**, not a full-suite-green claim: Timer 5, Year/Week/Health 5, PR #29 core 5.
- Year date-to-Today, trip bands/Year-only birthday filtering, Health Weight moving-average versus Steps, and Week task dragging passed in `/tmp/today-codex-main-gaps-core.log` (initial selection 6 executed, 4 passed, 2 failed).
- Final PR/core selection: 7 executed, 5 passed, 2 failed. Chinese existing-action questions, explicit time follow-up requiring Apply, canonical live agenda, plan preview/questions/Apply, and Timer footer passed (`/tmp/today-codex-main-pr29-core.log`).
- Remaining failures were stale test contracts: old combined Added text, and selecting the previous offscreen Week page (`x=-440`). Fixed status checks to persistent Added/Undo/Open and selected the visible Week grid. Restored all original dense-block hittability assertions; none of the geometry or editor checks were dropped. Final **2/2 passed**: chat/request/preview/Add 48.079s and eight-event/alarm disjoint frames plus correct editor tap 26.739s (`/tmp/today-codex-main-final-targeted-fixed.log` and xcresult).
- An intermediate test-only compile attempt failed because an XCUIElement was used as a query; fixed by matching all grid elements. That attempt executed no methods and is not counted as a product failure.
- Timer final footer frame included its accessible row insets; 64pt scroll-content margin accounts for composer overlap and row padding. Footer passed with full bounds above composer. Interactive controls still require hittability; static copy requires full visibility and its exact text.
- Primary simulator shut down after final tests; all three named simulators are Shutdown. The pre-existing stash and all branches/worktrees remain preserved.

## Unverified or deferred

- No second full UI suite under the owner's revised proportionate-testing instruction. Unselected UI methods were not revalidated after every common helper repair.
- Original Apple/Overlap screenshots were requested but not received. Exact World Clock/Stopwatch/Timer reference comparison and comprehensive light/dark visual checks remain deferred; actual Timer light appearance was inspected.
- Phone checkpoint proved build/install/launch only. Not functionally verified on the phone: first HealthKit authorization and real metric units/data; Lock Screen widget layout/countdown; actual AlarmKit ringing, Live Activities and Siri timer routing; Activity 100k-row performance; system appearance switching; native Apple event editor; recurring Apple Reminders; real system Holiday calendars; Apple Intelligence generation and cancellation behavior.
- Existing stale plannedStart data still requires the owner's explicit Unschedule action; no automatic event/task migration was introduced. iCloud/CloudKit remains later work under the existing developer-account constraints.
- The installed phone checkpoint is `07e800d`; later PR routing and final UI-only fixes are on main and were not silently reinstalled while the owner was using the phone.
