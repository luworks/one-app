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
    /// Ring like an alarm (AlarmKit) instead of a quiet notification.
    var ringsAsAlarm: Bool = false

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
        next.ringsAsAlarm = ringsAsAlarm
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
        t.ringsAsAlarm = ringsAsAlarm
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
    var isAllDay: Bool = false
    var ringsAsAlarm: Bool = false
    /// RepeatRule raw value; nil = one-off.
    var repeatRule: String? = nil

    var repeats: RepeatRule? { repeatRule.flatMap(RepeatRule.init(rawValue:)) }
    var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    /// Start dates of this event's occurrences overlapping `interval` (one-off events give 0 or 1).
    func occurrences(in interval: DateInterval) -> [Date] {
        Recurrence.occurrences(start: start, duration: duration, rule: repeats, in: interval)
    }

    func occurs(on day: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return occurrences(in: interval)
    }

    /// Next occurrence starting after `date`, for reminders.
    func nextStart(after date: Date) -> Date? {
        occurrences(in: DateInterval(start: date, duration: 400 * 86400)).first { $0 > date }
    }

    /// Next reminder: before the next upcoming occurrence (all-day events remind at 9:00 that day).
    var reminderDate: Date? {
        guard let offset = reminderOffsetMinutes else { return nil }
        let now = Date.now
        let lead = TimeInterval(offset * 60)
        guard var next = nextStart(after: now.addingTimeInterval(-60)) else { return nil }
        if isAllDay { next = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next }
        return next.addingTimeInterval(-lead)
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
        let t = OneTask(title: title, plannedStart: plannedStart, durationMinutes: durationMinutes ?? 25,
                        due: plannedStart == nil && hasDay ? day : nil)
        t.repeatRule = repeatRule
        return t
    }

    func makeEvent() -> OneEvent {
        let start = plannedStart ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let e = OneEvent(title: title, start: start, durationMinutes: durationMinutes ?? 60)
        e.repeatRule = repeatRule
        return e
    }

    func makeHabit() -> Habit {
        Habit(title: title)
    }

    /// Creates the right model for `kind` in `context`. Only called after the user taps Add.
    func insert(into context: ModelContext) {
        switch kind {
        case .task: context.insert(makeTask())
        case .event: context.insert(makeEvent())
        case .habit: context.insert(makeHabit())
        }
    }
}
