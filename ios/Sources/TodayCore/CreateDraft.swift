import Foundation

/// Shared text and independent settings for explicit native creation.
package struct CreateDraft {
  package enum Kind: String, CaseIterable {
    case reminder = "Reminder", calendar = "Calendar", alarm = "Alarm"
  }
  package var kind: Kind = .reminder
  package var title = ""
  package var notes = ""
  package var reminderDate: Date
  package var hasDueDate = false
  package var hasDueTime = false
  package var reminderRepeat: RepeatRule?
  package var listName = ""
  package var flagged = false
  package var reminderSound = ""
  package var reminderSnooze = true
  package var reminderSnoozeMinutes = 9
  package var eventStart: Date
  package var duration = 60
  package var allDay = false
  package var eventRepeat: RepeatRule?
  package var calendarID: String?
  package var eventAlert: Int? = 10
  package var eventLocation = ""
  package var eventURL = ""
  package var eventBusy = true
  package var alarmTime: Date
  package var weekdays: Set<Int> = []
  package var sound = ""
  package var snooze = true
  package var snoozeMinutes = 9
  package init(now: Date) {
    reminderDate = now
    eventStart = now
    alarmTime = now
  }
  /// The title without the date, time and repeat words the parser understood; nil when it understood none.
  package var parsedTitle: String?
  /// The last parsed timing, so a chip tapped afterwards wins until the typed timing changes again.
  package var lastParse: Capture?
  package var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// What is saved as the title: the typed text minus understood timing words. An alarm label may be empty.
  package var savedTitle: String {
    guard let parsedTitle else { return trimmedTitle }
    return kind == .alarm || !parsedTitle.isEmpty ? parsedTitle : trimmedTitle
  }
  package var isValid: Bool {
    (kind == .alarm || !savedTitle.isEmpty)
      && (kind != .reminder || reminderRepeat == nil || hasDueDate)
  }

  /// Fills date, time, duration and repeat from the typed title (CaptureParser), for every kind.
  /// Only a change in the understood timing is applied, so chips tapped after typing are kept.
  package mutating func applyTyped(now: Date, calendar: Calendar) {
    // An alarm's bare hour is a morning hour ("6:30" rings at 06:30), as in an alarm request.
    let typed = kind == .alarm ? "alarm " + title : title
    let capture = CaptureParser.parse(typed, now: now, calendar: calendar)
    var timing = capture
    timing.title = ""
    timing.notes = nil
    let understood = capture.hasDay || capture.hour != nil || capture.repeatRule != nil
    // The parser falls back to the whole line when only timing words were typed.
    let rest =
      capture.title == typed.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : capture.title
    let label = kind == .alarm ? CaptureParser.alarmLabel(rest) : rest
    parsedTitle =
      understood
      ? (kind == .alarm && label == "Alarm" ? "" : label)
        .trimmingCharacters(in: .whitespacesAndNewlines) : nil
    guard understood, timing != lastParse else { return }
    lastParse = timing
    let rule = capture.repeatRule.flatMap(RepeatRule.init(rawValue:))
    if let time = capture.clockTime(calendar: calendar) {
      reminderDate = time
      hasDueDate = true
      hasDueTime = true
      eventStart = time
      allDay = false
      alarmTime = time
    } else if capture.hasDay {
      reminderDate = capture.day
      hasDueDate = true
      hasDueTime = false
      eventStart = capture.day
      allDay = true
    }
    if let minutes = capture.durationMinutes { duration = minutes }
    if let rule {
      reminderRepeat = rule
      hasDueDate = true
      eventRepeat = rule
      weekdays = CreateWeekdays.days(for: rule, date: capture.day, calendar: calendar)
    }
  }
}

/// Serializes the explicit Create action and permits retry only after a failed attempt.
package struct CreateCommitState {
  package private(set) var saving = false
  package private(set) var committed = false
  package init() {}
  package mutating func begin() -> Bool {
    guard !saving, !committed else { return false }
    saving = true
    return true
  }
  package mutating func finish(success: Bool) {
    saving = false
    committed = success
  }
}
