# Permanent test inputs

These JSON inputs are versioned, read-only assets. UI tests resolve their names through
`TestData.fixturePath` / `TestData.fixtureArguments` in
[`UITestHelpers.swift`](../../ios/OneUITests/UITestHelpers.swift).
`TestData.path` and `TestData.launchArguments` continue to select the canonical
`today-dataset.json`; that dataset is unchanged.

| Dataset | Consumers and original generator |
| --- | --- |
| [`today-dataset.json`](today-dataset.json) | Shared UI journeys using `TestData.launchArguments` / `TestData.path`, including `DevDataTests.testDatasetFillsChatsAlarmsAndReminders` and the ordinary `CalendarAlarmTests.launch(pinned:)` setup. This is the canonical multi-screen dataset, not a generated per-run input. |
| [`year-day-month-agenda.json`](year-day-month-agenda.json) | `CalendarTabTests.testYearDayOpensMonthWithChosenDateAndItsItems`: an all-day event and a planned reminder on today and 400 days later. Verifies Year day taps select the exact date in Month and list only its items, including across years. |
| [`week-alarm-overlap-1.json`](week-alarm-overlap-1.json) | `CalendarAlarmTests.testWeekOverlappingEventAndAlarmHaveDisjointFramesAndOpenAlarmEditor` → `assertWeekOverlap(eventCount: 1)`. Replaces that helper's temporary JSON generator: event `Lane overlap event 0`, today at 09:00 for 60 minutes; `Lane overlap alarm` at 09:30. Clock pinned to 09:00; alarms pinned on. |
| [`week-alarm-overlap-8.json`](week-alarm-overlap-8.json) | `CalendarAlarmTests.testWeekDenseOverlapClusterStaysInsideAssignedFramesAndOpensAlarmEditor` → `assertWeekOverlap(eventCount: 8)`. Replaces the same generator with events `Lane overlap event 0` through `7`, all today at 09:00 for 60 minutes, and the same 09:30 alarm. Clock pinned to 09:00; alarms pinned on. |
| [`week-alarm-afternoon.json`](week-alarm-afternoon.json) | `CalendarAlarmTests.testWeekLateAlarmOpensItsEditorWithoutOtherEntries`. Minimal issue #53 reproduction: one Take medicine alarm at 13:00, no events/reminders/chats; clock pinned to 09:00 and alarms on. Distinguishes late-grid touch delivery from event density or task gestures. |
| [`repeating-reminder-daily-home.json`](repeating-reminder-daily-home.json) | `RepeatingReminderTests.setUp()` for `testCompletingARepeatingReminderMovesItToItsNextDay` and `testUndoBringsBackTheSameRowAtTheSameTime`. Replaces its temporary JSON generator: Home list (color 1), daily `Clean the drain filter`, due today at 07:00 and planned at 09:00. Clock pinned to 09:41. |

## Dates, defaults and isolation

Dates are relative: `day: 0` means the local start of the day the fixture loads,
`day: 1` tomorrow, and negative offsets earlier days. `time` is a local `HH:mm`
wall-clock time. `-uiTestingNow` pins the clock time used by these journeys; it
does not turn the relative day into a fixed calendar date. Chats use `hoursAgo`
relative to load time. The loader is [`TestDataset.swift`](../../ios/One/TestDataset.swift).

`-uiTesting -dataset <path>` loads into a fresh in-memory store with Apple Calendar
and Reminders sync off. Mutations affect that store, not the source JSON. Explicit
persistence/sync tests use their own launch hooks instead. Fixtures must never be
deleted in teardown or rewritten during a run, and generated input must not exist
solely in `/tmp`.

The small fixtures preserve the original generators' omitted fields and therefore
the loader defaults. For example, the daily reminder has a 25-minute duration,
empty note/tags/checklist and false flagged/done values by default; overlap alarms
are enabled, snoozable and have no repeating weekdays by default. No explicit
values were added to replace these defaults.

## Other permanent test data

- [`capture-cases.json`](../../ios/Eval/Tests/OneLogicTests/capture-cases.json)
  stays inside the Swift package at `ios/Eval/Tests/OneLogicTests/`. It is already
  versioned, declared as a copied resource in `ios/Package.swift`, and read through
  `Bundle.module` by `CaptureEvalTests`. Moving it here would change package resource
  behavior unnecessarily.
- [`CaptureTitleCleanupTests.swift`](../../ios/Eval/Tests/OneLogicTests/CaptureTitleCleanupTests.swift)
  keeps small Chinese/English title regressions inline: the exact 23:00 sleep
  reminder, dangling temporal connectors, request punctuation, conditions, negation
  and modality, plus model mapping with unchanged date/time/type/repeat fields.
- Small constants and synthetic generators in Swift test files are already
  versioned test inputs. Keep them with their corresponding tests rather than
  duplicating thousands of literals in JSON.
- Synthetic large-data configurations live in versioned test code. Examples:
  `ActivityDataTests.testActivityPagesWithShowMore` requests 400 Activity rows with
  `-uiTestingActivityRows`; `testOldLedgerRowsAreImportedOnceAndRetiredInALaterLaunch`
  requests 12 old ledger rows with `-uiTestingLegacyLedgerRows`.
  `ActivityStoreTests.testBenchmarkLarge` takes its row count from
  `ACTIVITY_BENCH_ROWS` (for example 100000). Keep the generator/configuration in
  test code and archive actual run arguments, environment overrides and results
  separately with the run evidence; do not check in 100000 generated rows.

The UI-test input inventory found only the two temporary JSON generators replaced
above. Screenshot writes are run outputs, not dataset inputs. QA/development action
recording and its SQLite storage are a separate concern from these fixtures.

## Pre-receipt SwiftData migration fixture

