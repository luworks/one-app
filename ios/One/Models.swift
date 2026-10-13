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
    /// Minutes before the planned time (or a timed deadline) to remind. nil = no reminder.
    var reminderOffsetMinutes: Int? = 0
    /// "" = Inbox.
    var listName: String = ""
    var tags: [String] = []
    var flagged: Bool = false
    /// RepeatRule raw value; nil = one-off.
    var repeatRule: String? = nil
    var checklist: [ChecklistItem] = []

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

    /// When the reminder fires: planned time, else a deadline that has a time of day.
    var reminderDate: Date? {
        guard let offset = reminderOffsetMinutes else { return nil }
        let base: Date?
        if let plannedStart {
            base = plannedStart
        } else if let due, Calendar.current.dateComponents([.hour, .minute], from: due) != DateComponents(hour: 0, minute: 0) {
            base = due
        } else {
            base = nil
        }
        return base?.addingTimeInterval(TimeInterval(-offset * 60))
    }

    func toggleDone() {
        isDone.toggle()
        doneAt = isDone ? .now : nil
    }

    var repeats: RepeatRule? { repeatRule.flatMap(RepeatRule.init(rawValue:)) }

    /// The next occurrence of a repeating task: same task, dates moved by the rule, checklist reset.
    func nextOccurrence() -> OneTask? {
        guard let rule = repeats else { return nil }
        let next = OneTask(title: title, note: note,
                           plannedStart: plannedStart.map { rule.next(after: $0) },
                           durationMinutes: durationMinutes,
                           due: due.map { rule.next(after: $0) }
                               ?? (plannedStart == nil ? rule.next(after: Calendar.current.startOfDay(for: .now)) : nil))
        next.reminderOffsetMinutes = reminderOffsetMinutes
        next.listName = listName
        next.tags = tags
        next.flagged = flagged
        next.repeatRule = repeatRule
        next.checklist = checklist.map { ChecklistItem(title: $0.title) }
        return next
    }

    /// Everything needed to recreate a deleted task (for Undo).
    func copy() -> OneTask {
        let t = OneTask(title: title, note: note, plannedStart: plannedStart, durationMinutes: durationMinutes, due: due)
        t.isDone = isDone
        t.doneAt = doneAt
        t.createdAt = createdAt
        t.reminderOffsetMinutes = reminderOffsetMinutes
        t.listName = listName
        t.tags = tags
        t.flagged = flagged
        t.repeatRule = repeatRule
        t.checklist = checklist
        return t
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
    var reminderOffsetMinutes: Int? = 10

    var reminderDate: Date? {
        reminderOffsetMinutes.map { start.addingTimeInterval(TimeInterval(-$0 * 60)) }
    }

    init(title: String, start: Date, durationMinutes: Int, calendarName: String = "Local") {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.calendarName = calendarName
    }
}

extension Capture {
    func makeTask() -> OneTask {
        OneTask(title: title, plannedStart: plannedStart, due: plannedStart == nil && hasDay ? day : nil)
    }
}
