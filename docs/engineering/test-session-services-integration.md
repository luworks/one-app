# Deterministic planner test services

Base: `8bbddffa8c307c75429e5ca117f763ee067eb7db`.
Owned implementation: `ios/Sources/TodayTestSupport/PlannerTestServices.swift` only.
The support target stays outside the production dependency closure. All declarations are iOS-guarded; no package, model, contract, configuration or other source was changed by this lane.

## Assembly API

```swift
@MainActor
package init(container: ModelContainer, defaults: UserDefaults,
             runtime: PlannerRuntime, arguments: [String]) throws
package func dispose()
```

The initializer throws only when opening the real memory ActivityStore fails. Root/Workbench must use `try`, retain the assembly, and surface that failure rather than silently disabling Activity. Root supplies an in-memory container, a distinct defaults suite for each session, a deterministic runtime (including its ID sequence), and explicit arguments. There is no process-argument read, implicit defaults selection, system clock/calendar lookup or production service construction here.

Retained package properties: `container`, `defaults`, `runtime`, concrete `calendar: TestCalendarService`, `reminders: TestReminderService`, `alarms: TestAlarmService`, `timers: TestTimerService`, `notifications: TestNotificationService`, `travel: TestTravelTimes`, `soundPreview: TestSoundPreview`, `activityStore: ActivityStore`, `activity: ActivityCenter`, `ledger: Ledger`, `actions: PlannerActions`, and `isDisposed`. Pass these narrow capabilities to feature constructors and install the real `actions` in the environment. Root constructs presentation, Ask and Health capabilities separately.

The ActivityStore uses `.memory`; ActivityCenter, Ledger and PlannerActions are the existing implementations, wired to the same supplied runtime and reminder fake. No action, recurrence, capture, grant, save or Undo algorithm is copied into this support file. In particular, fake completion does not mutate the model: real TaskActions still commits the receipt before the local save and captures the accepted receipt for Undo.

## Observable capabilities and inspectable outcomes

All seven fake classes use `@MainActor @Observable`. Existential property reads reach their actual tracked properties/computed-property inputs; no detached observable facade is used.

- Calendar starts ready, off, without access, with empty calendar/event arrays. `setEnabled` records requests and updates only local enabled/access/version state. Fixtures can set `hasAccess`, `isReady`, `isQuerying`, `lastError`, `availableCalendars`, `queryEvents` and hidden IDs. Query filtering uses explicit runtime calendar and interval overlap. Permission revocation makes `isOn` false immediately. It conforms only to CalendarService, never NativeCalendarService; native editing, external saves, rename, audience and deletion are unsupported. Existing local calendar model editing remains with real actions. `refreshCount` and `enableRequests` are inspectable.
- Reminders starts disconnected. `connect()` applies configurable `connectionGranted`; access, denial, error and reconciliation state are directly inspectable. `completionCalls` records model identity, external ID, requested completion, restore-due inputs and the exact expected receipt. Local tasks return nil without remote access. Linked tasks require connected access; `completionFailure` throws deterministically, and `completionReceipt` optionally supplies the accepted plain-value receipt. Otherwise a `RemindersSync.Remote` is created using its existing value initializer and runtime time. No EKReminder is created. `currentRemote` models the current fingerprint/doneAt receipt for expected-receipt fencing; changing it can simulate an outside edit. Persisted completion IDs, deleted reminder/list IDs, reconciliation delays/count and connect count are available. Reconciliation records requests without starting a background pass or pretending to synchronize Apple data. `-uiTestingFailReminderCompletion` preserves the linked failure injection.
- Alarms exposes authorization/response, availability and states; request/sync counts and stopped IDs are recorded. Stop only removes the local alarm state. Watch performs one local sync and returns; it starts no driver or observer.
- Notifications starts authorized and exposes status, configurable permission response, request count and resync count. No notification center is obtained.
- Sound records `playedNames`, `selectedName` and stop count. It reads only AlarmSound.name, without URL/resource lookup or audio calls.
- Travel starts with an empty cache and returns nil. Tests can supply `TravelEstimate` entries keyed with TravelTime.cacheKey using the same runtime calendar. Eligibility, cache keys, usable estimate, minutes and leave-by use real shared value rules. Label formatting uses the explicit runtime locale/calendar/time zone. No lookup, permission request, location manager or network work is started.