`migrations/today-55e73d5.store` is a standalone SQLite backup of a fresh synthetic
file store created by baseline `55e73d5`. Its adjacent JSON records the seed, hash
and expected contents. It contains one `Upgrade baseline 20261018` reminder,
Habit/LedgerEntry tables and no ShareImportReceipt table. It contains no user data.

To repeat the migration check, copy this fixture to a **new, named test store** in
the simulator app's temporary directory while the app is closed; never overwrite
a default/user store. Launch the current app with `-uiTesting -uiTestingStore <name>`.
Verify the original reminder remains and the additive receipt table is available.
For a committed-state accessibility probe also pass `-uiTestingShareInbox`,
`-uiTestingShareID <fresh UUID>` and `-uiTestingShareProbeTitle 'Upgrade baseline 20261018'`;
expect `acknowledged;tasks=1;receipts=0;pending=0`. Do not reseed the reminder.
The fixture is intentionally frozen; future schema changes should keep opening it.

## Bilingual semantic title and conversation evaluation

- [`ai-title-rewrite-cases.json`](ai-title-rewrite-cases.json): 38 authored cases,
  46 turns, 25 development / 13 reserved validation (not blind). Consumed by the
  offline [`TitleQuality/score.py`](../../ios/Eval/TitleQuality/score.py); this is
  an evaluation resource, not an app `TestDataset` JSON. Frozen clock, thread
  transitions, route/type/time, semantic facts, note retention and Add/Apply
  expectations are explained in the [rubric/interface](../../ios/Eval/TitleQuality/README.md).
- [`ai-title-rewrite-observed.json`](ai-title-rewrite-observed.json): sparse
  historical owner-screenshot transcription and attributed review. Unknown notes,
  gates and model path are intentionally omitted, not marked passing. The raw
  screenshot and scorer logs stay in canonical `tests/results/`, indexed by QA
  journal session `ai-title-quality-20261018`. This fixture is evidence for the
  scorer and baseline only, not a fresh app/model execution.
- `AskCardStaysTests` keeps three short capture title journeys inline: the owner's
  exact Chinese sleep request, a pending reminder title draft, and an Added alarm
  title Save/Cancel/reopen/creation-Undo journey. These inputs require no external
  dataset beyond the existing `today-dataset.json` used by the suite.

- `CaptureTitleQualityExportTests` consumes the frozen PR #67 fixture selected by
  `AI_TITLE_EVAL_FIXTURES`, exports actual parser/offline-refinement content to
  `AI_TITLE_EVAL_OUTPUT`, and uses only development watch/sleep/peanut cases.
  It does not feed expected answers to the implementation. UI gates and persisted
  writes remain unobserved; reserved cases and Foundation Models stay unmeasured.

## AI context journeys

[`ai-context-ui.json`](ai-context-ui.json) is consumed by the three methods in
`AIContextJourneyTests`. Its planner starts empty, so Activity must contain no
change-ledger rows before Add. The text-only `Dinner alarm context` chat uses the
existing `[role, text]` format and has no stored preview or created item. Its
assistant aside names watering plants at 09:00; the relevant user request remains
the dinner alarm at 18:00. The journeys cover the exact Chinese three-turn report,
English alarm/date/time corrections, and New chat isolation plus stored-thread
resumption. They use `-uiTesting` and the simulator's production rule fallback;
they do not inject model output or verify Apple Intelligence. Chinese screenshots
are retained as XCTest attachments inside the eventual xcresult bundle.

- `ios/Eval/Tests/OneLogicTests/conversation-journeys.json` is a copied Swift package resource: thirteen bilingual multi-turn journeys with expected route, title, time/date, preview action and zero writes before Add/Apply. `ConversationJourneyTests` exercises the production context resolver, routing and parser; UI journeys additionally check the real confirmation gate.

## Recurring reminder goals

- `ai-title-rewrite-recurring-cases.json`: 16 cases / 19 turns in the existing
  TitleQuality observation/scoring format; 9 development / 7 reserved validation
  cases (reserved, not blind). Exact owner Sunday and Friday+Sunday requests are
  mandatory development inputs. Route, type, time, actual weekdays, title meaning,
  notes and Add/Apply are independent expectations. No observations are invented.
- `RecurringReminderTests` and `RepeatWeekdayTests` keep small pure inputs inline;
  the three observed-goal regression methods additionally read the unchanged
  development cases from `ai-title-rewrite-recurring-cases.json`;
  `RecurringReminderExportTests` reads the versioned fixture with
  `AI_RECURRING_EVAL_FIXTURES` and writes actual fallback artifacts to
  `AI_RECURRING_EVAL_OUTPUT`. Gates, writes and FM remain unmeasured there.
- `AIRecurringReminderTests` reuses `ai-context-ui.json` as an empty planner and
  keeps three short journey inputs inline: Chinese Sunday preview, Friday+Sunday
  Add/editor Save/reopen, English add-repeat/time-correction. These use production
  simulator fallback, not an injected model. XCTest attachments belong in the
  complete retained xcresult bundle.

## SwiftUI development previews

The small inline fixtures in `ios/One/PreviewFixtures.swift` (DEBUG only) seed
three reminder lists and three reminders in an in-memory SwiftData container.
`WorldClockStore.previewFixture()` in `ios/One/WorldClockView.swift` provides
London, Shanghai and Tokyo with Los Angeles as home in a separate store instance.
`HealthMetricDetail.swift`'s `Weight trend` preview reuses the versioned
`HealthSampleSeries.swift` algorithm and `PreviewFixtures.healthNow` fixed date.
The three corresponding `#Preview` declarations render production views.
No required input lives in a temporary directory; screenshots and timing outputs
belong in the persistent QA results directory, not this fixture catalog.
