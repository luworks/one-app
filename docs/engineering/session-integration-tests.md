# Native planner session integration tests

Base parent commit: `ffc704de43ad451e5ee3866102409a1986b2548d`.
Owned files: `ios/TodayIntegrationTests/PlannerSessionTests.swift` and this note only.

## Assembly and test boundary

`PlannerSessionTests` uses Swift Testing (`@Test`, `#expect`, `#require`) under `#if os(iOS)` and runs on the main actor. It imports One, TodayCore, TodayData and TodayTestSupport. Root owns native target membership, dependency linkage, the Swift package identity needed for `package` access, Swift 6 type checking and the build/test lane. This change does not edit package/project configuration or existing tests.

Each test creates two simultaneous independent sessions. Each session retains:

- A real SwiftData in-memory container with the exact nine production model types: OneTask, OneEvent, OneAlarm, OneList, Habit, ChatThread, LedgerEntry, AIGrant and ShareImportReceipt. No persistent declaration, field or model module moves.
- Its own UUID-named UserDefaults suite, cleared before construction and after disposal.
- Its own deterministic clock and non-overlapping ID stream, captured by PlannerRuntime's Sendable closures. Synchronization.Mutex protects these small test values without unchecked Sendable or actor escapes. The calendar is Gregorian UTC and locale is en_US_POSIX; paired session clocks differ.
- `try PlannerTestServices(container:defaults:runtime:arguments: [])`, retaining the real memory ActivityStore, ActivityCenter, Ledger and PlannerActions.
- A real UndoToast, disposed before the service graph. Ledger flushes are explicit, so assertions do not sleep for debounce or UI animation timing.

The Session helper constructs fixtures through real capture insertion, queries real models and pages the real Activity store. It does not copy action, recurrence, planning, grant, save or Undo algorithms. Small test inputs are inline in this native test file. The fake remote receipt uses the existing RemindersSync.Remote value initializer without constructing EventKit objects.

These are service/action integration sessions; the tests do not construct the production PlannerSession wrapper, WidgetFeed or framework-backed composition. Native controls, card resolution and environment propagation remain root/UI acceptance work.

## Behavioral coverage

| Method | Assertions |
| --- | --- |
| `existentialObservationAndDisposalStayInsideTheirSession` | Reads through CalendarService, ReminderService and TimerService existentials trigger Observation when their underlying values change. Calendar permission revocation is observable. Timer starts use different IDs/clocks, defaults and pause/resume remain local, repeated pause/resume/cancel is harmless. Double disposal flushes only its own pending Activity entry and stops its own timer capability; the peer's pending ledger and timer stay usable. |
| `addApplyAndActivityUndoPersistWithoutChangingDeadlineOrPeer` | A capture preview writes nothing. Explicit Add inserts a real task and final identity/reference. Apply calls real setPlanned with AI/Ask approval, preserves due and identity, and duplicate placement creates no ledger entry. Activity Undo restores the plan and then removes the created task; repeated Undo is refused. Native legacy LedgerEntry rows remain unused and the peer stays empty. |
| `automaticPlanningRequiresRecordedChangesAndPreservesScopeAndUndo` | No grant, paused Activity and disabled Changes each prevent placement. With recording enabled, a grant places only the eligible due-today reminder after a fixed meeting. Overdue, future, completed, alarm-linked, timed-deadline and user-unscheduled reminders stay unplanned. Activity records AI/automatic/grant approval. Repeated planning adds nothing; toast Undo restores the original due/plan, and recent-AI protection prevents immediate replacement. The peer receives no grant or plan. |
| `sevenDayExpiryAndRevocationUseOnlyTheirSessionClockAndStore` | Settings grant is idempotent and expires exactly seven calendar days later. It is active one second before expiry and inactive at expiry; automatic planning then refuses work. Advancing one clock does not expire the peer's grant. Repeated revocation records one revocation and never mutates the other grant. |
| `localRecurrenceToastUndoRestoresOccurrenceAndCannotResurrectDeletedTask` | Real completion creates one next local daily occurrence with advanced due and new checklist identity. Toast Undo preserves the original model identity and removes the next occurrence once. Undo after the original has been deleted makes no completion call and cannot resurrect it. The peer remains untouched. |
| `completionUndoPassesAcceptedReceiptAndRefusesOutsideEdit` | Linked recurrence does not spawn a local duplicate. Real completion captures the accepted receipt; toast Undo passes its ID/fingerprint/doneAt and original due, restores a rolled-forward due/plan, and runs once. A changed remote fingerprint in the peer rejects Undo before local mutation or an undone Activity event, while retaining a useful failure notice. |
| `rejectedRemoteCompletionAndAlarmStopNeverCompleteAnotherTask` | Rejected remote completion leaves done/doneAt and Activity unchanged. Repeated alarm Stop removes only that session's ringing state and never attempts task completion. Only an explicit successful completion retry changes the task and records completion. |

