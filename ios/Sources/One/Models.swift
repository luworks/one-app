#if os(iOS)
  import TodayCore
  import TodayShared
  import TodayData
  import TodayPlatform
  import Foundation
  import SwiftData

  /// A task. Its planned time is flexible and can move; its deadline (`due`) never moves with it.
  @Model
  package final class OneTask {
    package var title: String
    package var note: String
    package var isDone: Bool
    package var doneAt: Date?
    /// When you plan to work on it. nil = not scheduled.
    package var plannedStart: Date?
    package var durationMinutes: Int
    /// Deadline. Moving planned time never changes this.
    package var due: Date?
    package var createdAt: Date
    /// Minutes before the planned time (or a timed deadline) to remind. nil = no reminder.
    package var reminderOffsetMinutes: Int? = 0
    /// "" = Inbox.
    package var listName: String = ""
    package var tags: [String] = []
    package var flagged: Bool = false
    /// RepeatRule raw value; nil = one-off.
    package var repeatRule: String? = nil
    package var checklist: [ChecklistItem] = []
    /// Ring like an alarm (AlarmKit) instead of a quiet notification.
    package var ringsAsAlarm: Bool = false
    /// EKReminder.calendarItemIdentifier when this task is synced with Apple Reminders.
    package var externalID: String? = nil

    package init(
      title: String, note: String = "", plannedStart: Date? = nil, durationMinutes: Int = 25,
      due: Date? = nil
    ) {
      self.title = title
      self.note = note
      self.isDone = false
      self.doneAt = nil
      self.plannedStart = plannedStart
      self.durationMinutes = durationMinutes
      self.due = due
      self.createdAt = .now
    }

    package var isOverdue: Bool {
      guard !isDone, let due else { return false }
      return due < Calendar.current.startOfDay(for: .now)
    }

    /// A deadline at a time of day (a date-only deadline is stored at midnight).
    package var dueHasTime: Bool {
      guard let due else { return false }
      return Calendar.current.dateComponents([.hour, .minute], from: due)
        != DateComponents(hour: 0, minute: 0)
    }

    /// When the reminder fires: planned time, else a deadline that has a time of day.
    package var reminderDate: Date? {
      guard let offset = reminderOffsetMinutes else { return nil }
      let base: Date?
      if let plannedStart {
        base = plannedStart
      } else if let due, dueHasTime {
        base = due
      } else {
        base = nil
      }
      return base?.addingTimeInterval(TimeInterval(-offset * 60))
    }

    package func toggleDone() {
      isDone.toggle()
      doneAt = isDone ? .now : nil
    }

    package var repeats: RepeatRule? { repeatRule.flatMap(RepeatRule.init(rawValue:)) }

    /// The next occurrence of a repeating task: same task, dates moved by the rule, checklist reset.
    package func nextOccurrence() -> OneTask? {
      guard let rule = repeats else { return nil }
      let next = OneTask(
        title: title, note: note,
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
    package func copy() -> OneTask {
      let t = OneTask(
        title: title, note: note, plannedStart: plannedStart, durationMinutes: durationMinutes,
        due: due)
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

    package func postpone(minutes: Int) {
      guard let start = plannedStart else { return }
      plannedStart = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Today at the same time of day, or the next full hour when it has no planned time yet.
    package func moveToToday() {
      let cal = Calendar.current
      if let start = plannedStart {
        let t = cal.dateComponents([.hour, .minute], from: start)
        plannedStart = cal.date(
          bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: .now)
      } else {
        let next = cal.date(byAdding: .hour, value: 1, to: .now) ?? .now
        plannedStart = cal.date(bySetting: .minute, value: 0, of: next).map {
          cal.date(bySetting: .second, value: 0, of: $0) ?? $0
        }
      }
    }

    package func moveToTomorrow() {
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
  package final class OneEvent {
    package var note: String = ""
    package var title: String
    package var start: Date
    package var durationMinutes: Int
    package var calendarName: String
    package var reminderOffsetMinutes: Int? = 10
    package var isAllDay: Bool = false
    package var ringsAsAlarm: Bool = false
    /// Identifier of the copy in the system calendar, when calendar sync is on.
    package var externalID: String? = nil
    /// RepeatRule raw value; nil = one-off.
    package var repeatRule: String? = nil

    package var repeats: RepeatRule? { repeatRule.flatMap(RepeatRule.init(rawValue:)) }
    package var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    /// Start dates of this event's occurrences overlapping `interval` (one-off events give 0 or 1).
    package func occurrences(in interval: DateInterval) -> [Date] {
      Recurrence.occurrences(start: start, duration: duration, rule: repeats, in: interval)
    }

    package func occurs(on day: Date, calendar: Calendar = .current) -> [Date] {
      guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
      return occurrences(in: interval)
    }

    /// Next occurrence starting after `date`, for reminders.
    package func nextStart(after date: Date) -> Date? {
      occurrences(in: DateInterval(start: date, duration: 400 * 86400)).first { $0 > date }
    }

    /// Next reminder: before the next upcoming occurrence (all-day events remind at 9:00 that day).
    package var reminderDate: Date? {
      guard let offset = reminderOffsetMinutes else { return nil }
      let now = Date.now
      let lead = TimeInterval(offset * 60)
      guard var next = nextStart(after: now.addingTimeInterval(-60)) else { return nil }
      if isAllDay {
        next = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next
      }
      return next.addingTimeInterval(-lead)
    }

    /// Everything needed to recreate a deleted event (for Undo).
    package func copy() -> OneEvent {
      let e = OneEvent(
        title: title, start: start, durationMinutes: durationMinutes, calendarName: calendarName)
      e.note = note
      e.reminderOffsetMinutes = reminderOffsetMinutes
      e.isAllDay = isAllDay
      e.ringsAsAlarm = ringsAsAlarm
      e.repeatRule = repeatRule
      return e
    }

    package init(title: String, start: Date, durationMinutes: Int, calendarName: String = "Local") {
      self.title = title
      self.start = start
      self.durationMinutes = durationMinutes
      self.calendarName = calendarName
    }
  }

  /// Committed with a Share reminder. Kept after Undo/deletion so an unacknowledged share cannot resurrect it.
  /// Separate from OneTask.externalID, which belongs exclusively to EventKit.
  @Model
  package final class ShareImportReceipt {
    package var sharedID: UUID = UUID()

    package init(sharedID: UUID) {
      self.sharedID = sharedID
    }
  }
#endif
