import Foundation

/// The pure part of the App Intents (Siri, Shortcuts, Spotlight); the intents themselves are in `AppIntents.swift`.
enum IntentReminder {
    /// What "Add Reminder" saves for `text` (a title, or one sentence like "call Mom tomorrow at 6pm") and an optional
    /// date from Siri or Shortcuts. Always a reminder: never an event or an alarm, even when the sentence reads like one.
    /// A given date wins over one in the sentence; a date at midnight means the day only, and then a time in the
    /// sentence is kept. nil when there's nothing to add.
    static func capture(text: String, date: Date?, now: Date = .now, calendar: Calendar = .current) -> Capture? {
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

enum IntentTimer {
    /// Whole minutes Siri can start, the same timer limit as the picker on the Clock tab.
    static let maxMinutes = TimerDial.maxSeconds / 60

    /// Seconds for a "Start Timer" request, or nil when the minutes are out of range.
    static func seconds(minutes: Int) -> Int? {
        (1...maxMinutes).contains(minutes) ? minutes * 60 : nil
    }

    /// "1 minute", "25 minutes".
    static func spoken(minutes: Int) -> String {
        "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    /// Seconds for a timer asked for in `seconds` (a Duration from Siri, or `TimerPhrase`), or nil when it is out of
    /// range: at least 1 second, at most 23 hours 59 minutes.
    static func seconds(seconds: Int) -> Int? {
        (1...TimerDial.maxSeconds).contains(seconds) ? seconds : nil
    }

    /// "10 minutes", "1 hour 30 minutes", "45 seconds" (what Siri says back).
    static func spoken(seconds: Int) -> String {
        func part(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        let s = max(seconds, 0)
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        let parts = [h > 0 ? part(h, "hour") : nil, m > 0 ? part(m, "minute") : nil, r > 0 ? part(r, "second") : nil]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// The label for a timer: trimmed, nil when empty.
    static func label(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}
