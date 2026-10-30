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
  /// The timing fields typed words can fill, so "Keep as text" can put them back.
  package struct Timing: Equatable {
    var reminderDate: Date, hasDueDate: Bool, hasDueTime: Bool, reminderRepeat: RepeatRule?
    var eventStart: Date, allDay: Bool, duration: Int, eventRepeat: RepeatRule?
    var alarmTime: Date, weekdays: Set<Int>
  }
  package var timing: Timing {
    get {
      Timing(
        reminderDate: reminderDate, hasDueDate: hasDueDate, hasDueTime: hasDueTime,
        reminderRepeat: reminderRepeat, eventStart: eventStart, allDay: allDay,
        duration: duration, eventRepeat: eventRepeat, alarmTime: alarmTime, weekdays: weekdays)
    }
    set {
      reminderDate = newValue.reminderDate
      hasDueDate = newValue.hasDueDate
      hasDueTime = newValue.hasDueTime
      reminderRepeat = newValue.reminderRepeat
      eventStart = newValue.eventStart
      allDay = newValue.allDay
      duration = newValue.duration
      eventRepeat = newValue.eventRepeat
      alarmTime = newValue.alarmTime
      weekdays = newValue.weekdays
    }
  }
  /// The timing before typed words first filled it.
  package var timingBeforeTyped: Timing?
  /// The user chose "Keep as text": the title is saved as typed and no longer parsed until it is cleared.
  package var keepsTypedText = false
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
    if trimmedTitle.isEmpty { keepsTypedText = false }
    guard !keepsTypedText else { return }
    // An alarm's bare hour is a morning hour ("6:30" rings at 06:30), as in an alarm request.
    let typed = kind == .alarm ? "alarm " + title : title
    let capture = CaptureParser.parse(typed, now: now, calendar: calendar)
    var key = capture
    key.title = ""
    key.notes = nil
    let understood = capture.hasDay || capture.hour != nil || capture.repeatRule != nil
    // The parser falls back to the whole line when only timing words were typed.
    let rest =
      capture.title == typed.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : capture.title
    let label = kind == .alarm ? CaptureParser.alarmLabel(rest) : rest
    parsedTitle =
      understood
      ? (kind == .alarm && label == "Alarm" ? "" : label)
        .trimmingCharacters(in: .whitespacesAndNewlines) : nil
    guard understood, key != lastParse else { return }
    lastParse = key
    if timingBeforeTyped == nil { timingBeforeTyped = self.timing }
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

  /// Undo a parse: the typed words stay in the title and the timing returns to what it was before.
  package mutating func keepTypedAsText() {
    if let before = timingBeforeTyped { timing = before }
    timingBeforeTyped = nil
    lastParse = nil
    parsedTitle = nil
    keepsTypedText = true
  }

  /// The parts of `title` the parser understood as timing (to highlight), as UTF-16 ranges.
  package var typedTimingRanges: [NSRange] {
    guard let parsedTitle, !keepsTypedText else { return [] }
    return TypedTiming.ranges(typed: title, kept: parsedTitle)
  }
}

/// Which characters of a typed line the parser consumed: those not in the longest common subsequence
/// with the kept title, matched as early as possible, grouped into runs without edge spaces.
package enum TypedTiming {
  package static func ranges(typed: String, kept: String) -> [NSRange] {
    let a = Array(typed.lowercased().utf16)
    let b = Array(kept.lowercased().utf16)
    guard a.count == typed.utf16.count, !a.isEmpty else { return [] }
    var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
      }
    }
    var consumed = Array(repeating: true, count: a.count)
    var i = 0
    var j = 0
    while i < a.count, j < b.count {
      if a[i] == b[j], dp[i][j] == dp[i + 1][j + 1] + 1 {
        consumed[i] = false
        i += 1
        j += 1
      } else if dp[i + 1][j] >= dp[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    let blank = Set(" ,.;:-–".utf16)
    var result: [NSRange] = []
    var start: Int?
    for k in 0...a.count {
      if k < a.count, consumed[k] {
        if start == nil { start = k }
        continue
      }
      guard let s = start else { continue }
      var lo = s
      var hi = k
      while lo < hi, blank.contains(a[lo]) { lo += 1 }
      while hi > lo, blank.contains(a[hi - 1]) { hi -= 1 }
      if hi > lo { result.append(NSRange(location: lo, length: hi - lo)) }
      start = nil
    }
    return result
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
