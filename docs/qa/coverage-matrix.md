# Today iOS QA coverage and repeatable runner

Source inventory baseline: `55e73d571f57987e5adc57d5d6b710bcec7a998a` (2026-10-18).
Read [issue #32](https://github.com/luworks/today/issues/32), [AGENTS.md](../../AGENTS.md),
[CLAUDE.md](../../CLAUDE.md) and [iOS README](../../ios/README.md) before interpreting results.
This is a coverage map, **not a green-suite report**. The overnight coordinator owns the only full UI run;
adding this runner does not require restarting or replacing that run.

The baseline inventory below remains frozen for comparison. The completed overnight work added five UI methods:
new-request interruption, three persisted Share journeys, and the minimal late-alarm regression.
The [current method proof](../../tests/qa/evidence/ui-method-coverage-20261018.json) covers all 270 current UI methods;
[the final report](overnight-2026-10-18.md) distinguishes baseline results from targeted repair evidence.
`--inventory` always reads the current source, including all 617 logic methods.

## Repeatable entry point

`python3 ios/Eval/run-e2e.py --help` describes the new standalone standard-library entry point.
It follows `run-eval.sh`'s logic → capture eval → simulator test sequence, but requires an explicit UI scope,
retains unfiltered logs and preserves default project signing. The older runner is unchanged.

```bash
# Safe anywhere: no processes, simulator probes, files or locks are created.
python3 ios/Eval/run-e2e.py --full --dry-run
python3 ios/Eval/run-e2e.py --inventory > /tmp/today-source-inventory.json

# Typical repair: select 3–5 related methods, reuse your own cache, no full rerun.
python3 ios/Eval/run-e2e.py \
  --only JourneyTests/testJ1_addTimedTaskFromOneLine \
  --only JourneyTests/testJ3_completeAndUndo \
  --only AskMultiTurnTests/testFollowUpChangesTheTimeOnTheSameCard \
  --simulator-name Today-QA-Repair --output tests/results/runs/repair-001

# Only when authorized, alone, once at the final integrated revision.
# --logic is optional: omit if this revision already has passing logic evidence.
python3 ios/Eval/run-e2e.py --full --logic --simulator-name Today-QA \
  --output tests/results/runs/full-001

# Host-only harness checks (no Xcode, Swift, simulator or device commands).
python3 ios/Eval/test_e2e_runner.py
```

The default is a named **Today-QA**, iPhone 18 Pro Max / iOS 27.0 simulator and
`ios/.build/Today-QA`. `--simulator-name Today-<purpose>` changes both the name and default cache.
`--simulator-id <udid>` must match that exact name; `--derived-data <path>` overrides the cache.
A missing named simulator is created and retained. An already active or ambiguous simulator is rejected;
shut down your own idle runner first. Never select another session's simulator or cache.
For the overnight coordinator's existing device, the explicit options are
`--simulator-name Today-Codex --simulator-id E0F10CAC-EA88-4F7F-83FC-A041EF7AA1F0 --derived-data ios/.build/Today-Codex`;
only its owner may use them, after the current full runner finishes. The new entry point is not needed to start that run.

The runner locks the simulator name and absolute derived-data path across checkouts. These locks coordinate
this entry point only: manually launched Xcode runners must still be coordinated by the owner. It uses one
`xcodebuild test -jobs 2` (incremental build plus execution), serial tests, one destination, no automatic retry,
and no signing overrides. In particular, do not disable signing: Share needs simulated App Group entitlements.
It does not change sources, signing, schema, simulator privacy, device locale or host time zone;
it does not erase/delete simulators or derived data. The owned simulator is shut down in `finally`, including
normal failures, Ctrl-C and SIGTERM; SIGKILL/host crashes cannot run cleanup. A shutdown failure is recorded separately.

Evidence directory (must be new; existing data is never overwritten):

| Artifact | Meaning |
|---|---|
| `summary.json` | Source SHA/dirty status, host time zone, scope, exact test commands, elapsed time, stage exit codes, shutdown result, test-case attempts/counts |
| `inventory.json` | Source declarations at run time; not runtime discovery or execution evidence |
| `logic.log` | Optional full `swift test --jobs 2` output, including capture train/test scores |
| `ui.log` | Unfiltered combined Xcode stdout/stderr, retained in original order |
| `progress.jsonl` | Timestamped completed test-case outcomes, appended and flushed live; terminal also shows starts/suites and completion counts |
| `ui.xcresult` | Xcode's authoritative attachments, test outcomes and skip/failure reasons |
| `xcresult-summary.json`, `.log` | Xcode structured result summary and extraction diagnostics; extraction failure does not turn UI success into failure |

Counts are completed XCTest **attempts**, separately for logic/UI. A build failure or interruption can leave
zero/partial attempts; consult stage exit codes and xcresult. Skipped tests are not passes. The process returns
the failed test command's code, `130` for interruption, or `1` for setup errors. It prints no fabricated pass count.
A later narrow success does not rewrite the full-run outcome. Use a new evidence path for each run.

## Journeys, evidence boundaries and gaps

**UI** means app UI automation through visible actions and assertions, often with deterministic debug hooks.
**Integration** means actual OS stores/extensions participate; debug hooks may still supply operations.
**Pure** means macOS Swift package logic/storage execution, not iPhone E2E.
**Phone** and **simulator unavailable** gates remain distinct even after a full simulator pass.

| User journey / contract | Existing UI or integration coverage | Pure coverage | Boundary / outstanding acceptance |
|---|---|---|---|
| Capture a reminder/event, inspect preview, Add, Undo, Open | `JourneyTests`, `AskMultiCaptureTests`, `AskCardStaysTests`, `AskMultiTurnTests`, `CRUDTests` | `CaptureEvalTests`, `AskCardTests`, `CaptureCardStateTests`, `CaptureLeadInTests`, `AlarmCaptureTests` | Rule fallback/fixture UI; Apple Intelligence generation, timeout/cancellation on supported phone still require device evidence |
| Chat without creating obligations; preserve pending edits across conversation | `AskConversationTests`, `AskMultiTurnTests`, `MessageCopyTests`, `SidebarTests` | `ChatRoutingTests`, `DialogueTests`, `EditRoutingTests`, `ConversationHistoryTests`, `MessageCopyLogicTests` | Simulator cannot prove real on-device model routing; ambiguous input must not become an obligation |
| Plan flexible tasks; explicit event edits; due deadlines stay fixed | `JourneyTests/testPlanMyDay`, `AskEditTests`, `TidyOverdueTests`, `HealthReviewTests`, `LedgerTests` | `DayPlannerTests`, `ReminderPlanTests`, `EveningReviewTests`, `OverdueTidyTests`, `AutonomyPolicyTests`, `EventMatchTests` | Plan journey skips after 18:00; own-data grants do not authorize EventKit writes/events/deadlines/deletes; phone invite updates need explicit Apply verification |
| Today timeline, overdue, suggested/free slots, Tomorrow and timers | `TodayTimelineTests`, `TodayTomorrowTests`, `TodayTimerTests`, `CalendarAlarmTests` | `DayScheduleTests`, `CalendarAlarmsTests`, `TimerListTests`, `RowSubtitleTests` | Dataset dates are relative; fake timer backend proves UI state, not ringing |
| Calendar Week/Month/Year, busy/holiday/trip marks, task drag and alarm lane | `CalendarTabTests`, `CalendarAlarmTests`, `JourneyTests/testDragTaskInWeekGrid`, `SettingsChoicesTests` | `CalendarMathTests`, `CalendarLayoutTests`, `YearMarksTests`, `CalendarAlarmsTests` | Real system Holidays and owner Apple/reference screenshot parity remain separate; injected fixtures do not prove a real subscribed calendar |
| Apple Calendar create/view/edit/delete and recurring occurrence scope | `CalendarSyncTests`, `CalendarDeleteSyncTests`, `CalendarRecurringDeleteTests`, `SystemEventEditorTests` (real simulator EventKit + Apple editor) | `RecurrenceTests`, `RepeatRuleTests`, `EventMatchTests` | Permission/native editor integration; current-hour fixtures skip some methods after 23:00; real account/invite side effects require phone acceptance |
| Reminder/list CRUD, flag, completion, repeat, pin/reorder and quick add | `CRUDTests`, `InlineNewReminderTests`, `RemindersListsTests`, `RepeatingReminderTests`, `EntryActionsTests` | `NewReminderDraftTests`, `RepeatAdvanceTests`, `PillOrderTests`, `ReminderSuggestTests`, `ListGuessTests` | Most use in-memory dataset. Shake skips when XCTest cannot synthesize it; drag behavior is tested through UI, not merely ordering functions |
| Apple Reminders both directions and recurring roll-forward | `RemindersSyncTests`, `RemindersSyncBothWaysTests` (real simulator EventKit, debug operations/readback) | `RepeatAdvanceTests`, `RecurrenceTests` | Integration through hooks, not a user driving Apple's Reminders app. Real account/repeating behavior remains a phone acceptance item |
| Alarms CRUD, snooze/sound defaults, calendar markers | `AlarmsTabTests`, `AlarmDefaultTimeTests`, `CRUDTests`, `SettingsChoicesTests`, `CalendarAlarmTests` | `AlarmPlanTests`, `AlarmCaptureTests`, `PreferencesTests` | `AlarmTests/testRingAsAlarmFires` skips on simulator. Real ringing, stop ≠ task completion, Focus/Silent and linked alarm behavior need phone evidence |
| Timer wheel/recents/multiple timers/Today rows; stopwatch; world city search/scrub/overlap | `TimerTests`, `TodayTimerTests`, `StopwatchTests`, `ClockTests`, `TabMemoryTests` | `TimerDialTests`, `TimerRecentsTests`, `TimerPhraseTests`, `TimerListTests`, `PomodoroTests`, `StopwatchLogicTests`, `CityDatabaseTests`, `WorldClockLookTests`, `WorldClockTests`, `OverlapTests` | Timer hooks swap AlarmKit for fake; real countdown/ringing/Live Activity/Siri are phone-only acceptance. Stopwatch/Overlap/Timer screenshot parity still needs owner references |
| Settings, adaptive appearance and retained tab/view choices | `SettingsChoicesTests`, `AppearanceUITests`, `TabMemoryTests`, `SinglePresentationTests` | `PreferencesTests`, `AppearanceTests`, `TabMemoryLogicTests` | Some dimming checks require yesterday/tomorrow in same month. Screenshot captures are optional; System appearance change and native editor override need phone review |
| Health summary, add/hide/reorder metrics, chart averages, stalled reads/auth | `HealthMetricsTests`, `HealthReviewTests`, `HealthStallTests` | `HealthMetricsTests`, `MovingAverageTests`, `HealthLogicTests`, `HealthLoadingTests` | Seeded simulator values/stalls; real first-time HealthKit authorization, health data/units and query performance remain phone-only |
| Activity audit/Undo, grants, pause/clear/export, paging and legacy migration | `ActivityDataTests`, `LedgerTests` | `ActivityStoreTests`, `ActivityRecorderTests`, `ActivityLedgerTests`, `LedgerFormatTests`, `AutonomyPolicyTests` | Includes app-side migration across launches; keep `Habit` and `LedgerEntry` schema. Simulator/host timings do not prove phone 100k performance |
| Share a Safari page, preview Add, import into Today | `ShareSheetTests` (genuine Safari → extension → App Group → app chain); `ShareImportTests` (injected app-side inbox) | `ShareInboxTests`, `ActivityRecorderTests` | Safari/address/network skip can hide unexecuted chain. Real cross-app chain needs default signing; app-only hook cannot substitute for it |
| Widgets, deep links, Siri/Spotlight/Shortcuts and background refresh | No dedicated system-surface UI suite; `IntentTests`/widget suites are pure only | `WidgetSnapshotTests`, `LockScreenNextTests`, `TravelTimeTests`, `IntentTests`, `ShareInboxTests` | Widget placement/countdown, timeline refresh, background scheduling, real intents, Siri routing and Live Activity need phone/system evidence |
| Launch speed | `LaunchTests/testColdStartUnderBudget` (three app launches, 4000 ms UI automation budget) | — | `Eval/cold-start.sh` measures first-frame <1000 ms separately and picks a booted simulator; never invoke while another owner has a simulator. Not automatically called by the new runner |

## Fixtures, date dependence and optional gates

`TestData.launchArguments` loads `tests/fixtures/today-dataset.json` into a fresh in-memory store with sync off.
Dates are relative to the loading day, not globally frozen. `-uiTestingNow HH:mm` stabilizes selected display time,
not the host date, time zone, EventKit, every `Date.now`, or every test's calendar. Tests also use fresh named file
stores for relaunch/migration, hook-generated events/reminders, seeded health readings and fake timer states.
Preserve the run date/time zone in the evidence and inspect a midnight/month-end failure before attributing it.
Do not change assertions or product scheduling just to hide such a failure.

Capture eval loads a fixed `now` and time zone from `capture-cases.json` (46 train + 22 test cases at this baseline);
these are 68 case assertions inside one XCTest method, not 68 E2E journeys. Other pure suites inject dates/calendars
where required (including moving-average DST cases); source inventory is not a blanket determinism guarantee.

| Gate | Existing source behavior | How to interpret / opt in |
|---|---|---|
| Alarm hardware | `AlarmTests` requires iOS 26+ and explicitly skips simulator | Run on a physical phone separately; this runner accepts simulator only |
| Network / Safari | `ShareSheetTests` skips missing Safari address field or unloaded page | Read xcresult skip reason; no network skip is evidence of Share success |
| Current-hour limits | Calendar sync/delete/editor methods and `CalendarTabTests` skip at 23:00; J6 skips 23:45+ | Rerun the affected method at a valid time, not the whole suite |
| Planner evening | `JourneyTests/testPlanMyDay` skips at 18:00+ | Evening run cannot prove this daytime path |
| Month boundaries | `CalendarTabTests` sample dates, two `SettingsChoicesTests` dimming checks | Month-end skip is a coverage gap to record |
| Permission row / shake | `AlarmsTabTests/testPermissionIsOneSlimRow`, `EntryActionsTests/testShakeOffersUndoAfterDelete` | Conditions depend on simulator permission/XCTest capability; record skip |
| Health screenshots | `HealthMetricsTests`, `HealthReviewTests`: `HEALTH_SHOTS=1`, optional `HEALTH_SHOTS_MODE`, `HEALTH_SHOTS_DIR` (metrics) | Use `TEST_RUNNER_HEALTH_SHOTS=1` etc. in the xcodebuild environment; capture is not a reference comparison |
| Appearance screenshots | Two `AppearanceUITests` methods require `APPEARANCE_SHOTS=<directory>` | `TEST_RUNNER_APPEARANCE_SHOTS=/tmp/...`; test creates its output directory |
| Clock/Stopwatch/Ledger screenshots | Dedicated `testScreenshots` methods require `CLOCK_SHOTS`, `STOPWATCH_SHOTS`, `LEDGER_SHOTS` directories; optional `*_SHOTS_SUFFIX` | `TEST_RUNNER_<KEY>=...` forwards to test runner; opt in separately from routine repair coverage |
| Additional attachments | `ALARM_SHOTS`, `EVENT_SHOTS`, `PRESENT_SHOTS`, `TEST_RUNNER_CARD_SHOTS` | Some helpers simply return without a directory, rather than skip the method. Inspect the exact source variable name (card test already reads `TEST_RUNNER_CARD_SHOTS`) |
| Activity benchmark | `ActivityStoreTests/testBenchmarkLarge` skips without `ACTIVITY_BENCH_ROWS` | `ACTIVITY_BENCH_ROWS=100000 swift test --jobs 2 --filter testBenchmarkLarge` from `ios/`; separate opt-in timing run, not a phone benchmark |
| Real Activity phone speed | Settings → Activity data → Debug Run speed test (100,000 rows) | Requires phone; no accepted phone figure yet |

The runner inherits environment variables and records screenshot/benchmark settings in `summary.json`. It does not
create screenshot directories or enable optional tests automatically. Keep skipped/phone-only gates visible in reports.
For physical acceptance also check owner reference images, actual HealthKit permissions/data, widget layout/countdown,
AlarmKit/Siri/Live Activities, native system editor appearance and recurring Apple Reminders. These are the remaining
acceptance categories in issue #32, not newly reproduced bugs.

## Complete source inventory

Generated from XCTest class and `func test...` declarations at the baseline: **45 UI suites / 265 UI methods**;
**63 pure suites / 590 pure methods**. Swift conditional compilation/runtime skips can reduce execution. Refresh with
`--inventory`; its JSON lists every method and source line in both lanes. Classes sharing a file are listed separately.
The lists below are declaration inventory only; consult a run's xcresult for discovery/execution.

### UI suites and methods

<details>
<summary>ActivityDataTests (5 methods)</summary>

Source: [ios/OneUITests/ActivityDataTests.swift](../../ios/OneUITests/ActivityDataTests.swift).

- [`testPageExplainsPausesAndClears`](../../ios/OneUITests/ActivityDataTests.swift#L40)
- [`testActivityPagesWithShowMore`](../../ios/OneUITests/ActivityDataTests.swift#L83)
- [`testPausedRecordingStopsAutomaticChanges`](../../ios/OneUITests/ActivityDataTests.swift#L102)
- [`testOldLedgerRowsAreImportedOnceAndRetiredInALaterLaunch`](../../ios/OneUITests/ActivityDataTests.swift#L114)
- [`testExportOpensTheShareSheet`](../../ios/OneUITests/ActivityDataTests.swift#L162)

</details>

<details>
<summary>AlarmTests (1 methods)</summary>

Source: [ios/OneUITests/AlarmTests.swift](../../ios/OneUITests/AlarmTests.swift).

- [`testRingAsAlarmFires`](../../ios/OneUITests/AlarmTests.swift#L6)

</details>

<details>
<summary>AlarmsTabTests (9 methods)</summary>

Source: [ios/OneUITests/AlarmsTabTests.swift](../../ios/OneUITests/AlarmsTabTests.swift).

- [`testEmptyStateAndAddAlarm`](../../ios/OneUITests/AlarmsTabTests.swift#L47)
- [`testToggleSwitchesAlarmOffAndHidesNextHint`](../../ios/OneUITests/AlarmsTabTests.swift#L58)
- [`testRepeatDaysShowClockWording`](../../ios/OneUITests/AlarmsTabTests.swift#L71)
- [`testEditTimeAndLabel`](../../ios/OneUITests/AlarmsTabTests.swift#L89)
- [`testSwipeLeftDeletes`](../../ios/OneUITests/AlarmsTabTests.swift#L109)
- [`testDeleteAlarmFromEditor`](../../ios/OneUITests/AlarmsTabTests.swift#L123)
- [`testChoosingATone`](../../ios/OneUITests/AlarmsTabTests.swift#L132)
- [`testPermissionIsOneSlimRow`](../../ios/OneUITests/AlarmsTabTests.swift#L158)
- [`testSnoozeOffHidesDuration`](../../ios/OneUITests/AlarmsTabTests.swift#L169)

</details>

<details>
<summary>AlarmDefaultTimeTests (1 methods)</summary>

Source: [ios/OneUITests/AlarmsTabTests.swift](../../ios/OneUITests/AlarmsTabTests.swift).

- [`testAddAlarmOpensOnTheNextQuarterHour`](../../ios/OneUITests/AlarmsTabTests.swift#L180)

</details>

<details>
<summary>AppearanceUITests (4 methods)</summary>

Source: [ios/OneUITests/AppearanceUITests.swift](../../ios/OneUITests/AppearanceUITests.swift).

- [`testDarkAppliesAtOnceAndSticksAfterRelaunch`](../../ios/OneUITests/AppearanceUITests.swift#L51)
- [`testScreenshotsOfEveryScreenInBothModes`](../../ios/OneUITests/AppearanceUITests.swift#L68)
- [`testMoreScreenshotsInBothModes`](../../ios/OneUITests/AppearanceUITests.swift#L101)
- [`testLightAppliesAtOnceAndSticksAfterRelaunch`](../../ios/OneUITests/AppearanceUITests.swift#L130)

</details>

<details>
<summary>AskCardStaysTests (4 methods)</summary>

Source: [ios/OneUITests/AskCardStaysTests.swift](../../ios/OneUITests/AskCardStaysTests.swift).

- [`testAddedCardStaysThenUndoAndAddAgain`](../../ios/OneUITests/AskCardStaysTests.swift#L52)
- [`testAddedStateSurvivesReopening`](../../ios/OneUITests/AskCardStaysTests.swift#L105)
- [`testCancelLeavesADimmedDroppedCard`](../../ios/OneUITests/AskCardStaysTests.swift#L118)
- [`testNewLineAfterAnOpenCardDropsIt`](../../ios/OneUITests/AskCardStaysTests.swift#L132)

</details>

<details>
<summary>AskConversationTests (6 methods)</summary>

Source: [ios/OneUITests/AskConversationTests.swift](../../ios/OneUITests/AskConversationTests.swift).

- [`testReportedActivityMessageIsConversation`](../../ios/OneUITests/AskConversationTests.swift#L25)
- [`testChatThenExplicitRequestAndChatPreservesPreview`](../../ios/OneUITests/AskConversationTests.swift#L41)
- [`testExistingAlarmQuestionPreservesPendingReminder`](../../ios/OneUITests/AskConversationTests.swift#L59)
- [`testExplicitEventAndAlarmRequestsStillShowPreviews`](../../ios/OneUITests/AskConversationTests.swift#L78)
- [`testChineseExistingActionQuestionsInFreshChatDoNotProposeItems`](../../ios/OneUITests/AskConversationTests.swift#L87)
- [`testQuestionAndUnknownStatementDoNotCreateCards`](../../ios/OneUITests/AskConversationTests.swift#L99)

</details>

<details>
<summary>AskEditTests (6 methods)</summary>

Source: [ios/OneUITests/AskEditTests.swift](../../ios/OneUITests/AskEditTests.swift).

- [`testCapture_fiveSentences`](../../ios/OneUITests/AskEditTests.swift#L48)
- [`testEdit_moveEventApplyUndo`](../../ios/OneUITests/AskEditTests.swift#L69)
- [`testEdit_moveTaskKeepsDeadline`](../../ios/OneUITests/AskEditTests.swift#L89)
- [`testEdit_moveEventToTomorrow`](../../ios/OneUITests/AskEditTests.swift#L100)
- [`testEdit_deleteTaskAndUndo`](../../ios/OneUITests/AskEditTests.swift#L109)
- [`testEdit_clarifyAsksInsteadOfCard`](../../ios/OneUITests/AskEditTests.swift#L121)

</details>

<details>
<summary>AskMultiCaptureTests (3 methods)</summary>

Source: [ios/OneUITests/AskMultiCaptureTests.swift](../../ios/OneUITests/AskMultiCaptureTests.swift).

- [`testEveryItemShowsAtOnceAndAddAllFilesThem`](../../ios/OneUITests/AskMultiCaptureTests.swift#L32)
- [`testAddOneAndSkipAnother`](../../ios/OneUITests/AskMultiCaptureTests.swift#L52)
- [`testUndoOneRowAndAddItAgain`](../../ios/OneUITests/AskMultiCaptureTests.swift#L63)

</details>

<details>
<summary>AskMultiTurnTests (13 methods)</summary>

Source: [ios/OneUITests/AskMultiTurnTests.swift](../../ios/OneUITests/AskMultiTurnTests.swift).

- [`testFollowUpChangesTheTimeOnTheSameCard`](../../ios/OneUITests/AskMultiTurnTests.swift#L31)
- [`testFollowUpMakesItAnAlarm`](../../ios/OneUITests/AskMultiTurnTests.swift#L43)
- [`testAskingWhichMeetingOffersRealItemsAndTapWorks`](../../ios/OneUITests/AskMultiTurnTests.swift#L51)
- [`testAskingWhichMeetingAcceptsTypedAnswer`](../../ios/OneUITests/AskMultiTurnTests.swift#L61)
- [`testMissingTimeIsAskedForThenAnswered`](../../ios/OneUITests/AskMultiTurnTests.swift#L69)
- [`testEnglishQuestionTimeAnswerPreservesConversationAndRequiresApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L77)
- [`testChineseQuestionTimeAnswerPreservesConversationAndRequiresApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L81)
- [`testReminderQuestionPreservesTimeFollowupAndChangeUntilApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L85)
- [`testPoliteStoryQuestionPreservesTimeFollowupAndChangeUntilApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L89)
- [`testChineseExistingReminderQuestionPreservesTimeFollowupAndChangeUntilApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L93)
- [`testChineseAddedReminderQuestionPreservesTimeFollowupAndChangeUntilApply`](../../ios/OneUITests/AskMultiTurnTests.swift#L97)
- [`testNewRequestMentioningAnItemsTimeIsACaptureNotAnEdit`](../../ios/OneUITests/AskMultiTurnTests.swift#L125)
- [`testItMeansWhatWeTalkedAboutLast`](../../ios/OneUITests/AskMultiTurnTests.swift#L140)

</details>

<details>
<summary>AskSuggestionTests (7 methods)</summary>

Source: [ios/OneUITests/AskSuggestionTests.swift](../../ios/OneUITests/AskSuggestionTests.swift).

- [`testTwoOrThreeChipsAndTappingOneSendsIt`](../../ios/OneUITests/AskSuggestionTests.swift#L27)
- [`testChipsDifferByTimeOfDay`](../../ios/OneUITests/AskSuggestionTests.swift#L42)
- [`testReviewTodayAnswersWithWhatGotDone`](../../ios/OneUITests/AskSuggestionTests.swift#L53)
- [`testPolitePlanRequestPreservesPreviewThroughOperationQuestionsUntilApply`](../../ios/OneUITests/AskSuggestionTests.swift#L73)
- [`testPoliteTidyRequestRequiresApplyAndAboutQuestionPreservesIt`](../../ios/OneUITests/AskSuggestionTests.swift#L88)
- [`testChineseQuestionReviewUsesExistingReadOnlySummary`](../../ios/OneUITests/AskSuggestionTests.swift#L101)
- [`testCanonicalRemainingTodayQuestionReadsCurrentDataset`](../../ios/OneUITests/AskSuggestionTests.swift#L113)

</details>

<details>
<summary>CRUDTests (14 methods)</summary>

Source: [ios/OneUITests/CRUDTests.swift](../../ios/OneUITests/CRUDTests.swift).

- [`testReminderCreateEditFlagCompleteDeleteUndo`](../../ios/OneUITests/CRUDTests.swift#L111)
- [`testReminderQuickAddWithPlus`](../../ios/OneUITests/CRUDTests.swift#L180)
- [`testReminderSwipeFlagShowsInFlagged`](../../ios/OneUITests/CRUDTests.swift#L208)
- [`testListCreateRenameDelete`](../../ios/OneUITests/CRUDTests.swift#L230)
- [`testListSwipeDeleteKeepsReminders`](../../ios/OneUITests/CRUDTests.swift#L285)
- [`testEventCreateEditDeleteInEditor`](../../ios/OneUITests/CRUDTests.swift#L343)
- [`testEventSwipeAndLongPressDelete`](../../ios/OneUITests/CRUDTests.swift#L403)
- [`testRepeatingEventDeleteAsksFirst`](../../ios/OneUITests/CRUDTests.swift#L428)
- [`testAlarmCreateEditToggleDelete`](../../ios/OneUITests/CRUDTests.swift#L472)
- [`testAlarmTogglesFromDataset`](../../ios/OneUITests/CRUDTests.swift#L527)
- [`testChatCreateAndReopen`](../../ios/OneUITests/CRUDTests.swift#L554)
- [`testChatRenameArchiveDeleteUndo`](../../ios/OneUITests/CRUDTests.swift#L587)
- [`testSearchFindsEveryKind`](../../ios/OneUITests/CRUDTests.swift#L638)
- [`testSearchSeesCreatedAndDeletedItems`](../../ios/OneUITests/CRUDTests.swift#L689)

</details>

<details>
<summary>CalendarAlarmTests (6 methods)</summary>

Source: [ios/OneUITests/CalendarAlarmTests.swift](../../ios/OneUITests/CalendarAlarmTests.swift).

- [`testMonthListsTheAlarmAndOpensItsEditor`](../../ios/OneUITests/CalendarAlarmTests.swift#L40)
- [`testMonthDayCellCountsTheAlarm`](../../ios/OneUITests/CalendarAlarmTests.swift#L53)
- [`testWeekGridShowsTheAlarmMarker`](../../ios/OneUITests/CalendarAlarmTests.swift#L62)
- [`testWeekOverlappingEventAndAlarmHaveDisjointFramesAndOpenAlarmEditor`](../../ios/OneUITests/CalendarAlarmTests.swift#L73)
- [`testWeekDenseOverlapClusterStaysInsideAssignedFramesAndOpensAlarmEditor`](../../ios/OneUITests/CalendarAlarmTests.swift#L77)
- [`testTheSettingHidesAlarmsInTheCalendar`](../../ios/OneUITests/CalendarAlarmTests.swift#L153)

</details>

<details>
<summary>CalendarDeleteSyncTests (2 methods)</summary>

Source: [ios/OneUITests/CalendarDeleteSyncTests.swift](../../ios/OneUITests/CalendarDeleteSyncTests.swift).

- [`testEventDeletedInAppleCalendarDisappearsHere`](../../ios/OneUITests/CalendarDeleteSyncTests.swift#L64)
- [`testEventDeletedHereIsDeletedInAppleCalendar`](../../ios/OneUITests/CalendarDeleteSyncTests.swift#L85)

</details>

<details>
<summary>CalendarRecurringDeleteTests (6 methods)</summary>

Source: [ios/OneUITests/CalendarRecurringDeleteTests.swift](../../ios/OneUITests/CalendarRecurringDeleteTests.swift).

- [`testDeleteThisEventOnlyFromRowKeepsOtherDays`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L139)
- [`testDeleteAllFutureEventsFromTodayKeepsThePast`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L151)
- [`testDeleteThisEventOnlyInAppleEditorClosesItAndKeepsOtherDays`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L160)
- [`testOneOffEventDeletedFromRowWithUndo`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L171)
- [`testOneOffEventDeletedInAppleEditorClosesIt`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L182)
- [`testEventDeletedInAppleCalendarIsGoneFromToday`](../../ios/OneUITests/CalendarRecurringDeleteTests.swift#L192)

</details>

<details>
<summary>CalendarSyncTests (1 methods)</summary>

Source: [ios/OneUITests/CalendarSyncTests.swift](../../ios/OneUITests/CalendarSyncTests.swift).

- [`testEventRoundTripsThroughSystemCalendar`](../../ios/OneUITests/CalendarSyncTests.swift#L5)

</details>

<details>
<summary>CalendarTabTests (11 methods)</summary>

Source: [ios/OneUITests/CalendarTabTests.swift](../../ios/OneUITests/CalendarTabTests.swift).

- [`testWeekIsTheDefault`](../../ios/OneUITests/CalendarTabTests.swift#L33)
- [`testMonthListsTodaysEvents`](../../ios/OneUITests/CalendarTabTests.swift#L46)
- [`testMonthPaging`](../../ios/OneUITests/CalendarTabTests.swift#L60)
- [`testSelectingADayListsItsEvents`](../../ios/OneUITests/CalendarTabTests.swift#L81)
- [`testYearViewOpensAMonth`](../../ios/OneUITests/CalendarTabTests.swift#L95)
- [`testYearMarksHolidaysAndHasAKey`](../../ios/OneUITests/CalendarTabTests.swift#L111)
- [`testYearDayOpensTheChosenDayInToday`](../../ios/OneUITests/CalendarTabTests.swift#L132)
- [`testYearReadsTripDaysButLeavesLocalBirthdayInMonth`](../../ios/OneUITests/CalendarTabTests.swift#L145)
- [`testWeekShowsAllDayBanner`](../../ios/OneUITests/CalendarTabTests.swift#L176)
- [`testCalendarsListLivesInSettings`](../../ios/OneUITests/CalendarTabTests.swift#L189)
- [`testCalendarsFilterHidesEvents`](../../ios/OneUITests/CalendarTabTests.swift#L202)

</details>

<details>
<summary>ClockTests (10 methods)</summary>

Source: [ios/OneUITests/ClockTests.swift](../../ios/OneUITests/ClockTests.swift).

- [`testSwitchingSectionsAndPlus`](../../ios/OneUITests/ClockTests.swift#L41)
- [`testAddAndDeleteCity`](../../ios/OneUITests/ClockTests.swift#L73)
- [`testDeleteFromLongPressMenu`](../../ios/OneUITests/ClockTests.swift#L107)
- [`testScrubbing`](../../ios/OneUITests/ClockTests.swift#L121)
- [`testOverlapGraph`](../../ios/OneUITests/ClockTests.swift#L149)
- [`testSearchBeijingAndChina`](../../ios/OneUITests/ClockTests.swift#L166)
- [`testSearchByChineseName`](../../ios/OneUITests/ClockTests.swift#L186)
- [`testReorderFromLongPressMenu`](../../ios/OneUITests/ClockTests.swift#L196)
- [`testStopwatchStartLapStopReset`](../../ios/OneUITests/ClockTests.swift#L211)
- [`testScreenshots`](../../ios/OneUITests/ClockTests.swift#L251)

</details>

<details>
<summary>DevDataTests (1 methods)</summary>

Source: [ios/OneUITests/DevDataTests.swift](../../ios/OneUITests/DevDataTests.swift).

- [`testDatasetFillsChatsAlarmsAndReminders`](../../ios/OneUITests/DevDataTests.swift#L6)

</details>

<details>
<summary>EntryActionsTests (5 methods)</summary>

Source: [ios/OneUITests/EntryActionsTests.swift](../../ios/OneUITests/EntryActionsTests.swift).

- [`testCompletedTaskLeavesToday`](../../ios/OneUITests/EntryActionsTests.swift#L25)
- [`testLongPressOnAnEventOffersTheUsualActions`](../../ios/OneUITests/EntryActionsTests.swift#L33)
- [`testSwipeLeftDeletesAnEvent`](../../ios/OneUITests/EntryActionsTests.swift#L43)
- [`testSwipingARepeatingEventAsksFirst`](../../ios/OneUITests/EntryActionsTests.swift#L54)
- [`testShakeOffersUndoAfterDelete`](../../ios/OneUITests/EntryActionsTests.swift#L66)

</details>

<details>
<summary>HealthMetricsTests (10 methods)</summary>

Source: [ios/OneUITests/HealthMetricsTests.swift](../../ios/OneUITests/HealthMetricsTests.swift).

- [`testListShowsTheDefaultRowsAndNoCards`](../../ios/OneUITests/HealthMetricsTests.swift#L32)
- [`testTapOpensDetailWithRangeSwitch`](../../ios/OneUITests/HealthMetricsTests.swift#L51)
- [`testMovingAverageAppearsForWeightButNotSteps`](../../ios/OneUITests/HealthMetricsTests.swift#L77)
- [`testAddMetricAddsRowsAndOffersOnlyWhatIsHidden`](../../ios/OneUITests/HealthMetricsTests.swift#L102)
- [`testHideRemovesTheRowAndAddMetricBringsItBack`](../../ios/OneUITests/HealthMetricsTests.swift#L128)
- [`testHidingSleepMakesTheTodayLineUseTheNextMetric`](../../ios/OneUITests/HealthMetricsTests.swift#L145)
- [`testOrderSurvivesARelaunch`](../../ios/OneUITests/HealthMetricsTests.swift#L164)
- [`testStaleReadingShowsItsDateNotToday`](../../ios/OneUITests/HealthMetricsTests.swift#L187)
- [`testSettingsOpensTheSameSheet`](../../ios/OneUITests/HealthMetricsTests.swift#L198)
- [`testScreenshots`](../../ios/OneUITests/HealthMetricsTests.swift#L214)

</details>

<details>
<summary>HealthReviewTests (6 methods)</summary>

Source: [ios/OneUITests/HealthReviewTests.swift](../../ios/OneUITests/HealthReviewTests.swift).

- [`testHealthLineOpensTheHealthSheet`](../../ios/OneUITests/HealthReviewTests.swift#L35)
- [`testHealthLineOnlyOnToday`](../../ios/OneUITests/HealthReviewTests.swift#L49)
- [`testSettingTurnsTheLineOff`](../../ios/OneUITests/HealthReviewTests.swift#L59)
- [`testNoReviewBeforeTheEvening`](../../ios/OneUITests/HealthReviewTests.swift#L98)
- [`testEveningReviewMovesAndDropsWithOneUndo`](../../ios/OneUITests/HealthReviewTests.swift#L104)
- [`testScreenshots`](../../ios/OneUITests/HealthReviewTests.swift#L145)

</details>

<details>
<summary>HealthStallTests (2 methods)</summary>

Source: [ios/OneUITests/HealthStallTests.swift](../../ios/OneUITests/HealthStallTests.swift).

- [`testStalledQueryGivesAFallbackRowAndOthersKeepData`](../../ios/OneUITests/HealthStallTests.swift#L32)
- [`testAccessThatNeverAnswersStillAddsTheRow`](../../ios/OneUITests/HealthStallTests.swift#L50)

</details>

<details>
<summary>InlineNewReminderTests (1 methods)</summary>

Source: [ios/OneUITests/InlineNewReminderTests.swift](../../ios/OneUITests/InlineNewReminderTests.swift).

- [`testNewRowAddsAReminderWithDateAndFlag`](../../ios/OneUITests/InlineNewReminderTests.swift#L27)

</details>

<details>
<summary>JourneyTests (15 methods)</summary>

Source: [ios/OneUITests/JourneyTests.swift](../../ios/OneUITests/JourneyTests.swift).

- [`testJ1_addTimedTaskFromOneLine`](../../ios/OneUITests/JourneyTests.swift#L28)
- [`testJ2_todayShowsWhatsLeft`](../../ios/OneUITests/JourneyTests.swift#L44)
- [`testJ3_completeAndUndo`](../../ios/OneUITests/JourneyTests.swift#L53)
- [`testJ4_addEvent`](../../ios/OneUITests/JourneyTests.swift#L65)
- [`testJ5_addReminderToList`](../../ios/OneUITests/JourneyTests.swift#L85)
- [`testJ6_addAlarmAndSeeItInToday`](../../ios/OneUITests/JourneyTests.swift#L98)
- [`testJ7_search`](../../ios/OneUITests/JourneyTests.swift#L114)
- [`testSearchFindsEventsAndRemindersTogether`](../../ios/OneUITests/JourneyTests.swift#L125)
- [`testSearchSuggestionsAndCancelClosesIt`](../../ios/OneUITests/JourneyTests.swift#L137)
- [`testSidebarOpensWithEdgeSwipe`](../../ios/OneUITests/JourneyTests.swift#L148)
- [`testMenuButtonOpensTheSidebar`](../../ios/OneUITests/JourneyTests.swift#L154)
- [`testPlanMyDay`](../../ios/OneUITests/JourneyTests.swift#L160)
- [`testDragTaskInWeekGrid`](../../ios/OneUITests/JourneyTests.swift#L176)
- [`testSettingsExplainsEachOptionUnderItsRow`](../../ios/OneUITests/JourneyTests.swift#L193)
- [`testSettingsDeleteAllDataNeedsTwoConfirmations`](../../ios/OneUITests/JourneyTests.swift#L211)

</details>

<details>
<summary>LaunchTests (1 methods)</summary>

Source: [ios/OneUITests/LaunchTests.swift](../../ios/OneUITests/LaunchTests.swift).

- [`testColdStartUnderBudget`](../../ios/OneUITests/LaunchTests.swift#L9)

</details>

<details>
<summary>LedgerTests (4 methods)</summary>

Source: [ios/OneUITests/LedgerTests.swift](../../ios/OneUITests/LedgerTests.swift).

- [`testActivityListsAnAIApplyAndAUserDeleteWithUndo`](../../ios/OneUITests/LedgerTests.swift#L49)
- [`testGrantAutoAppliesWithToastAndCanBeRevoked`](../../ios/OneUITests/LedgerTests.swift#L88)
- [`testAlwaysForSevenDaysAppliesAndGrants`](../../ios/OneUITests/LedgerTests.swift#L113)
- [`testScreenshots`](../../ios/OneUITests/LedgerTests.swift#L129)

</details>

<details>
<summary>MessageCopyTests (2 methods)</summary>

Source: [ios/OneUITests/MessageCopyTests.swift](../../ios/OneUITests/MessageCopyTests.swift).

- [`testEachMessageHasACopyButtonThatConfirms`](../../ios/OneUITests/MessageCopyTests.swift#L6)
- [`testStatusSentencesHaveNoCopyButton`](../../ios/OneUITests/MessageCopyTests.swift#L28)

</details>

<details>
<summary>RemindersListsTests (13 methods)</summary>

Source: [ios/OneUITests/RemindersListsTests.swift](../../ios/OneUITests/RemindersListsTests.swift).

- [`testNoEditButtonAndCompactSmartLists`](../../ios/OneUITests/RemindersListsTests.swift#L38)
- [`testSmartListPillsAreOneRowAndTappable`](../../ios/OneUITests/RemindersListsTests.swift#L56)
- [`testAddListIsVisibleAndCreatesAList`](../../ios/OneUITests/RemindersListsTests.swift#L86)
- [`testSwipePinsAListToTheTop`](../../ios/OneUITests/RemindersListsTests.swift#L100)
- [`testLongPressRenamesAList`](../../ios/OneUITests/RemindersListsTests.swift#L111)
- [`testLongPressColorAndIconOpensTheListEditor`](../../ios/OneUITests/RemindersListsTests.swift#L133)
- [`testLongPressPinsAndUnpins`](../../ios/OneUITests/RemindersListsTests.swift#L141)
- [`testLongPressDeleteAsksFirst`](../../ios/OneUITests/RemindersListsTests.swift#L153)
- [`testLongPressHidesASmartListAndSettingsBringsItBack`](../../ios/OneUITests/RemindersListsTests.swift#L164)
- [`testMoveSmartListPillsWithTheMenuAndKeepTheOrder`](../../ios/OneUITests/RemindersListsTests.swift#L186)
- [`testMovePinnedListPillsWithTheMenu`](../../ios/OneUITests/RemindersListsTests.swift#L226)
- [`testLongPressDragReordersSmartListPills`](../../ios/OneUITests/RemindersListsTests.swift#L243)
- [`testLongPressDragReordersLists`](../../ios/OneUITests/RemindersListsTests.swift#L254)

</details>

<details>
<summary>RemindersSyncBothWaysTests (4 methods)</summary>

Source: [ios/OneUITests/RemindersSyncBothWaysTests.swift](../../ios/OneUITests/RemindersSyncBothWaysTests.swift).

- [`testAppChangesReachAppleReminders`](../../ios/OneUITests/RemindersSyncBothWaysTests.swift#L62)
- [`testAppleChangesReachTheApp`](../../ios/OneUITests/RemindersSyncBothWaysTests.swift#L75)
- [`testCompletingARepeatingReminderInTheAppRollsItForward`](../../ios/OneUITests/RemindersSyncBothWaysTests.swift#L94)
- [`testCompletingARepeatingReminderInAppleRollsItForwardInTheApp`](../../ios/OneUITests/RemindersSyncBothWaysTests.swift#L105)

</details>

<details>
<summary>RemindersSyncTests (1 methods)</summary>

Source: [ios/OneUITests/RemindersSyncTests.swift](../../ios/OneUITests/RemindersSyncTests.swift).

- [`testReminderRoundTripsThroughAppleReminders`](../../ios/OneUITests/RemindersSyncTests.swift#L15)

</details>

<details>
<summary>RepeatingReminderTests (2 methods)</summary>

Source: [ios/OneUITests/RepeatingReminderTests.swift](../../ios/OneUITests/RepeatingReminderTests.swift).

- [`testCompletingARepeatingReminderMovesItToItsNextDay`](../../ios/OneUITests/RepeatingReminderTests.swift#L37)
- [`testUndoBringsBackTheSameRowAtTheSameTime`](../../ios/OneUITests/RepeatingReminderTests.swift#L70)

</details>

<details>
<summary>SettingsChoicesTests (21 methods)</summary>

Source: [ios/OneUITests/SettingsChoicesTests.swift](../../ios/OneUITests/SettingsChoicesTests.swift).

- [`testDimPastDaysSettingTurnsTheDimmingOffAndOn`](../../ios/OneUITests/SettingsChoicesTests.swift#L119)
- [`testDimPastDaysOffAlsoStopsFadingEventsThatAreOver`](../../ios/OneUITests/SettingsChoicesTests.swift#L151)
- [`testWeekendsLookLikeAnyOtherDayInMonth`](../../ios/OneUITests/SettingsChoicesTests.swift#L166)
- [`testWeekendColumnsAreNotShadedInWeek`](../../ios/OneUITests/SettingsChoicesTests.swift#L177)
- [`testFirstDayOfTheWeekSettingMovesTheMonthColumns`](../../ios/OneUITests/SettingsChoicesTests.swift#L196)
- [`testFirstDayOfTheWeekAlsoMovesWeek`](../../ios/OneUITests/SettingsChoicesTests.swift#L216)
- [`testWeekNumbersAppearInMonthAndWeekWhenSwitchedOn`](../../ios/OneUITests/SettingsChoicesTests.swift#L229)
- [`testCalendarOpensOnTheChosenView`](../../ios/OneUITests/SettingsChoicesTests.swift#L249)
- [`testCalendarStartPillsAreInSettings`](../../ios/OneUITests/SettingsChoicesTests.swift#L256)
- [`testEveningHourSettingMovesTheReview`](../../ios/OneUITests/SettingsChoicesTests.swift#L276)
- [`testEveningHourPreferenceIsRespectedAtLaunch`](../../ios/OneUITests/SettingsChoicesTests.swift#L298)
- [`testEarlierEveningHourOpensTheReviewSooner`](../../ios/OneUITests/SettingsChoicesTests.swift#L305)
- [`testShowTomorrowOffHidesTheSection`](../../ios/OneUITests/SettingsChoicesTests.swift#L312)
- [`testFreeTimeRowsCanBeSwitchedOff`](../../ios/OneUITests/SettingsChoicesTests.swift#L319)
- [`testSuggestedTimesCanBeSwitchedOff`](../../ios/OneUITests/SettingsChoicesTests.swift#L330)
- [`testNewReminderListAlarmDefaultsAndAskSuggestionsAreInSettings`](../../ios/OneUITests/SettingsChoicesTests.swift#L339)
- [`testDefaultReminderListChosenInSettingsContainsTheSavedQuickAdd`](../../ios/OneUITests/SettingsChoicesTests.swift#L349)
- [`testDefaultAlarmSoundChosenInSettingsSurvivesSaveAndReopen`](../../ios/OneUITests/SettingsChoicesTests.swift#L379)
- [`testAskPageHidesItsSuggestionsWhenSwitchedOff`](../../ios/OneUITests/SettingsChoicesTests.swift#L428)
- [`testAskPageShowsSuggestionsByDefault`](../../ios/OneUITests/SettingsChoicesTests.swift#L435)
- [`testNewAlarmStartsWithTheChosenSnoozeLength`](../../ios/OneUITests/SettingsChoicesTests.swift#L442)

</details>

<details>
<summary>ShareImportTests (1 methods)</summary>

Source: [ios/OneUITests/ShareImportTests.swift](../../ios/OneUITests/ShareImportTests.swift).

- [`testSharedReminderArrivesOnce`](../../ios/OneUITests/ShareImportTests.swift#L7)

</details>

<details>
<summary>ShareSheetTests (1 methods)</summary>

Source: [ios/OneUITests/ShareSheetTests.swift](../../ios/OneUITests/ShareSheetTests.swift).

- [`testShareAPageFromSafariAddsAReminder`](../../ios/OneUITests/ShareSheetTests.swift#L7)

</details>

<details>
<summary>SidebarTests (9 methods)</summary>

Source: [ios/OneUITests/SidebarTests.swift](../../ios/OneUITests/SidebarTests.swift).

- [`testConversationAppearsInSidebarAndReopens`](../../ios/OneUITests/SidebarTests.swift#L34)
- [`testNewChatStartsEmpty`](../../ios/OneUITests/SidebarTests.swift#L45)
- [`testSwipeLeftDeletesAConversationAndUndoBringsItBack`](../../ios/OneUITests/SidebarTests.swift#L53)
- [`testChatOpenedFromSidebarGoesBackToSidebar`](../../ios/OneUITests/SidebarTests.swift#L71)
- [`testSwipeLeftArchivesAConversationIntoTheArchivedSection`](../../ios/OneUITests/SidebarTests.swift#L89)
- [`testSwipeLeftOnThePageReturnsToToday`](../../ios/OneUITests/SidebarTests.swift#L107)
- [`testLongPressOffersRenameArchiveAndDelete`](../../ios/OneUITests/SidebarTests.swift#L120)
- [`testSidebarHasNoTabRowsAndShowsTheEmptyState`](../../ios/OneUITests/SidebarTests.swift#L139)
- [`testCloseButtonClosesTheSidebar`](../../ios/OneUITests/SidebarTests.swift#L155)

</details>

<details>
<summary>SinglePresentationTests (14 methods)</summary>

Source: [ios/OneUITests/SinglePresentationTests.swift](../../ios/OneUITests/SinglePresentationTests.swift).

- [`testTappingAnEventInWeekOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L42)
- [`testTappingAnEventInMonthOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L50)
- [`testTappingAnEventOnTodayOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L58)
- [`testTappingAReminderOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L64)
- [`testTappingAReminderInAListOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L70)
- [`testTappingAnAlarmOpensOneEditor`](../../ios/OneUITests/SinglePresentationTests.swift#L86)
- [`testLongPressOnAnEmptySlotMakesAnEventThere`](../../ios/OneUITests/SinglePresentationTests.swift#L122)
- [`testLongPressThenDragMovesTheNewEvent`](../../ios/OneUITests/SinglePresentationTests.swift#L137)
- [`testLongPressOnAnEventShowsOnlyItsMenu`](../../ios/OneUITests/SinglePresentationTests.swift#L151)
- [`testDraggingATaskDoesNotMakeAnEvent`](../../ios/OneUITests/SinglePresentationTests.swift#L163)
- [`testTapAndSwipeOnTheGridDoNotMakeAnEvent`](../../ios/OneUITests/SinglePresentationTests.swift#L177)
- [`testYearShowsBusyDays`](../../ios/OneUITests/SinglePresentationTests.swift#L194)
- [`testWeekAndMonthTints`](../../ios/OneUITests/SinglePresentationTests.swift#L206)
- [`testPinchZoomsTheWeekGrid`](../../ios/OneUITests/SinglePresentationTests.swift#L215)

</details>

<details>
<summary>StopwatchTests (8 methods)</summary>

Source: [ios/OneUITests/StopwatchTests.swift](../../ios/OneUITests/StopwatchTests.swift).

- [`testOpensOnTheAnalogDialWithTheRightDotAndSwipesToTheBigDigits`](../../ios/OneUITests/StopwatchTests.swift#L38)
- [`testFrozenFrameReadsLikeTheReferenceShot`](../../ios/OneUITests/StopwatchTests.swift#L56)
- [`testStartLapStopReset`](../../ios/OneUITests/StopwatchTests.swift#L70)
- [`testTheBigDigitsKeepRunningAndStopWithTheButtons`](../../ios/OneUITests/StopwatchTests.swift#L103)
- [`testTheChosenFaceIsKeptWhenYouLeaveTheTab`](../../ios/OneUITests/StopwatchTests.swift#L118)
- [`testFastestLapIsGreenAndSlowestRedOnceThereAreTwoFinishedLaps`](../../ios/OneUITests/StopwatchTests.swift#L130)
- [`testOneFinishedLapIsNotMarked`](../../ios/OneUITests/StopwatchTests.swift#L138)
- [`testScreenshots`](../../ios/OneUITests/StopwatchTests.swift#L148)

</details>

<details>
<summary>SystemEventEditorTests (1 methods)</summary>

Source: [ios/OneUITests/SystemEventEditorTests.swift](../../ios/OneUITests/SystemEventEditorTests.swift).

- [`testOpeningASystemEventShowsTheEditorWithOneDelete`](../../ios/OneUITests/SystemEventEditorTests.swift#L13)

</details>

<details>
<summary>TabMemoryTests (1 methods)</summary>

Source: [ios/OneUITests/TabMemoryTests.swift](../../ios/OneUITests/TabMemoryTests.swift).

- [`testTabsKeepTheirPlace`](../../ios/OneUITests/TabMemoryTests.swift#L5)

</details>

<details>
<summary>TidyOverdueTests (1 methods)</summary>

Source: [ios/OneUITests/TidyOverdueTests.swift](../../ios/OneUITests/TidyOverdueTests.swift).

- [`testTidyOverdueMovesTheDateOnlyOnApplyAndUndoBringsItBack`](../../ios/OneUITests/TidyOverdueTests.swift#L7)

</details>

<details>
<summary>TimerTests (16 methods)</summary>

Source: [ios/OneUITests/TimerTests.swift](../../ios/OneUITests/TimerTests.swift).

- [`testScreenIsAppleTimersWithoutEdit`](../../ios/OneUITests/TimerTests.swift#L87)
- [`testWheelsSetTheTimeAndEnableStart`](../../ios/OneUITests/TimerTests.swift#L102)
- [`testStartFromTheWheelWithALabel`](../../ios/OneUITests/TimerTests.swift#L112)
- [`testPresetsFillRecentsUntilYouStartYourOwn`](../../ios/OneUITests/TimerTests.swift#L126)
- [`testOwnRecentsReplaceThePresets`](../../ios/OneUITests/TimerTests.swift#L137)
- [`testPlayStartsAtOnceAndTheRecentMovesToTheTop`](../../ios/OneUITests/TimerTests.swift#L147)
- [`testTapOnARowLoadsItIntoThePickerWithoutStarting`](../../ios/OneUITests/TimerTests.swift#L159)
- [`testSwipeLeftDeletesARecent`](../../ios/OneUITests/TimerTests.swift#L169)
- [`testSeededPresetsHaveNothingToDelete`](../../ios/OneUITests/TimerTests.swift#L178)
- [`testSeveralRunningTimersStackAboveThePicker`](../../ios/OneUITests/TimerTests.swift#L187)
- [`testPauseResumeAndCancelFromTheCard`](../../ios/OneUITests/TimerTests.swift#L210)
- [`testRingingCardOffersStop`](../../ios/OneUITests/TimerTests.swift#L224)
- [`testFocusRoundsAreACaptionUnderRecents`](../../ios/OneUITests/TimerTests.swift#L235)
- [`testPlayingTheFocusPresetStartsAFocusTimer`](../../ios/OneUITests/TimerTests.swift#L244)
- [`testStartWithoutAlarmAccessExplains`](../../ios/OneUITests/TimerTests.swift#L259)
- [`testTimerTabNotesWhatSiriCannotShare`](../../ios/OneUITests/TimerTests.swift#L273)

</details>

<details>
<summary>TodayTimelineTests (7 methods)</summary>

Source: [ios/OneUITests/TodayTimelineTests.swift](../../ios/OneUITests/TodayTimelineTests.swift).

- [`testTodayNamesItsDayAndHasNoScheduleLabel`](../../ios/OneUITests/TodayTimelineTests.swift#L21)
- [`testRowSubtitlesKeepTwoFactsAtMost`](../../ios/OneUITests/TodayTimelineTests.swift#L27)
- [`testNoSeparateDueTodaySection`](../../ios/OneUITests/TodayTimelineTests.swift#L36)
- [`testTimedReminderSitsAtItsTime`](../../ios/OneUITests/TodayTimelineTests.swift#L40)
- [`testUntimedReminderIsSuggestedAndPlannedOnTap`](../../ios/OneUITests/TodayTimelineTests.swift#L48)
- [`testFreeTimeShowsAfterTheSuggestions`](../../ios/OneUITests/TodayTimelineTests.swift#L58)
- [`testOverdueStaysOutOfTheTimeline`](../../ios/OneUITests/TodayTimelineTests.swift#L66)

</details>

<details>
<summary>TodayTimerTests (6 methods)</summary>

Source: [ios/OneUITests/TodayTimerTests.swift](../../ios/OneUITests/TodayTimerTests.swift).

- [`testNoTimerNoRow`](../../ios/OneUITests/TodayTimerTests.swift#L22)
- [`testTwoRowsThenMore`](../../ios/OneUITests/TodayTimerTests.swift#L28)
- [`testPauseResumeAndStopFromTheRow`](../../ios/OneUITests/TodayTimerTests.swift#L40)
- [`testTapOpensTheTimerTab`](../../ios/OneUITests/TodayTimerTests.swift#L59)
- [`testStartingOnTheTimerTabShowsOnToday`](../../ios/OneUITests/TodayTimerTests.swift#L68)
- [`testTimerTabNotesWhatSiriCannotShare`](../../ios/OneUITests/TodayTimerTests.swift#L86)

</details>

<details>
<summary>TodayTomorrowTests (3 methods)</summary>

Source: [ios/OneUITests/TodayTomorrowTests.swift](../../ios/OneUITests/TodayTomorrowTests.swift).

- [`testMorningShowsTheStartOfTomorrow`](../../ios/OneUITests/TodayTomorrowTests.swift#L32)
- [`testEveningShowsAllOfTomorrow`](../../ios/OneUITests/TodayTomorrowTests.swift#L49)
- [`testHeaderOpensTomorrowAsItsOwnDay`](../../ios/OneUITests/TodayTomorrowTests.swift#L58)

</details>

### Pure logic and eval suites

These run in the macOS package (`ios/Package.swift`), not the simulator.

| Suite | Source | Declared methods |
|---|---|---|
| `AICaptureMappingTests` | [AICaptureMappingTests.swift](../../ios/Eval/Tests/OneLogicTests/AICaptureMappingTests.swift) | 24 |
| `ActivityLedgerTests` | [ActivityLedgerTests.swift](../../ios/Eval/Tests/OneLogicTests/ActivityLedgerTests.swift) | 9 |
| `ActivityRecorderTests` | [ActivityRecorderTests.swift](../../ios/Eval/Tests/OneLogicTests/ActivityRecorderTests.swift) | 15 |
| `ActivityStoreTests` | [ActivityStoreTests.swift](../../ios/Eval/Tests/OneLogicTests/ActivityStoreTests.swift) | 23 |
| `AlarmCaptureTests` | [AlarmCaptureTests.swift](../../ios/Eval/Tests/OneLogicTests/AlarmCaptureTests.swift) | 3 |
| `AppearanceTests` | [AppearanceTests.swift](../../ios/Eval/Tests/OneLogicTests/AppearanceTests.swift) | 5 |
| `AskCardTests` | [AskCardTests.swift](../../ios/Eval/Tests/OneLogicTests/AskCardTests.swift) | 9 |
| `AskSuggestionsTests` | [AskSuggestionsTests.swift](../../ios/Eval/Tests/OneLogicTests/AskSuggestionsTests.swift) | 23 |
| `AutonomyPolicyTests` | [AutonomyPolicyTests.swift](../../ios/Eval/Tests/OneLogicTests/AutonomyPolicyTests.swift) | 5 |
| `CalendarAlarmsTests` | [CalendarAlarmsTests.swift](../../ios/Eval/Tests/OneLogicTests/CalendarAlarmsTests.swift) | 9 |
| `CaptureCardStateTests` | [CaptureCardStateTests.swift](../../ios/Eval/Tests/OneLogicTests/CaptureCardStateTests.swift) | 9 |
| `CaptureEvalTests` | [CaptureEvalTests.swift](../../ios/Eval/Tests/OneLogicTests/CaptureEvalTests.swift) | 1 |
| `CaptureLeadInTests` | [CaptureLeadInTests.swift](../../ios/Eval/Tests/OneLogicTests/CaptureLeadInTests.swift) | 9 |
| `ChatRoutingTests` | [ChatRoutingTests.swift](../../ios/Eval/Tests/OneLogicTests/ChatRoutingTests.swift) | 28 |
| `CityDatabaseTests` | [CityDatabaseTests.swift](../../ios/Eval/Tests/OneLogicTests/CityDatabaseTests.swift) | 15 |
| `WorldClockLookTests` | [CityDatabaseTests.swift](../../ios/Eval/Tests/OneLogicTests/CityDatabaseTests.swift) | 7 |
| `WorldClockTests` | [ClockLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/ClockLogicTests.swift) | 6 |
| `OverlapTests` | [ClockLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/ClockLogicTests.swift) | 11 |
| `StopwatchTests` | [ClockLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/ClockLogicTests.swift) | 6 |
| `ConversationHistoryTests` | [ConversationHistoryTests.swift](../../ios/Eval/Tests/OneLogicTests/ConversationHistoryTests.swift) | 5 |
| `AutoArchiveTests` | [ConversationHistoryTests.swift](../../ios/Eval/Tests/OneLogicTests/ConversationHistoryTests.swift) | 2 |
| `DialogueTests` | [DialogueTests.swift](../../ios/Eval/Tests/OneLogicTests/DialogueTests.swift) | 13 |
| `EditRoutingTests` | [EditRoutingTests.swift](../../ios/Eval/Tests/OneLogicTests/EditRoutingTests.swift) | 15 |
| `EveningReviewTests` | [EveningReviewTests.swift](../../ios/Eval/Tests/OneLogicTests/EveningReviewTests.swift) | 6 |
| `EventMatchTests` | [EventMatchTests.swift](../../ios/Eval/Tests/OneLogicTests/EventMatchTests.swift) | 4 |
| `HealthLoadingTests` | [HealthLoadingTests.swift](../../ios/Eval/Tests/OneLogicTests/HealthLoadingTests.swift) | 13 |
| `HealthLogicTests` | [HealthLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/HealthLogicTests.swift) | 3 |
| `HealthMetricsTests` | [HealthMetricsTests.swift](../../ios/Eval/Tests/OneLogicTests/HealthMetricsTests.swift) | 26 |
| `IntentTests` | [IntentTests.swift](../../ios/Eval/Tests/OneLogicTests/IntentTests.swift) | 11 |
| `LedgerFormatTests` | [LedgerFormatTests.swift](../../ios/Eval/Tests/OneLogicTests/LedgerFormatTests.swift) | 6 |
| `ListGuessTests` | [ListGuessTests.swift](../../ios/Eval/Tests/OneLogicTests/ListGuessTests.swift) | 8 |
| `LockScreenNextTests` | [LockScreenNextTests.swift](../../ios/Eval/Tests/OneLogicTests/LockScreenNextTests.swift) | 14 |
| `RepeatRuleTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 4 |
| `RecurrenceTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 2 |
| `ReminderPlanTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 1 |
| `DayPlannerTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 2 |
| `DayScheduleTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 7 |
| `ListNameTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 1 |
| `AlarmPlanTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 12 |
| `CalendarMathTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 6 |
| `CalendarLayoutTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 11 |
| `SearchMatchTests` | [LogicTests.swift](../../ios/Eval/Tests/OneLogicTests/LogicTests.swift) | 4 |
| `MessageCopyLogicTests` | [MessageCopyLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/MessageCopyLogicTests.swift) | 3 |
| `MovingAverageTests` | [MovingAverageTests.swift](../../ios/Eval/Tests/OneLogicTests/MovingAverageTests.swift) | 8 |
| `NewReminderDraftTests` | [NewReminderDraftTests.swift](../../ios/Eval/Tests/OneLogicTests/NewReminderDraftTests.swift) | 5 |
| `OverdueTidyTests` | [OverdueTidyTests.swift](../../ios/Eval/Tests/OneLogicTests/OverdueTidyTests.swift) | 5 |
| `PillOrderTests` | [PillOrderTests.swift](../../ios/Eval/Tests/OneLogicTests/PillOrderTests.swift) | 7 |
| `PomodoroTests` | [PomodoroTests.swift](../../ios/Eval/Tests/OneLogicTests/PomodoroTests.swift) | 9 |
| `PreferencesTests` | [PreferencesTests.swift](../../ios/Eval/Tests/OneLogicTests/PreferencesTests.swift) | 17 |
| `QuickTimeTests` | [QuickTimeTests.swift](../../ios/Eval/Tests/OneLogicTests/QuickTimeTests.swift) | 5 |
| `ReminderSuggestTests` | [ReminderSuggestTests.swift](../../ios/Eval/Tests/OneLogicTests/ReminderSuggestTests.swift) | 3 |
| `RepeatAdvanceTests` | [RepeatAdvanceTests.swift](../../ios/Eval/Tests/OneLogicTests/RepeatAdvanceTests.swift) | 8 |
| `RowSubtitleTests` | [RowSubtitleTests.swift](../../ios/Eval/Tests/OneLogicTests/RowSubtitleTests.swift) | 11 |
| `ShareInboxTests` | [ShareInboxTests.swift](../../ios/Eval/Tests/OneLogicTests/ShareInboxTests.swift) | 3 |
| `StopwatchLogicTests` | [StopwatchLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/StopwatchLogicTests.swift) | 13 |
| `TabMemoryLogicTests` | [TabMemoryLogicTests.swift](../../ios/Eval/Tests/OneLogicTests/TabMemoryLogicTests.swift) | 2 |
| `TimerDialTests` | [TimerDialTests.swift](../../ios/Eval/Tests/OneLogicTests/TimerDialTests.swift) | 3 |
| `TimerListTests` | [TimerListTests.swift](../../ios/Eval/Tests/OneLogicTests/TimerListTests.swift) | 17 |
| `TimerPhraseTests` | [TimerListTests.swift](../../ios/Eval/Tests/OneLogicTests/TimerListTests.swift) | 7 |
| `TimerRecentsTests` | [TimerRecentsTests.swift](../../ios/Eval/Tests/OneLogicTests/TimerRecentsTests.swift) | 11 |
| `TravelTimeTests` | [TravelTimeTests.swift](../../ios/Eval/Tests/OneLogicTests/TravelTimeTests.swift) | 13 |
| `WidgetSnapshotTests` | [WidgetSnapshotTests.swift](../../ios/Eval/Tests/OneLogicTests/WidgetSnapshotTests.swift) | 20 |
| `YearMarksTests` | [YearMarksTests.swift](../../ios/Eval/Tests/OneLogicTests/YearMarksTests.swift) | 27 |

All individual pure method names/line numbers are available through `--inventory`; the UI list above is expanded for journey selection.
