#if os(iOS)
  import Foundation
  import SwiftData
  import EventKit
  import UserNotifications
  import WidgetKit
  import TodayCore
  import TodayData
  import TodayShared
  import TodayPlatform

  /// Framework boundary shared by the live app and its App Intents, whichever starts first.
  @MainActor
  public enum OneStore {
    public static var container: ModelContainer { session.container }

    @discardableResult
    public static func start() -> ModelContainer { session.container }

    package static let session: PlannerSession = {
      do {
        let evaluation: Bool
        #if DEBUG && targetEnvironment(simulator)
          evaluation = ProcessInfo.processInfo.arguments.contains("-gptEvaluationStore")
        #else
          evaluation = false
        #endif
        let evaluationRoot = URL.applicationSupportDirectory.appending(path: "GPTMediumEvaluation")
        if evaluation {
          try FileManager.default.createDirectory(
            at: evaluationRoot, withIntermediateDirectories: true)
        }
        let defaults =
          evaluation
          ? UserDefaults(suiteName: "com.luworks.today.gpt-medium-evaluation")! : .standard
        let runtime = PlannerRuntime(
          now: { Date.now }, nextID: { UUID() },
          calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
        // Preserve the installed store's module, schema and default configuration identity.
        let container = try ModelContainer(
          for: OneTask.self, OneEvent.self, OneAlarm.self, OneList.self,
          Habit.self, ChatThread.self, LedgerEntry.self, AIGrant.self,
          ShareImportReceipt.self,
          configurations: evaluation
            ? ModelConfiguration(url: evaluationRoot.appending(path: "planner.store"))
            : ModelConfiguration())
        let calendar = CalendarSync(
          defaults: defaults, runtime: runtime, arguments: [], makeStore: { EKEventStore() })
        let reminders = RemindersSync(
          defaults: defaults, runtime: runtime, arguments: [], makeStore: { EKEventStore() })
        let driver = Ringer(defaults: defaults, runtime: runtime)
        let alarms = AlarmCenter(driver: driver)
        let timers = TimerController(
          defaults: defaults, runtime: runtime, driver: driver,
          donate: { TimerIntentSupport.donate(seconds: $0) })
        let store = try ActivityStore.openOrRecover(
          at: evaluation
            ? evaluationRoot.appending(path: "activity.sqlite") : ActivityStore.defaultURL())
        let activity = ActivityCenter(store: store, defaults: defaults, runtime: runtime)
        let ledger = Ledger(activity: activity, reminders: reminders, runtime: runtime)
        let notifications = Reminders(
          center: .current(), alarms: alarms, reminders: reminders,
          ledger: ledger, runtime: runtime)
        let travel = TravelTimes(defaults: defaults, runtime: runtime)
        let sound = SoundPreview()
        let actions = PlannerActions(
          calendar: calendar, reminders: reminders, alarms: alarms,
          ledger: ledger, runtime: runtime, defaults: defaults)
        let widget = WidgetFeed(
          container: container, calendar: calendar, reminders: reminders,
          runtime: runtime, enabled: !evaluation,
          travel: { travel.widgetFields(eventID: $0, start: $1, isAllDay: $2, place: $3, now: $4) },
          save: { $0.save() }, reload: { WidgetCenter.shared.reloadAllTimelines() })
        travel.didUpdateEstimate = { [weak widget] in widget?.rewriteFromStore() }
        reminders.configure(container, ledger: ledger)
        notifications.configure(container)
        widget.registerBackgroundRefresh()
        return PlannerSession(
          container: container, defaults: defaults, runtime: runtime, calendar: calendar,
          reminders: reminders, alarms: alarms, timers: timers, notifications: notifications,
          activity: activity, ledger: ledger, actions: actions, travel: travel,
          soundPreview: sound, widget: widget,
          inbox: FileShareInbox(
            url: evaluation
              ? evaluationRoot.appending(path: "share-inbox.json") : ShareInbox.fileURL)
        ) {
          calendar.dispose()
          reminders.dispose()
          notifications.dispose()
          travel.dispose()
          sound.stop()
          ledger.dispose()
          activity.dispose()
        }
      } catch {
        // Never replace or delete the SwiftData store when opening fails.
        fatalError("Could not open the data store: \(error)")
      }
    }()
  }
#endif