## Local timer behavior and legacy fixtures

TestTimerService uses TodayCore's existing RunningTimer value (the current source name, not a new CoreRunningTimer wrapper), TimerList, TimerRecents and Pomodoro rules. Start clamps duration, normalizes labels, allocates through runtime.nextID, replaces only the existing Pomodoro timer for preset starts, clears replaced ringing IDs, and records recents. Pause/resume use the same value transformations. Cancel/Stop removes only the local timer; a ringing Pomodoro counts through the real log rule and never completes a task. `startsByHand` records the input without donating an intent.

`liveStates` can explicitly project running/paused/ringing/missing IDs; refresh then uses TimerList.reconcile and PomodoroLog.completing. Outside legacy fixtures, nil derives these states from local timers and runtime time. No timer driver runs. Watch refreshes once and returns; tests advance their runtime and call refresh explicitly.

Legacy parsing was inspected against `git show 81d020d:ios/Sources/One/TimerController.swift`:

- `-uiTestingTimers 600:Pasta,1500,300:Tea:paused,60:Eggs:ringing`: comma entries, colon fields with empty labels retained, invalid integer durations skipped, voice-source timers, independent paused/ringing markers. Only identity/time generation changes to the explicit runtime.
- `-uiTestingRecents 420,1200,1200:go to lion market`: input order is newest-first; split once at the colon; invalid integer durations skipped; labels use RecentTimer normalization.
- `-pomodoroRounds N`: integer rounds are preserved, pending is Focus only when N > 0, day comes from runtime. Without this flag, `-uiTesting` starts with an empty log.
- `-uiTesting` starts empty timers/recents/sound instead of loading prior values. Timer and recents mutations do not persist in this mode, matching the former implementation. Sound changes and log changes write only the explicitly supplied defaults. With no `-uiTesting`, stores also use only those defaults.
- Refresh for `-uiTesting` or `-uiTestingTimers` keeps the legacy fixture list/ringing state frozen, apart from midnight log reset. An explicit non-nil `liveStates` opts into deterministic reconciliation for integration tests. All starts/pauses/resumes/stops are local regardless of arguments.

## Two-session integration and disposal

Root's integration tests can construct two assemblies with separate containers/defaults and distinct runtime ID streams. Drive both via existential capabilities and real actions. Assert independent query/auth/timer state, expected receipt calls, model writes, real ledger rows and Activity pause/grant behavior. Mutation observation can be tested with withObservationTracking on the existential's isOn/hasAccess/timers/log reads. These are integration acceptance conditions, not tests executed by this lane.

Cancel view-owned tasks, UndoToast and callbacks before disposing. `dispose()` marks/cancels only these fakes, stops this sound preview, then calls the real Ledger.dispose before ActivityCenter.dispose. Ledger flushes its pending model-backed entries; Activity flushes its recorder and cancels its own delayed flush tasks. The method is idempotent. It never removes defaults or cancels another session's work. Root removes its isolated defaults afterward and must stop using retained actions after disposal. No fake starts its own background task.

## Lightweight validation and limits

The iOS DEBUG Swift frontend syntax parse passed, as did git diff --check and the bounded source audit. Source inspection confirmed seven observable fake conformances, the real memory Activity/action graph, explicit runtime/defaults use, legacy argument parsing and absence of native adapter constructors, shared services, permission APIs, unsafe Sendable or fresh UUID allocation in this file.

Raw evidence and file hashes are retained in the primary checkout under `tests/results/test-session-services-20261018-ff74a691/` and indexed in the QA SQLite journal. Syntax parsing emits the host macOS sysroot/iOS target warning; it does not resolve imported types, expand/validate Observation macros or type-check conformances. No SwiftPM test/build, Xcode build, simulator, device or runtime two-session test was run: the parent exclusively owns heavy validation. Integrated type checking and real two-session action/observation/Undo tests remain required. This implementation provides no EventKit, AlarmKit, notification delivery or physical-device acceptance evidence.
