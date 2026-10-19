import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import Foundation

/// First-run access to Apple Calendar and Apple Reminders. iOS shows its own permission prompt the first time;
/// if access was already granted (a reinstall, or another app's grant) Today simply turns the integration on once,
/// and the user can switch it off in Settings afterwards.
@MainActor
enum FirstRun {
    private static var testing: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    private static let defaults = UserDefaults.standard

    static func calendar() async {
        guard !testing else { return }
        if CalendarSync.shared.hasAccess, !CalendarSync.shared.isOn, defaults.object(forKey: "today.firstRun.calendar") == nil {
            defaults.set(true, forKey: "today.firstRun.calendar")
            await CalendarSync.shared.setEnabled(true)
        } else {
            await CalendarSync.shared.connectIfFirstRun()
        }
    }

    static func reminders() async {
        guard !testing else { return }
        if RemindersSync.shared.hasAccess, !RemindersSync.shared.isConnected, defaults.object(forKey: "today.firstRun.reminders") == nil {
            defaults.set(true, forKey: "today.firstRun.reminders")
            await RemindersSync.shared.connect()
        } else {
            await RemindersSync.shared.connectIfFirstRun()
        }
    }

    /// Opening the Alarms tab asks for what alarms need: AlarmKit access, then notifications. iOS shows each prompt only
    /// once (and only the user can tap Allow); after a "Don't Allow" nothing is shown and Settings explains how to turn it on.
    static func alarms() async {
        guard !testing else { return }
        if Ringer.authorization == .notDetermined { await Ringer.requestAuthorization() }
        if await Reminders.shared.authorizationStatus() == .notDetermined { await Reminders.shared.requestPermission() }
    }
}
