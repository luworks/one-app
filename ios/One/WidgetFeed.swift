import BackgroundTasks
import Foundation
import SwiftData
import WidgetKit

/// Feeds the TodayWidgets extension: writes the next few days' items (events, reminders with a time, alarms)
/// as a small JSON snapshot into the App Group, then asks WidgetKit to reload. The widget never opens SwiftData;
/// it reads Apple Calendar itself when it can (see `NextItems.merge`), so the snapshot matters most for Today's own items.
@MainActor
enum WidgetFeed {
    private static var lastWritten: WidgetSnapshot?
    private static var container: ModelContainer?

    /// Background refresh: rewrites the snapshot while the app isn't open (at midnight, and whenever iOS allows).
    nonisolated static let refreshTaskID = "com.luworks.one.widgetRefresh"

    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    static func configure(_ container: ModelContainer) {
        self.container = container
    }

    static func update(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date = .now, calendar: Calendar = .current) {
        // UI tests run on a throwaway store; keep them from replacing what the widget shows.
        guard !isUITesting else { return }
        let items = items(tasks: tasks, events: events, alarms: alarms, now: now, calendar: calendar)
        // Right after launch EventKit is still warming up and system events read as none; writing now would blank them
        // on the widget. The store bumps `CalendarSync.version` when it's ready, which calls this again.
        let sync = CalendarSync.shared
        guard sync.isReady else { return }
        let settings = WidgetSnapshot.CalendarSettings(isOn: sync.isOn, hiddenCalendarIDs: sync.hiddenCalendarIDs.sorted())
        if let last = lastWritten, last.items == items, last.calendar == settings { return }
        let snapshot = WidgetSnapshot(generatedAt: now, items: items, calendar: settings)
        guard snapshot.save() else { return }
        lastWritten = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func items(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date, calendar: Calendar) -> [WidgetItem] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<WidgetSnapshot.days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        guard let end = calendar.date(byAdding: .day, value: WidgetSnapshot.days, to: today) else { return [] }
        var result: [WidgetItem] = []

        // Apple Calendar events, Today's own events and planned tasks, the way the Calendar tab merges them.
        let entries = CalendarEntries.make(in: DateInterval(start: today, end: end), events: events, tasks: tasks, calendar: calendar)
        for entry in entries {
            switch entry.source {
            case .task:
                for day in days where entry.overlaps(day, calendar: calendar) {
                    let span = entry.span(on: day, calendar: calendar)
                    result.append(WidgetItem(id: "\(entry.id)#\(Int(day.timeIntervalSince1970))", title: entry.title,
                                             start: span.allDay ? day : span.start, isAllDay: span.allDay, kind: .reminder))
                }
            case .system(let id):
                result += WidgetItem.eventRows(id: entry.id, title: entry.title, start: entry.start, end: entry.end,
                                               isAllDay: entry.isAllDay, externalID: id, days: days, calendar: calendar)
            case .local(let e):
                result += WidgetItem.eventRows(id: entry.id, title: entry.title, start: entry.start, end: entry.end,
                                               isAllDay: entry.isAllDay, externalID: e.externalID, days: days, calendar: calendar)
            }
        }

        // Reminders with a time on their deadline but no planned time (most Apple Reminders look like this).
        for t in tasks where !t.isDone && t.plannedStart == nil {
            guard let due = t.due, due >= today, due < end,
                  calendar.dateComponents([.hour, .minute], from: due) != DateComponents(hour: 0, minute: 0) else { continue }
            result.append(WidgetItem(id: "d\(t.persistentModelID.hashValue)", title: t.title, start: due, kind: .reminder))
        }

        // Alarms that ring on those days.
        for a in alarms where a.isOn {
            for day in days {
                guard let fire = AlarmPlan.fire(on: day, hour: a.hour, minute: a.minute, weekdays: a.weekdays, now: now, calendar: calendar)
                else { continue }
                let title = a.label.isEmpty ? AlarmPlan.defaultLabel : a.label
                result.append(WidgetItem(id: "a\(a.persistentModelID.hashValue)#\(Int(day.timeIntervalSince1970))", title: title,
                                         start: fire, kind: .alarm))
            }
        }
        return result.sorted(by: NextItems.ordered)
    }

    // MARK: Background refresh

    /// Must run before launch finishes (`application(_:didFinishLaunchingWithOptions:)`).
    nonisolated static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: .main) { task in
            MainActor.assumeIsolated { runBackgroundRefresh(task) }
        }
    }

    /// Asks iOS to wake the app just after midnight (one pending request; each run books the next one).
    static func scheduleBackgroundRefresh(now: Date = .now, calendar: Calendar = .current) {
        guard !isUITesting else { return }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = midnight.addingTimeInterval(60)
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
    }

    private static func runBackgroundRefresh(_ task: BGTask) {
        scheduleBackgroundRefresh()
        var finished = false
        func finish(_ success: Bool) {
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
        let work = Task { @MainActor in
            // Pull Apple Reminders first (does nothing when Reminders sync is off), so new reminders reach the widget too.
            await RemindersSync.shared.reconcile()
            CalendarSync.shared.prepareStore()
            rewriteFromStore()
            finish(true)
        }
        task.expirationHandler = {
            MainActor.assumeIsolated {
                work.cancel()
                finish(false)
            }
        }
    }

    /// Rewrites the snapshot from the data store (no views needed).
    static func rewriteFromStore() {
        guard let context = container?.mainContext else { return }
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>())) ?? []
        let alarms = (try? context.fetch(FetchDescriptor<OneAlarm>())) ?? []
        update(tasks: tasks, events: events, alarms: alarms)
    }
}
