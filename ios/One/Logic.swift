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
