import Foundation
import WidgetKit

/// Feeds the TodayWidgets extension: writes today's and tomorrow's items (events, reminders with a time, alarms)
/// as a small JSON snapshot into the App Group, then asks WidgetKit to reload. The widget never opens SwiftData.
@MainActor
enum WidgetFeed {
    private static var lastWritten: [WidgetItem]?

    static func update(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date = .now, calendar: Calendar = .current) {
        // UI tests run on a throwaway store; keep them from replacing what the widget shows.
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        let items = items(tasks: tasks, events: events, alarms: alarms, now: now, calendar: calendar)
        guard items != lastWritten else { return }
        guard WidgetSnapshot(generatedAt: now, items: items).save() else { return }
        lastWritten = items
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func items(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], now: Date, calendar: Calendar) -> [WidgetItem] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let end = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        let days = [today, tomorrow]
        var result: [WidgetItem] = []

        // Apple Calendar events, Today's own events and planned tasks, the way the Calendar tab merges them.
        let entries = CalendarEntries.make(in: DateInterval(start: today, end: end), events: events, tasks: tasks, calendar: calendar)
        for day in days {
            for entry in CalendarEntries.on(day, in: entries, calendar: calendar) {
                let span = entry.span(on: day, calendar: calendar)
                result.append(WidgetItem(id: "\(entry.id)#\(Int(day.timeIntervalSince1970))", title: entry.title,
                                         start: span.allDay ? day : span.start, end: entry.isTask || span.allDay ? nil : span.end,
                                         isAllDay: span.allDay, kind: entry.isTask ? .reminder : .event))
            }
        }

        // Reminders with a time on their deadline but no planned time (most Apple Reminders look like this).
        for t in tasks where !t.isDone && t.plannedStart == nil {
            guard let due = t.due, due >= today, due < end,
                  calendar.dateComponents([.hour, .minute], from: due) != DateComponents(hour: 0, minute: 0) else { continue }
            result.append(WidgetItem(id: "d\(t.persistentModelID.hashValue)", title: t.title, start: due, kind: .reminder))
        }

        // Alarms that ring today or tomorrow.
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
}
