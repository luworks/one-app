import Foundation

// Pure logic with no SwiftData/SwiftUI, so it can be unit-tested with `swift test` (see ios/Eval).

/// Past AI conversations, grouped like ChatGPT's history: Today, Yesterday, Previous 7 Days, Older.
enum ConversationBucket: Int, CaseIterable, Comparable {
    case today, yesterday, previous7Days, older

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previous7Days: "Previous 7 Days"
        case .older: "Older"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Calendar days decide, not hours: 00:05 today is "Today" and 23:55 yesterday is "Yesterday".
    /// "Previous 7 Days" covers the days from 2 to 7 days ago.
    static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> Self {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ..<1: return .today          // today, or a clock that moved backwards
        case 1: return .yesterday
        case 2...7: return .previous7Days
        default: return .older
        }
    }
}

enum ConversationHistory {
    /// Newest first, split into non-empty buckets in display order. Items with equal dates keep their input order.
    static func group<T>(_ items: [T], date: (T) -> Date, now: Date = .now, calendar: Calendar = .current)
        -> [(bucket: ConversationBucket, items: [T])] {
        let sorted = items.enumerated().sorted { a, b in
            let (da, db) = (date(a.element), date(b.element))
            return da == db ? a.offset < b.offset : da > db
        }.map(\.element)
        var out: [(bucket: ConversationBucket, items: [T])] = []
        for bucket in ConversationBucket.allCases {
            let inBucket = sorted.filter { ConversationBucket.of(date($0), now: now, calendar: calendar) == bucket }
            if !inBucket.isEmpty { out.append((bucket, inBucket)) }
        }
        return out
    }

    /// The time of day for today's conversations, the weekday for the past week, otherwise the date.
    static func timeText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        switch ConversationBucket.of(date, now: now, calendar: calendar) {
        case .today: return date.formatted(date: .omitted, time: .shortened)
        case .yesterday, .previous7Days: return date.formatted(.dateTime.weekday(.abbreviated))
        case .older: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// A conversation is titled by its first user message: whitespace collapsed, capped so one long paste stays a title.
    static func title(from text: String, limit: Int = 80) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > limit else { return flat.isEmpty ? "New chat" : flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
