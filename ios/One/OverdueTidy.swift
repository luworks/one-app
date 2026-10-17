import Foundation

/// "Tidy overdue": a suggested new date for each overdue reminder, shown as a preview the user changes per row and
/// applies with one tap (Undo after). Nothing here writes anything. Foundation only, so it runs under `swift test`.
///
/// What it changes is the reminder's date (`due`), keeping its time of day, the way you would in Apple Reminders.
/// This is an explicit, per-item choice the user confirms, not work moving its deadline (principle 3).
enum OverdueTidy {
    enum Choice: String, CaseIterable, Identifiable {
        case today = "Today", tomorrow = "Tomorrow", nextWeek = "Next Week", noDate = "No Date", keep = "Keep"
        var id: Self { self }
    }

    struct Item: Equatable {
        let id: Int
        let due: Date
        var flagged = false
        var repeats = false
    }

    /// How many reminders the suggestion puts on today, and on tomorrow; the rest go to next week.
    static let perDay = 3
    /// Older than this (and not flagged or repeating) suggests No Date: still kept, just no longer overdue.
    static let staleDays = 30

    /// Flagged first, then the most recently overdue (likely still relevant). Returns (id, choice) in that order.
    static func suggest(_ items: [Item], now: Date = .now, calendar cal: Calendar = .current) -> [(id: Int, choice: Choice)] {
        let today = cal.startOfDay(for: now)
        let stale = cal.date(byAdding: .day, value: -staleDays, to: today) ?? today
        let ordered = items.sorted { a, b in
            if a.flagged != b.flagged { return a.flagged }
            if a.due != b.due { return a.due > b.due }
            return a.id < b.id
        }
        var placed = 0
        return ordered.map { item in
            if !item.flagged, !item.repeats, item.due < stale { return (item.id, .noDate) }
            defer { placed += 1 }
            switch placed {
            case ..<perDay: return (item.id, .today)
            case ..<(2 * perDay): return (item.id, .tomorrow)
            default: return (item.id, .nextWeek)
            }
        }
    }

    /// The choices a row offers. A repeating reminder needs a date to repeat from, so it has no No Date.
    static func choices(repeats: Bool) -> [Choice] {
        repeats ? Choice.allCases.filter { $0 != .noDate } : Choice.allCases
    }

    /// The new date for a choice, keeping the time of day (a date-only reminder stays date-only).
    /// nil = no date. `keep` returns the old date.
    static func newDue(_ due: Date, _ choice: Choice, now: Date = .now, calendar cal: Calendar = .current) -> Date? {
        switch choice {
        case .today: QuickTime.move(due, to: .today, now: now, calendar: cal)
        case .tomorrow: QuickTime.move(due, to: .tomorrow, now: now, calendar: cal)
        case .nextWeek: QuickTime.move(due, to: .nextWeek, now: now, calendar: cal)
        case .noDate: nil
        case .keep: due
        }
    }

    /// "tidy overdue", "clean up overdue", "整理过期" … A question ("what's overdue?") is not a request.
    static func isRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["tidy overdue", "tidy up overdue", "clean up overdue", "clear overdue", "reschedule overdue", "sort out overdue",
                "整理过期", "处理过期", "清理过期"].contains { t.contains($0) }
    }
}
