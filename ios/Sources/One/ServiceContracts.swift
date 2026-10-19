#if os(iOS)
  import Foundation
  import SwiftUI
  import SwiftData
  import EventKit
  import EventKitUI
  import UserNotifications
  import TodayCore
  import TodayShared

  /// Model-bound compatibility contracts. Implementations are selected by executable composition.
  /// Persistent declarations remain in One; no feature resolves a live service implicitly.
  @MainActor
  package protocol CalendarService: AnyObject {
    var version: Int { get }
    var isReady: Bool { get }
    var hasAccess: Bool { get }
    var isOn: Bool { get }
    var usesNativeEditor: Bool { get }
    var hiddenCalendarIDs: Set<String> { get }
    func prepare()
    func prepareStore()
    func connectIfFirstRun() async
    func setEnabled(_ on: Bool) async
    func refresh()
    func calendars() -> [SystemCalendar]
    func setVisibleCalendars(_ selected: Set<String>)
    func events(in interval: DateInterval, excluding: Set<String>) -> [ExternalEvent]
    func events(on day: Date, excluding: Set<String>) -> [ExternalEvent]
    func calendar(forExternalID id: String?) -> SystemCalendar?
    func place(forExternalID id: String?) -> TravelPlace?
    func color(forExternalID id: String?) -> Color?
    func isHidden(externalID: String?) -> Bool
    func isRepeating(externalID: String?) -> Bool
    func audience(externalID: String?) -> (attendees: Int, isOrganizer: Bool)?
    func canDelete(externalID: String?) -> Bool
    func save(_ event: OneEvent, span: EKSpan) -> String?
    func delete(_ event: OneEvent, span: EKSpan) -> Bool
    func delete(externalID: String?, occurrence: Date?, span: EKSpan) -> Bool
    func removedMirrors(_ events: [OneEvent]) -> [OneEvent]
    func title(externalID: String, occurrence: Date?) -> String?
    func rename(externalID: String, occurrence: Date?, to title: String) -> Bool
  }

  /// Native EventKit UI is an explicit live capability, absent from deterministic sessions.
  @MainActor
  package protocol NativeCalendarService: CalendarService {
    var eventStore: EKEventStore { get }
    func nativeEvent(identifier: String, occurrence: Date?) -> (EKEvent, EKEventStore)?
    func edit(
      identifier: String?, start: Date, end: Date?, fullOptions: Bool,
      onComplete: ((EKEventEditViewAction) -> Void)?)
  }

  @MainActor
  package protocol ReminderService: AnyObject {
    var hasAccess: Bool { get }
    var isConnected: Bool { get }
    var isDenied: Bool { get }
    var lastError: String? { get }
    func connectIfFirstRun() async
    func connect() async
    func disconnect()
    func forgetLink()
    func noteDeleted(reminder externalID: String?)
    func noteDeleted(list externalID: String?)
    func scheduleReconcile(after delay: Duration)
    func reconcile() async
    func commitEdit(_ task: OneTask, draft: TaskSnapshot, expected: TaskSnapshot) throws
      -> RemindersSync.Remote?
    func didPersistEdit(_ task: OneTask, accepted: RemindersSync.Remote?)
    func commitCompletion(
      _ task: OneTask, done: Bool, restoringDue: Date?, restoresDue: Bool,
      expected: RemindersSync.Remote?
    ) throws -> RemindersSync.Remote?
    func didPersistCompletion(_ task: OneTask, restoredDue: Bool)
  }

  @MainActor
  package protocol AlarmService: AnyObject {
    var authorization: AlarmAuthorization { get }
    var states: [UUID: AlarmLiveState] { get }
    var isAvailable: Bool { get }
    func state(of alarm: OneAlarm) -> AlarmLiveState?
    func requestAuthorization() async
    func sync(_ context: ModelContext) async
    func stop(_ id: UUID)
    func watch(context: ModelContext) async
  }

  @MainActor
  package protocol TimerService: AnyObject {
    var timers: [RunningTimer] { get }
    var ringing: Set<UUID> { get }
    var log: PomodoroLog { get }
    var recents: [RecentTimer] { get }
    var sound: String { get set }
    var message: String? { get }
    func start(seconds: Int, label: String?, byHand: Bool) async -> RunningTimer?
    func pause(_ id: UUID)
    func resume(_ id: UUID)
    func cancel(_ id: UUID)
    func deleteRecent(id: String)
    func refresh()
    func watch() async
  }

  @MainActor
  package protocol NotificationService: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestPermission() async -> Bool
    func resync() async
  }

  // Convenience arguments preserve call semantics while always dispatching to the injected instance.
  extension CalendarService {
    package func events(in interval: DateInterval) -> [ExternalEvent] {
      events(in: interval, excluding: [])
    }
    package func events(on day: Date) -> [ExternalEvent] { events(on: day, excluding: []) }
    package func save(_ event: OneEvent) -> String? { save(event, span: .futureEvents) }
    package func delete(_ event: OneEvent) -> Bool { delete(event, span: .futureEvents) }
    package func delete(externalID: String?, occurrence: Date? = nil) -> Bool {
      delete(externalID: externalID, occurrence: occurrence, span: .futureEvents)
    }
  }
  extension ReminderService {
    package func scheduleReconcile() { scheduleReconcile(after: .milliseconds(1200)) }
    package func commitCompletion(
      _ task: OneTask, done: Bool, restoringDue: Date? = nil,
      restoresDue: Bool = false
    ) throws -> RemindersSync.Remote? {
      try commitCompletion(
        task, done: done, restoringDue: restoringDue, restoresDue: restoresDue, expected: nil)
    }
    package func didPersistCompletion(_ task: OneTask) {
      didPersistCompletion(task, restoredDue: false)
    }
  }
  extension TimerService {
    @discardableResult
    package func start(seconds: Int, label: String? = nil) async -> RunningTimer? {
      await start(seconds: seconds, label: label, byHand: false)
    }
  }
#endif
