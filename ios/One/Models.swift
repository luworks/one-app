import Foundation
import SwiftData

/// A task. Its planned time is flexible and can move; its deadline (`due`) never moves with it.
@Model
final class OneTask {
    var title: String
    var note: String
    var isDone: Bool
    var doneAt: Date?
    /// When you plan to work on it. nil = not scheduled.
    var plannedStart: Date?
    var durationMinutes: Int
    /// Deadline. Moving planned time never changes this.
    var due: Date?
    var createdAt: Date

    init(title: String, note: String = "", plannedStart: Date? = nil, durationMinutes: Int = 25, due: Date? = nil) {
        self.title = title
        self.note = note
        self.isDone = false
        self.doneAt = nil
        self.plannedStart = plannedStart
        self.durationMinutes = durationMinutes
        self.due = due
        self.createdAt = .now
    }

    var isOverdue: Bool {
        guard !isDone, let due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    func toggleDone() {
        isDone.toggle()
        doneAt = isDone ? .now : nil
    }

    func postpone(minutes: Int) {
        guard let start = plannedStart else { return }
        plannedStart = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func moveToTomorrow() {
        let cal = Calendar.current
        if let start = plannedStart {
            plannedStart = cal.date(byAdding: .day, value: 1, to: start)
        } else if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) {
            plannedStart = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}

/// A calendar event. Events stay fixed: nothing in the app moves them.
/// Later this is replaced by the system calendar (EventKit).
@Model
final class OneEvent {
    var title: String
    var start: Date
    var durationMinutes: Int
    var calendarName: String

    init(title: String, start: Date, durationMinutes: Int, calendarName: String = "Local") {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.calendarName = calendarName
    }
}

enum DayLabel {
    static func text(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day())
    }

    /// "Today 15:00", or just "Today" when the time is midnight (a whole-day date).
    static func withTime(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if parts.hour == 0 && parts.minute == 0 { return text(for: date, calendar: calendar) }
        return text(for: date, calendar: calendar) + " " + date.formatted(date: .omitted, time: .shortened)
    }
}
