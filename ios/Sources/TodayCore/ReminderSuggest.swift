import Foundation

/// Guesses what you are about to add when you tap +, from your own past reminders (on the device, nothing is sent).
/// A title scores higher the more often you added it, the more recently, and the closer the time and weekday you usually
/// added it are to now. Each guess comes with the time of day you usually gave it. Things already open are not suggested.
public enum ReminderSuggest {
    public struct Past {
        public let title: String
        public let createdAt: Date
        /// When it was set for, if it had a time.
        public let due: Date?
        public let isOpen: Bool

        public init(title: String, createdAt: Date, due: Date? = nil, isOpen: Bool) {
            self.title = title
            self.createdAt = createdAt
            self.due = due
            self.isOpen = isOpen
        }
    }

    public struct Suggestion: Equatable {
        public let title: String
        /// The next time it would usually be set for, nil when it usually had no time.
        public let when: Date?

        public init(title: String, when: Date? = nil) {
            self.title = title
            self.when = when
        }
    }

    public static func suggest(from past: [Past], now: Date = .now, calendar cal: Calendar = .current, limit: Int = 4) -> [Suggestion] {
        let key: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let open = Set(past.filter(\.isOpen).map { key($0.title) })
        let nowHour = Double(cal.component(.hour, from: now)) + Double(cal.component(.minute, from: now)) / 60
        let nowWeekday = cal.component(.weekday, from: now)

        var score: [String: Double] = [:]
        var title: [String: String] = [:]
        var times: [String: [Int]] = [:]   // minutes after midnight of each timed occurrence
        // The most recent 2000 are plenty to learn habits from and keep this instant on large libraries.
        for p in past.sorted(by: { $0.createdAt > $1.createdAt }).prefix(2000) {
            let k = key(p.title)
            guard !k.isEmpty, !open.contains(k) else { continue }
            let ageDays = max(0, now.timeIntervalSince(p.createdAt) / 86_400)
            let recency = exp(-ageDays / 30)                       // a month-old habit counts about a third
            let h = Double(cal.component(.hour, from: p.createdAt)) + Double(cal.component(.minute, from: p.createdAt)) / 60
            let gap = min(abs(h - nowHour), 24 - abs(h - nowHour))
            let timeOfDay = exp(-gap * gap / 8)                    // within ~2 hours of now counts most
            let sameWeekday = cal.component(.weekday, from: p.createdAt) == nowWeekday ? 1.5 : 1
            score[k, default: 0] += recency * (0.3 + timeOfDay) * sameWeekday
            title[k] = title[k] ?? p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let due = p.due {
                let c = cal.dateComponents([.hour, .minute], from: due)
                if c.hour != 0 || c.minute != 0 { times[k, default: []].append((c.hour ?? 0) * 60 + (c.minute ?? 0)) }
            }
        }
        // A one-off is not a habit: suggest only what you added at least twice.
        let counts = Dictionary(past.map { (key($0.title), 1) }, uniquingKeysWith: +)
        return score.filter { (counts[$0.key] ?? 0) >= 2 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { k, _ in Suggestion(title: title[k] ?? k, when: times[k].map { next(atMinutes: median($0), now: now, calendar: cal) }) }
    }

    private static func median(_ xs: [Int]) -> Int { xs.sorted()[xs.count / 2] }

    /// Today at that time, or tomorrow when it has passed.
    private static func next(atMinutes m: Int, now: Date, calendar cal: Calendar) -> Date {
        let today = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: now) ?? now
        return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }
}
