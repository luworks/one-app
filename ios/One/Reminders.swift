import Foundation
import SwiftData
import UserNotifications

/// Local notifications for timed tasks and events, Due-style:
/// a task keeps nagging every few minutes until it's done, and every notification
/// has Done / Snooze / Tomorrow actions. Snoozing only moves the reminder, never the task;
/// stopping a reminder never completes the task (only Done does).
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    static let taskCategory = "ONE_TASK"
    static let eventCategory = "ONE_EVENT"
    enum Action: String { case done = "DONE", snooze10 = "SNOOZE_10", snooze60 = "SNOOZE_60", tomorrow = "TOMORROW" }

    /// iOS keeps at most 64 pending requests per app.
    static let maxPending = 60
    private static let snoozePrefix = "snooze-"

    private let center = UNUserNotificationCenter.current()
    private var container: ModelContainer?

    func configure(_ container: ModelContainer) {
        self.container = container
        center.delegate = self
        let done = UNNotificationAction(identifier: Action.done.rawValue, title: "Done", options: [])
        let s10 = UNNotificationAction(identifier: Action.snooze10.rawValue, title: "Snooze 10 min", options: [])
        let s60 = UNNotificationAction(identifier: Action.snooze60.rawValue, title: "Snooze 1 hour", options: [])
        let tomorrow = UNNotificationAction(identifier: Action.tomorrow.rawValue, title: "Move to tomorrow", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.taskCategory, actions: [done, s10, s60, tomorrow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.eventCategory, actions: [s10], intentIdentifiers: []),
        ])
    }

    // MARK: Permission

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await resync()
        return granted
    }

    // MARK: Scheduling

    /// Rebuilds all pending reminders from the current data. Cheap; call after any change.
    func resync() async {
        guard let context = container?.mainContext else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let now = Date.now
        let horizon = now.addingTimeInterval(14 * 24 * 3600)
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>())) ?? []

        var requests: [(Date, UNNotificationRequest)] = []
        for task in tasks {
            guard let fire = task.reminderDate, fire < horizon else { continue }
            let id = Self.key(task.persistentModelID)
            let when = task.plannedStart.map { DayLabel.withTime($0) } ?? task.due.map { "Due " + DayLabel.withTime($0) } ?? ""
            for (n, f) in ReminderPlan.taskFires(reminder: fire, now: now).enumerated() {
                requests.append((f.date, request(id: "\(id)#\(n)", title: task.title, body: f.isNag ? "Still open · " + when : when,
                                                 category: Self.taskCategory, key: id, at: f.date)))
            }
        }
        for event in events {
            guard let fire = event.reminderDate, fire > now, fire < horizon else { continue }
            let id = Self.key(event.persistentModelID)
            let body = event.start.formatted(date: .omitted, time: .shortened) + " · \(event.durationMinutes) min"
            requests.append((fire, request(id: "\(id)#0", title: event.title, body: body, category: Self.eventCategory, key: id, at: fire)))
        }

        let pending = await center.pendingNotificationRequests()
        let snoozed = pending.filter { $0.identifier.hasPrefix(Self.snoozePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !$0.hasPrefix(Self.snoozePrefix) })
        for (_, r) in requests.sorted(by: { $0.0 < $1.0 }).prefix(max(0, Self.maxPending - snoozed.count)) {
            try? await center.add(r)
        }
        try? await center.setBadgeCount(tasks.filter(\.isOverdue).count)
    }

    private func request(id: String, title: String, body: String, category: String, key: String, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = key
        content.userInfo = ["key": key]
        content.interruptionLevel = .timeSensitive
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    private static func key(_ id: PersistentIdentifier) -> String {
        (try? JSONEncoder().encode(id)).map { $0.base64EncodedString() } ?? UUID().uuidString
    }

    private static func identifier(from key: String) -> PersistentIdentifier? {
        Data(base64Encoded: key).flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }

    // MARK: Notification delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let key = content.userInfo["key"] as? String ?? ""
        let title = content.title
        let body = content.body
        let category = content.categoryIdentifier
        await handle(action: action, key: key, title: title, body: body, category: category)
    }

    private func handle(action: String, key: String, title: String, body: String, category: String) async {
        if let fire = ReminderPlan.snoozed(action, now: .now) {
            let r = request(id: Self.snoozePrefix + UUID().uuidString, title: title, body: body, category: category, key: key, at: fire)
            try? await center.add(r)
            await clearDelivered(key: key)
            return
        }

        guard let context = container?.mainContext, let id = Self.identifier(from: key) else { return }
        guard let task = context.model(for: id) as? OneTask else { return }
        switch Action(rawValue: action) {
        case .done:
            if !task.isDone { TaskActions.toggleDone(task, context: context, toast: nil) }
        case .tomorrow:
            task.moveToTomorrow()
        default:
            return
        }
        try? context.save()
        await clearDelivered(key: key)
        await removeSnoozes(key: key)
        await resync()
    }

    private func clearDelivered(key: String) async {
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered
            .filter { $0.request.content.userInfo["key"] as? String == key }
            .map(\.request.identifier))
    }

    private func removeSnoozes(key: String) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending
            .filter { $0.content.userInfo["key"] as? String == key }
            .map(\.identifier))
    }
}

/// Reminder offset choices shared by the editors and the Alarms list.
enum ReminderOffset {
    static let choices: [(String, Int?)] = [
        ("Off", nil), ("At time", 0), ("5 min before", 5), ("10 min before", 10),
        ("30 min before", 30), ("1 hour before", 60),
    ]

    static func label(_ minutes: Int?) -> String {
        choices.first { $0.1 == minutes }?.0 ?? "\(minutes ?? 0) min before"
    }
}
