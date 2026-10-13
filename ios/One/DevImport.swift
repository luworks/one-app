#if DEBUG
import Foundation
import SwiftData

/// Debug-only: load a private Calendar + Reminders export (schemaVersion 1, see one-app-data/SCHEMA.md)
/// so the app can be developed against real data. Launch with `-importData <path>`; the file never ships
/// with the app and is never committed.
enum DevImport {
    struct Export: Decodable {
        let schemaVersion: Int
        let calendars: [Container]
        let events: [Event]
        let reminderLists: [Container]
        let reminders: [Reminder]
    }

    struct Container: Decodable { let id: String; let title: String }

    struct Alarm: Decodable { let relativeOffsetSec: Double?; let absoluteDate: String? }

    struct Recurrence: Decodable { let frequency: String; let interval: Int? }

    struct Event: Decodable {
        let calendarId: String
        let title: String?
        let start: String
        let end: String
        let isAllDay: Bool
        let alarms: [Alarm]?
    }

    struct DateParts: Decodable {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int?
        let minute: Int?
        let allDay: Bool?
    }

    struct Reminder: Decodable {
        let listId: String
        let title: String?
        let notes: String?
        let isCompleted: Bool
        let completionDate: String?
        let start: DateParts?
        let due: DateParts?
        let recurrence: [Recurrence]?
        let alarms: [Alarm]?
        let created: String?
    }

    /// Path from the `-importData` launch argument, if any.
    static var requestedPath: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-importData"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Replaces all tasks and events with the export. Returns (events, tasks) imported.
    @discardableResult
    static func run(path: String, into context: ModelContext) throws -> (Int, Int) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let export = try JSONDecoder().decode(Export.self, from: data)
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoFrac.date(from: $0) } }
        let cal = Calendar.current

        try context.delete(model: OneTask.self)
        try context.delete(model: OneEvent.self)

        let calendars = Dictionary(export.calendars.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var eventCount = 0
        for e in export.events {
            guard let start = date(e.start), let end = date(e.end) else { continue }
            let minutes = max(e.isAllDay ? 1440 : 5, Int(end.timeIntervalSince(start) / 60))
            let event = OneEvent(title: e.title ?? "Untitled", start: e.isAllDay ? cal.startOfDay(for: start) : start,
                                 durationMinutes: minutes, calendarName: calendars[e.calendarId] ?? "Calendar")
            event.isAllDay = e.isAllDay
            let offset = e.alarms?.compactMap(\.relativeOffsetSec).first
            event.reminderOffsetMinutes = offset.map { e.isAllDay ? 0 : max(0, Int(-$0 / 60)) }
            context.insert(event)
            eventCount += 1
        }

        let lists = Dictionary(export.reminderLists.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        func parts(_ p: DateParts?) -> (Date, Bool)? {
            guard let p else { return nil }
            let timed = p.hour != nil && !(p.allDay ?? false)
            let d = cal.date(from: DateComponents(year: p.year, month: p.month, day: p.day,
                                                  hour: timed ? p.hour : 0, minute: timed ? (p.minute ?? 0) : 0))
            return d.map { ($0, timed) }
        }
        var taskCount = 0
        for r in export.reminders {
            let due = parts(r.due)
            let start = parts(r.start)
            // A timed start is when you plan to do it; the due stays the deadline.
            // Reminders' start date mostly mirrors the due date; use it as a plan only when it's a distinct timed slot.
            let planned = start.flatMap { $0.1 && $0.0 != due?.0 ? $0.0 : nil }
            let task = OneTask(title: r.title ?? "Untitled", note: r.notes ?? "", plannedStart: planned,
                               due: due?.0)
            task.listName = lists[r.listId] ?? ""
            task.isDone = r.isCompleted
            task.doneAt = date(r.completionDate)
            task.createdAt = date(r.created) ?? .now
            task.repeatRule = r.recurrence?.first.flatMap { RepeatRule(rawValue: $0.frequency)?.rawValue }
            let alarm = r.alarms?.first
            task.reminderOffsetMinutes = alarm == nil ? nil : (alarm?.relativeOffsetSec).map { max(0, Int(-$0 / 60)) } ?? 0
            context.insert(task)
            taskCount += 1
        }
        try context.save()
        return (eventCount, taskCount)
    }
}
#endif
