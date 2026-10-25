import Foundation

/// The pure part of the App Intents (Siri, Shortcuts, Spotlight); the intents themselves are in `AppIntents.swift`.
public enum IntentReminder {
  /// What "Add Reminder" saves for `text` (a title, or one sentence like "call Mom tomorrow at 6pm") and an optional
  /// date from Siri or Shortcuts. Always a reminder: never an event or an alarm, even when the sentence reads like one.
  /// A given date wins over one in the sentence; a date at midnight means the day only, and then a time in the
  /// sentence is kept. nil when there's nothing to add.
  public static func capture(
    text: String, date: Date?, now: Date = .now, calendar: Calendar = .current
  ) -> Capture? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var c = CaptureParser.parse(trimmed, now: now, calendar: calendar)
    if c.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { c.title = trimmed }
    c.kind = .task
    c.ringsAsAlarm = false
    c.isAllDay = false
    if let date {
      c.day = calendar.startOfDay(for: date)
      c.hasDay = true
      let time = calendar.dateComponents([.hour, .minute], from: date)
      if time.hour != 0 || time.minute != 0 {
        c.hour = time.hour
        c.minute = time.minute ?? 0
      }
    }
    return c
  }
}

public enum IntentTimer {
  /// Whole minutes Siri can start, the same timer limit as the picker on the Clock tab.
  public static let maxMinutes = TimerDial.maxSeconds / 60

  /// Seconds for a "Start Timer" request, or nil when the minutes are out of range.
  public static func seconds(minutes: Int) -> Int? {
    (1...maxMinutes).contains(minutes) ? minutes * 60 : nil
  }

  /// "1 minute", "25 minutes".
  public static func spoken(minutes: Int) -> String {
    "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
  }

  /// Seconds for a timer asked for in `seconds` (a Duration from Siri, or `TimerPhrase`), or nil when it is out of
  /// range: at least 1 second, at most 23 hours 59 minutes.
  public static func seconds(seconds: Int) -> Int? {
    (1...TimerDial.maxSeconds).contains(seconds) ? seconds : nil
  }

  /// "10 minutes", "1 hour 30 minutes", "45 seconds" (what Siri says back).
  public static func spoken(seconds: Int) -> String {
    func part(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
    let s = max(seconds, 0)
    let h = s / 3600
    let m = (s % 3600) / 60
    let r = s % 60
    let parts = [
      h > 0 ? part(h, "hour") : nil, m > 0 ? part(m, "minute") : nil,
      r > 0 ? part(r, "second") : nil,
    ]
    return parts.compactMap { $0 }.joined(separator: " ")
  }

  /// The label for a timer: trimmed, nil when empty.
  public static func label(_ text: String?) -> String? {
    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return t.isEmpty ? nil : t
  }
}

public enum IntentAlarm {
  /// What "Set Alarm" saves for `text`, the time the way people say it ("7am tomorrow", "weekdays at 6:30",
  /// "in 20 minutes", "明早7点叫我"). The chat's parser reads it, so Siri and the chat make the same alarm; a sentence
  /// with no alarm words is read as if it started with "alarm". A given `label` wins over a name in the sentence.
  /// nil when there is no time of day.
  public static func capture(
    text: String, label: String? = nil, now: Date = .now, calendar: Calendar = .current
  ) -> Capture? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let parsed = CaptureParser.parse(trimmed, now: now, calendar: calendar)
    var c =
      parsed.ringsAsAlarm
      ? parsed : CaptureParser.parse("alarm " + trimmed, now: now, calendar: calendar)
    guard c.hour != nil else { return nil }
    c.kind = .task
    c.isAllDay = false
    c.ringsAsAlarm = true
    if let name = label?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      c.title = name
    }
    return c
  }

  /// What Siri says back: "Alarm set for 7:00 AM tomorrow.", "Wake up set for 6:30 AM, Weekdays."
  public static func confirmation(
    label: String, hour: Int, minute: Int, weekdays: [Int], now: Date,
    calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let parts = AlarmPlan.timeParts(hour: hour, minute: minute, locale: locale)
    let time = [parts.time, parts.suffix].compactMap { $0 }.joined(separator: " ")
    let name = label.trimmingCharacters(in: .whitespaces)
    let head = (name.isEmpty ? AlarmPlan.defaultLabel : name) + " set for " + time
    guard weekdays.isEmpty else {
      return head + ", " + AlarmPlan.repeatValue(weekdays: weekdays, calendar: calendar) + "."
    }
    let fire = AlarmPlan.nextFire(
      hour: hour, minute: minute, weekdays: [], after: now, calendar: calendar)
    let today = fire.map { calendar.isDate($0, inSameDayAs: now) } ?? true
    return head + (today ? " today." : " tomorrow.")
  }
}

extension AlarmPlan {
  private static let localeWeekdays: [Locale.Weekday] = [
    .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
  ]

  /// Calendar weekdays (1 = Sunday … 7 = Saturday) from Siri's repeat rule: daily is every day, weekly is its days.
  /// nil or any other rule rings once.
  @available(macOS 15, iOS 18, *)
  public static func weekdays(from rule: Calendar.RecurrenceRule?) -> [Int] {
    guard let rule else { return [] }
    let days = rule.weekdays.compactMap { day -> Int? in
      guard case .every(let weekday) = day, let i = localeWeekdays.firstIndex(of: weekday) else {
        return nil
      }
      return i + 1
    }
    switch rule.frequency {
    case .daily: return days.isEmpty ? Array(1...7) : Set(days).sorted()
    case .weekly: return Set(days).sorted()
    default: return []
    }
  }

  /// The repeat rule Siri reads for an alarm's weekdays; nil when it rings once.
  @available(macOS 15, iOS 18, *)
  public static func recurrenceRule(weekdays: [Int], calendar: Calendar = .current)
    -> Calendar.RecurrenceRule?
  {
    let days = Set(weekdays).sorted().filter { (1...7).contains($0) }
    guard !days.isEmpty else { return nil }
    if days.count == 7 { return .daily(calendar: calendar) }
    return .weekly(calendar: calendar, weekdays: days.map { .every(localeWeekdays[$0 - 1]) })
  }
}
