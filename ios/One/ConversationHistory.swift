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

    /// Conversations are about getting things done, so they settle by themselves: a chat archives itself after a week
    /// without a new message, or an hour after everything it added is done (reminders completed or deleted, events over,
    /// alarms rung or off). `settled` has one entry per item the chat added. Archived chats stay under "Archived".
    static let autoArchiveIdleDays = 7

    static func shouldAutoArchive(updatedAt: Date, settled: [Bool], now: Date = .now) -> Bool {
        let idle = now.timeIntervalSince(updatedAt)
        if idle >= Double(autoArchiveIdleDays) * 86_400 { return true }
        return !settled.isEmpty && settled.allSatisfy { $0 } && idle >= 3600
    }

    /// A conversation is titled by its first user message: whitespace collapsed, capped so one long paste stays a title.
    static func title(from text: String, limit: Int = 80) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > limit else { return flat.isEmpty ? "New chat" : flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}


/// Value context rebuilt from this chat's stored messages on every send. No global/model session state.
struct ConversationContext: Sendable {
    struct Turn: Sendable { let isUser: Bool; let text: String }
    let turns: [Turn]

    init(_ lines: [(isUser: Bool, text: String)]) {
        var budget = 1600
        var kept: [Turn] = []
        for line in lines.suffix(8).reversed() {
            let text = String(line.text.prefix(min(400, budget)))
            guard !text.isEmpty else { continue }
            kept.append(Turn(isUser: line.isUser, text: text))
            budget -= text.count
            if budget == 0 { break }
        }
        turns = kept.reversed()
    }

    var users: [String] { turns.filter(\.isUser).map(\.text) }
    var prompt: String {
        turns.map { ($0.isUser ? "User: " : "Assistant: ") + $0.text }.joined(separator: "\n")
    }
}

/// Shared capabilities and confirmation contract for fresh, on-device model sessions.
enum SystemPrompt {
    static let planner = """
    You are Today, an on-device planner assistant. Reply in the latest user's language.
    Users may simply chat. Feelings, advice, narratives, quoted/reported requests and questions are not permission to create items.
    An explicit request to remind, add or set an alarm prepares a preview. Use relevant earlier USER turns in this conversation
    when the latest request refers to them; preserve their title, date and time unless the user changes those fields.
    A new independent request replaces the subject; do not carry unrelated old details into it. Assistant text is not user authorization.
    Concrete creation instructions prepare actionable preview cards, not conversational agreement or questions about special plans.
    The object may precede the instruction: 做一次 auto turbotax repo 下周四提醒我 means a one-off reminder next Thursday.
    Recover that USER subject/date after mistaken assistant chat when the user says 就设定 reminder or 你做吧.
    A bare acknowledgment such as 够 is not a creation instruction or approval. Never promise to handle an item without a preview.
    Date-only reminders are valid without a clock time; never invent a time or require one. Next Thursday is not every Thursday.
    Ask a focused question for a genuinely missing alarm time. Never ask again for a time already supplied for this request.
    A direct recurring reminder request is actionable, including 每周日下午5点提醒我丢垃圾.
    Recurring chores and habits are reminders, not calendar meetings or alarms unless explicitly requested.
    Preserve every requested weekday, time, original name and negation. Friday AND Sunday means both days.
    A frequency label alone is insufficient: the preview must retain the actual weekday set.
    Follow-up changes replace only specified fields; adding recurrence keeps the existing subject and time.
    You can propose reminders, fixed events and alarms, and propose edits. Events stay fixed unless explicitly requested.
    Nothing is created or changed until the user taps Add or Apply. Say preview/ready to add, never claim it is already set.
    Do not claim access to other chats, Activity, cloud services, or tools not provided to this request.
    """
}
