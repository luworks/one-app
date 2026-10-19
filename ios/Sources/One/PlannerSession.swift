#if os(iOS)
import Foundation
import SwiftData
import TodayCore
import TodayData
import TodayShared
import TodayPlatform

/// Retained by composition roots. Features receive individual capabilities, never this assembly.
@MainActor
package final class PlannerSession {
    package let container: ModelContainer
    package let defaults: UserDefaults
    package let runtime: PlannerRuntime
    package let calendar: any CalendarService
    package let reminders: any ReminderService
    package let alarms: any AlarmService
    package let timers: any TimerService
    package let notifications: any NotificationService
    package let activity: ActivityCenter
    package let ledger: Ledger
    package let actions: PlannerActions
    package let travel: any TravelTimeProviding
    package let soundPreview: any SoundPreviewing
    package let widget: WidgetFeed
    package let inbox: any ShareInboxReading
    private let teardown: () -> Void
    private var disposed = false

    package init(container: ModelContainer, defaults: UserDefaults, runtime: PlannerRuntime,
                 calendar: any CalendarService, reminders: any ReminderService, alarms: any AlarmService,
                 timers: any TimerService, notifications: any NotificationService, activity: ActivityCenter,
                 ledger: Ledger, actions: PlannerActions, travel: any TravelTimeProviding,
                 soundPreview: any SoundPreviewing, widget: WidgetFeed, inbox: any ShareInboxReading,
                 teardown: @escaping () -> Void) {
        self.container = container; self.defaults = defaults; self.runtime = runtime
        self.calendar = calendar; self.reminders = reminders; self.alarms = alarms; self.timers = timers
        self.notifications = notifications; self.activity = activity; self.ledger = ledger; self.actions = actions
        self.travel = travel; self.soundPreview = soundPreview; self.widget = widget; self.inbox = inbox
        self.teardown = teardown
    }

    package func dispose() {
        guard !disposed else { return }
        disposed = true
        widget.dispose()
        teardown()
    }
}

@MainActor
package struct FileShareInbox: ShareInboxReading {
    package let url: URL?
    package init(url: URL?) { self.url = url }
    package func read() throws -> [SharedReminder] { try ShareInbox.read(at: url) }
    package func acknowledge(_ ids: Set<UUID>) -> Bool { ShareInbox.acknowledge(ids, at: url) }
}
#endif
