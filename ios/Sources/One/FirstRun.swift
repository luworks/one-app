#if os(iOS)
  import TodayCore
  import TodayShared
  import TodayData
  import TodayPlatform
  import Foundation

  /// First-run access to Apple Calendar and Apple Reminders. iOS shows its own permission prompt the first time;
  /// if access was already granted (a reinstall, or another app's grant) Today simply turns the integration on once,
  /// and the user can switch it off in Settings afterwards.
  @MainActor
  package enum FirstRun {

    package static func calendar(
      _ calendar: any CalendarService, defaults: UserDefaults, arguments: [String]
    ) async {
      guard !arguments.contains("-uiTesting") else { return }
      if calendar.hasAccess, !calendar.isOn,
        defaults.object(forKey: "today.firstRun.calendar") == nil
      {
        defaults.set(true, forKey: "today.firstRun.calendar")
        await calendar.setEnabled(true)
      } else {
        await calendar.connectIfFirstRun()
      }
    }

    package static func reminders(
      _ reminders: any ReminderService, defaults: UserDefaults, arguments: [String]
    ) async {
      guard !arguments.contains("-uiTesting") else { return }
      if reminders.hasAccess, !reminders.isConnected,
        defaults.object(forKey: "today.firstRun.reminders") == nil
      {
        defaults.set(true, forKey: "today.firstRun.reminders")
        await reminders.connect()
      } else {
        await reminders.connectIfFirstRun()
      }
    }

    /// Opening the Alarms tab asks for what alarms need: AlarmKit access, then notifications. iOS shows each prompt only
    /// once (and only the user can tap Allow); after a "Don't Allow" nothing is shown and Settings explains how to turn it on.
    package static func alarms(
      _ alarms: any AlarmService, notifications: any NotificationService, arguments: [String]
    ) async {
      guard !arguments.contains("-uiTesting") else { return }
      if alarms.authorization == .notDetermined { await alarms.requestAuthorization() }
      if await notifications.authorizationStatus() == .notDetermined {
        _ = await notifications.requestPermission()
      }
    }
  }
#endif
