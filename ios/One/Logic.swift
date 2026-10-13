import Foundation

// Pure logic with no SwiftData/SwiftUI, so it can be unit-tested with `swift test` (see ios/Eval).

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

enum HabitMath {
    static func isDone(_ checkins: [Date], on day: Date, calendar: Calendar = .current) -> Bool {
        checkins.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    /// Check-ins in the week containing `now` (weeks start on Monday).
    static func weekCount(_ checkins: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        var cal = calendar
        cal.firstWeekday = 2
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return Set(checkins.filter { week.contains($0) }.map { cal.startOfDay(for: $0) }).count
    }

    /// Longest run of consecutive checked-in days ever.
    static func bestStreak(_ checkins: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(checkins.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in days {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }

    /// Consecutive checked-in days ending today, or ending yesterday if today isn't checked yet.
    static func streak(_ checkins: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if !isDone(checkins, on: day, calendar: calendar) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while isDone(checkins, on: day, calendar: calendar) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}

/// How a task repeats. Completing a repeating task creates the next one (OmniFocus / Reminders style).
enum RepeatRule: String, CaseIterable, Codable {
    case daily, weekdays, weekly, monthly, yearly

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    /// The next occurrence strictly after `date`, keeping its time of day.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(d) {
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

/// A checklist line inside a task.
struct ChecklistItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

enum Recurrence {
    /// Start dates of an event's occurrences that overlap `interval`.
    static func occurrences(start: Date, duration: TimeInterval, rule: RepeatRule?, in interval: DateInterval,
                            calendar: Calendar = .current, limit: Int = 1000) -> [Date] {
        let length = max(duration, 1)
        func overlaps(_ d: Date) -> Bool { d < interval.end && d.addingTimeInterval(length) > interval.start }
        guard let rule else { return overlaps(start) ? [start] : [] }
        var result: [Date] = []
        var d = start
        var n = 0
        while d < interval.end && n < limit {
            if overlaps(d) { result.append(d) }
            d = rule.next(after: d, calendar: calendar)
            n += 1
        }
        return result
    }
}

enum DurationLabel {
    /// "25 min", "1 h", "1 h 30 min".
    static func text(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

/// When reminders fire (Due-style): at the reminder time, then nags until the task is done.
enum ReminderPlan {
    /// Follow-up nags after the first reminder, in minutes.
    static let nagMinutes = [5, 10, 20]

    /// Fire dates still in the future: (date, isNag).
    static func taskFires(reminder: Date, now: Date) -> [(date: Date, isNag: Bool)] {
        var result: [(Date, Bool)] = []
        if reminder > now { result.append((reminder, false)) }
        for m in nagMinutes {
            let nag = reminder.addingTimeInterval(TimeInterval(m * 60))
            if nag > now { result.append((nag, true)) }
        }
        return result
    }

    /// Snooze presets offered on the notification.
    static let snoozeMinutes = ["SNOOZE_10": 10, "SNOOZE_60": 60]

    static func snoozed(_ action: String, now: Date) -> Date? {
        snoozeMinutes[action].map { now.addingTimeInterval(TimeInterval($0 * 60)) }
    }
}

/// "Plan my day": first-fit flexible tasks into free time between fixed events.
enum DayPlanner {
    struct Item: Equatable {
        let id: Int
        let minutes: Int
    }

    /// Assigns start times in `items` order, skipping anything that doesn't fit before the window ends.
    /// Starts are rounded up to 5 minutes and keep `buffer` minutes after each busy block.
    static func plan(_ items: [Item], busy: [DateInterval], window: DateInterval, buffer: Int = 5,
                     calendar: Calendar = .current) -> [(id: Int, start: Date)] {
        var blocks = busy.filter { $0.end > window.start && $0.start < window.end }.sorted { $0.start < $1.start }
        var result: [(Int, Date)] = []
        for item in items {
            let length = TimeInterval(item.minutes * 60)
            var cursor = roundUp(window.start, calendar: calendar)
            var placed = false
            while cursor.addingTimeInterval(length) <= window.end {
                let slot = DateInterval(start: cursor, duration: length)
                if let clash = blocks.first(where: { $0.intersects(slot) && $0.end > slot.start && $0.start < slot.end }) {
                    cursor = roundUp(clash.end.addingTimeInterval(TimeInterval(buffer * 60)), calendar: calendar)
                } else {
                    result.append((item.id, cursor))
                    blocks.append(slot)
                    blocks.sort { $0.start < $1.start }
                    placed = true
                    break
                }
            }
            _ = placed
        }
        return result
    }

    private static func roundUp(_ date: Date, calendar: Calendar) -> Date {
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let extra = (5 - m % 5) % 5
        if extra == 0 && s == 0 { return date }
        let base = calendar.date(bySetting: .second, value: 0, of: date) ?? date
        return base.addingTimeInterval(TimeInterval((extra == 0 ? 5 : extra) * 60))
    }
}

extension ReminderPlan {
    /// Habit reminders for the next `days` days at hour:minute, skipping days already checked in.
    static func habitFires(checkins: [Date], hour: Int, minute: Int, now: Date, days: Int = 7,
                           calendar: Calendar = .current) -> [Date] {
        (0..<days).compactMap { n in
            guard let day = calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: now)),
                  !HabitMath.isDone(checkins, on: day, calendar: calendar),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { return nil }
            return fire
        }
    }
}

enum ListName {
    /// "01 工作" → "工作". Numbered names keep their order for sorting; the number is noise when shown.
    static func display(_ name: String) -> String {
        guard let r = name.range(of: #"^\d{1,3}[\s._-]+"#, options: .regularExpression) else { return name }
        let rest = name[r.upperBound...]
        return rest.isEmpty ? name : String(rest)
    }
}
