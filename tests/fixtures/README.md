# Permanent test inputs

These JSON inputs are versioned, read-only assets. UI tests resolve their names through
`TestData.fixturePath` / `TestData.fixtureArguments` in
[`UITestHelpers.swift`](../../ios/OneUITests/UITestHelpers.swift).
`TestData.path` and `TestData.launchArguments` continue to select the canonical
`today-dataset.json`; that dataset is unchanged.

| Dataset | Consumers and original generator |
| --- | --- |
| [`today-dataset.json`](today-dataset.json) | Shared UI journeys using `TestData.launchArguments` / `TestData.path`, including `DevDataTests.testDatasetFillsChatsAlarmsAndReminders` and the ordinary `CalendarAlarmTests.launch(pinned:)` setup. This is the canonical multi-screen dataset, not a generated per-run input. |
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