## Exact API handoff

The tests call existing APIs without requesting new support contracts:

```swift
try PlannerTestServices(container: container, defaults: defaults, runtime: runtime, arguments: [])
try services.actions.insert(capture, into: context, actor: .todayAI, channel: .ask, approval: .asked)
services.actions.setPlanned(task, to: start, context: context, actor: .todayAI, channel: .ask, approval: .asked)
services.actions.undo(persistedEntry, context: context)
services.actions.toggleDone(task, context: context, toast: toast)
services.actions.autoPlan(context: context, toast: toast)
try GrantStore.setEnabled(true, scope: .planFreeTime, context: context, ledger: services.ledger, runtime: runtime)
services.ledger.flush(context)
try services.activityStore.page(ActivityQuery(tiers: [.changes]), limit: 150)
toast.performUndo()
toast.dispose()
services.dispose()
```

Ledger.record returns before the pending item acquires its final model reference. The Activity Undo test therefore flushes and retrieves the stored LedgerItem by returned entry ID before calling actions.undo. It checks the decoded reference against the saved task identity. Completion toast Undo deliberately uses the existing captured receipt path; Activity completion Undo has a different contract and is not substituted for it.

The receipt-fence scenario changes the fake's current remote fingerprint while preserving its identity and completion timestamp. It checks real TaskActions error handling and captured expected arguments, not EventKit's external-edit detection implementation.

## Validation and evidence

Executed in this lane: one iOS DEBUG Swift frontend syntax parse, one bounded source/API audit, and whitespace checking. Syntax parsing passed with the host macOS sysroot/iOS target warning. It does not resolve imported types, validate macros, or prove Swift 6 isolation and native target access.

Canonical evidence: `/Users/yuanlu/code/one-app/tests/results/planner-session-tests-20261018-ffc704de/`.
QA journal session: `planner-session-tests-ffc704de`, using the primary checkout's `tests/results/activity.sqlite`. Raw syntax output, bounded audit and owned-file diff are retained and hashed through `tests/qa/journal.py`.

No SwiftPM test/build, Xcode build/test, simulator or physical-device command ran. All seven test methods are authored but **unrun**. Root must wire the native test bundle to the same Swift package identity as the package modules, link TodayTestSupport/One/Core/Data, and run the native suite after architecture integration. A macOS SwiftPM pass would exclude this iOS-guarded suite and cannot serve as its acceptance.

Remaining gates include imported API/macro type checking, actual two-session Observation/runtime assertions, production Scene/PlannerSession assembly, real Add/Apply card UI, capture save-failure preview retention, accepted remote write followed by local save failure, EventKit reconciliation fencing, shared live AlarmKit alarm/timer ownership, widget/inbox behavior and physical-device delivery. No failure-injecting ModelContext API was added; local save failure is not claimed by these tests. Timed Capture conversion/summary still uses existing Core presentation rules; this suite uses untimed captures and makes no claim of eliminating that existing global-calendar path. Persistent store upgrade/identity compatibility remains covered by the separately owned StoreUpgradeTests, not an in-memory claim here.
