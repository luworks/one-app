import Foundation
import FoundationModels

/// "Move / delete / ask" for items that already exist. Spike only; not wired into any view.
/// The model only picks an operation, a target id and a small number. Code works out the new time and decides
/// when to ask instead (several items could match, no item matches, a question). Nothing here writes anything:
/// the result feeds a preview card and the user's Apply.
struct EditItem: Equatable {
    var id: String
    var type: String // "event" | "task"
    var title: String
    var start: Date?
    var minutes: Int
    var attendees: Int
}

@Generable
enum EditOp: String {
    case move, delete, clarify, none
}

@Generable
struct EditPlan {
    var op: EditOp
    @Guide(description: "id of the one item the message names, from the list. Empty if none or unsure")
    var target: String?
    @Guide(description: "Only for 'later by' / 'earlier by' requests: minutes later, negative for earlier. A day is 1440")
    var postponeMinutes: Int?
    @Guide(description: "Hour on a 24-hour clock, only if the message gives a new time of day")
    var targetHour: Int?
    var targetMinute: Int?
    @Guide(description: "Days from today, only if the message names a new day: 0 today, 1 tomorrow. Empty otherwise")
    var dayShift: Int?
}

struct EditDecision: Equatable {
    enum Op: String { case move, delete, clarify, none }
    var op: Op
    var target: String?
    var newStart: Date?
    /// Why code overrode or decided (for logs and tests).
    var reason: String
}

enum Editing {
    // MARK: Model

    static func instructions(items: [EditItem], now: Date, calendar: Calendar) -> String {
        let day = DateFormatter()
        day.calendar = calendar; day.timeZone = calendar.timeZone; day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        let today = calendar.startOfDay(for: now)
        let rows = items.map { i -> String in
            let when: String
            if let s = i.start {
                let d = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: s)).day ?? 0
                let c = calendar.dateComponents([.hour, .minute], from: s)
                when = String(format: "day %d %02d:%02d", d, c.hour ?? 0, c.minute ?? 0)
            } else { when = "unscheduled" }
            return "\(i.id) | \(i.type) | \(i.title) | \(when) | \(i.minutes) | \(i.attendees)"
        }
        return [
            "You edit a planner. Today is \(day.string(from: now)).",
            "Items the person can mean (id | type | title | when | minutes | attendees):",
            rows.joined(separator: "\n"),
            "op: move = reschedule ONE item. delete = remove ONE item. clarify = you cannot tell which item or what time. none = the message is not an edit.",
            "target is the id of the item the message names. Never invent an id.",
            "Fill postponeMinutes for 'later by' or 'earlier by' requests, targetHour/targetMinute when a new time of day is given, dayShift when a new day is named.",
        ].joined(separator: "\n")
    }

    /// One request, one fresh session. Throws on any model error.
    static func plan(_ text: String, items: [EditItem], now: Date, calendar: Calendar) async throws -> EditPlan {
        let session = LanguageModelSession(instructions: instructions(items: items, now: now, calendar: calendar))
        return try await session.respond(to: text, generating: EditPlan.self).content
    }

    // MARK: Code rules (pure)

    /// Does this sentence talk about an existing item (edit) rather than add something new (capture)?
    /// Cancel / delete verbs always do. Move-like verbs only when the message also names an item, "it", or a meeting.
    static func looksLikeEdit(_ text: String, items: [EditItem]) -> Bool {
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has(#"取消|删掉|删除|删了|\bcancel(l?ed)?\b|\bdelete\b|\bremove\b"#) { return true }
        guard has(#"推迟|延后|延期|提前|推到|改到|改成|挪|移到|排到|往后推|\bpostpone|\breschedule|\bmove\b|\bpush\b|\bdelay\b|bring forward"#) else { return false }
        return !matchingItems(text, in: items).isEmpty || usesPronoun(text)
    }

    /// Same test the composer uses to route questions away from capture.
    static func isQuestion(_ text: String) -> Bool {
        text.hasSuffix("?") || text.hasSuffix("？") || ["什么", "怎么", "吗", "多少", "几"].contains { text.contains($0) }
            || ["what", "how", "when", "which", "do ", "is ", "am ", "any"].contains { text.lowercased().hasPrefix($0) }
    }

    private static let englishStopWords: Set<String> = ["with", "the", "and", "for", "to", "my", "of", "in", "on", "at", "a", "an", "is", "it", "or", "by", "be"]

    /// Items whose title words appear in the message: a two-character piece of a Chinese title, or a whole English word.
    /// Generic "meeting / 会议 / 把会…" words match every event with other people.
    static func matchingItems(_ text: String, in items: [EditItem]) -> [EditItem] {
        let lower = text.lowercased()
        let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func titleMatches(_ title: String) -> Bool {
            let t = title.lowercased()
            let cjk = Array(t).filter { $0.unicodeScalars.first.map { $0.value >= 0x4E00 && $0.value <= 0x9FFF } ?? false }
            if cjk.count >= 2 {
                for i in 0..<(cjk.count - 1) where lower.contains(String(cjk[i...(i + 1)])) { return true }
            }
            let tokens = t.split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 && !englishStopWords.contains($0) }
            return tokens.contains { words.contains($0) }
        }
        let specific = items.filter { titleMatches($0.title) }
        if !specific.isEmpty { return specific }
        let meetingWord = lower.range(of: #"meeting|会议|开会|[把将的]会(?=[推改挪提延移取都])"#, options: .regularExpression) != nil
        if meetingWord {
            // With attendee info, meetings are the events other people are on; without it (no calendar access) any event could be it.
            let events = items.filter { $0.type == "event" }
            let withPeople = events.filter { $0.attendees > 0 }
            return withPeople.isEmpty ? events : withPeople
        }
        return []
    }

    static func mentionsEverything(_ text: String) -> Bool {
        text.range(of: #"所有|全部|每一?个|\ball\b|\bevery\b|everything"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func usesPronoun(_ text: String) -> Bool {
        text.range(of: #"\b(it|that|this|them)\b|这个|那个|它"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let numberWords: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10]
    private static let chineseDigits: [Character: Int] = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]

    /// "半小时", "一小时", "两天", "30 minutes", "a day", "half an hour" → minutes. Negative for "提前 / earlier". Nil if no amount.
    /// A day is 1440 minutes. "三天后" (in three days) is not an amount to shift by.
    static func postponeAmount(in text: String) -> Int? {
        let lower = text.lowercased()
        func first(_ pattern: String) -> [String?]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: lower).map { String(lower[$0]) } }
        }
        var minutes: Int?
        if first(#"一个半小时"#) != nil { minutes = 90 }
        else if first(#"半(?:个)?(?:小时|钟头)|half an? hour"#) != nil { minutes = 30 }
        else if let g = first(#"(\d+|[一二两三四五六七八九十])\s*(?:个)?\s*(小时|钟头|分钟|天)(?!后)"#), let u = g[1] {
            let n = g[0].flatMap { Int($0) ?? ($0.count == 1 ? chineseDigits[$0.first!] : nil) }
            minutes = n.map { $0 * (u == "分钟" ? 1 : u == "天" ? 1440 : 60) }
        } else if let g = first(#"\b(\d+|a|an|one|two|three|four|five|six|ten)\s*(hours?|hrs?|minutes?|mins?|days?)\b"#), let u = g[1] {
            let n = g[0].flatMap { Int($0) ?? numberWords[$0] }
            minutes = n.map { $0 * (u.hasPrefix("m") ? 1 : u.hasPrefix("d") ? 1440 : 60) }
        }
        guard let m = minutes else { return nil }
        let earlier = lower.range(of: #"提前|早半|早一|早点|earlier|ahead|bring forward|move up|pull in"#, options: .regularExpression) != nil
        return earlier ? -m : m
    }

    /// New start time. A day or clock time named in the message (read by `CaptureParser`) replaces that part and the rest stays.
    /// Otherwise "later / earlier by N" is arithmetic on the old start: the amount comes from the words (`postponeAmount`) when
    /// `codeAmounts` is on, else from the model's number. The model's day / hour only fill gaps the parser left.
    static func newStart(for item: EditItem, plan: EditPlan, text: String, now: Date, calendar: Calendar, codeAmounts: Bool = true) -> Date? {
        let parsed = CaptureParser.parse(text, now: now, calendar: calendar)
        let absolute = parsed.hasDay || parsed.hour != nil
        if !absolute, let start = item.start {
            let amount = (codeAmounts ? postponeAmount(in: text) : nil) ?? (plan.postponeMinutes == 0 ? nil : plan.postponeMinutes)
            if let m = amount { return start.addingTimeInterval(TimeInterval(m * 60)) }
        }
        guard absolute || plan.dayShift != nil || plan.targetHour != nil else { return nil }
        let today = calendar.startOfDay(for: now)
        var day = item.start.map { calendar.startOfDay(for: $0) } ?? today
        if parsed.hasDay {
            day = parsed.day
        } else if let n = plan.dayShift, (0...365).contains(n), let d = calendar.date(byAdding: .day, value: n, to: today) {
            day = d
        }
        let hour: Int, minute: Int
        if let h = parsed.hour {
            (hour, minute) = (h, parsed.minute)
        } else if let h = plan.targetHour, (0...23).contains(h),
                  text.range(of: #"同一?时间|同一个时间|same time"#, options: [.regularExpression, .caseInsensitive]) == nil {
            (hour, minute) = (h, (0...59).contains(plan.targetMinute ?? 0) ? plan.targetMinute ?? 0 : 0)
        } else if let s = item.start {
            let c = calendar.dateComponents([.hour, .minute], from: s)
            (hour, minute) = (c.hour ?? 9, c.minute ?? 0)
        } else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Model plan + code rules → what the preview card should propose. `plan` nil means the model failed.
    static func decide(text: String, plan: EditPlan?, items: [EditItem], now: Date, calendar: Calendar, codeAmounts: Bool = true) -> EditDecision {
        func ask(_ why: String) -> EditDecision { EditDecision(op: .clarify, target: nil, newStart: nil, reason: why) }
        if isQuestion(text) { return EditDecision(op: .none, target: nil, newStart: nil, reason: "question") }
        guard let plan else { return ask("model unavailable") }
        if plan.op == .none { return EditDecision(op: .none, target: nil, newStart: nil, reason: "model: not an edit") }
        if plan.op == .clarify { return ask("model asked") }
        if mentionsEverything(text) { return ask("several items") }
        let matches = matchingItems(text, in: items)
        if matches.count > 1 { return ask("several items match: " + matches.map(\.id).joined(separator: ",")) }
        let item: EditItem
        if let only = matches.first {
            item = only
        } else if usesPronoun(text) {
            return ask("no item named")
        } else if let id = plan.target, let found = items.first(where: { $0.id == id }) {
            item = found
        } else {
            return ask("no item named")
        }
        switch plan.op {
        case .delete:
            return EditDecision(op: .delete, target: item.id, newStart: nil, reason: "ok")
        case .move:
            guard let start = newStart(for: item, plan: plan, text: text, now: now, calendar: calendar, codeAmounts: codeAmounts) else { return ask("no new time") }
            return EditDecision(op: .move, target: item.id, newStart: start, reason: "ok")
        default:
            return ask("unexpected op")
        }
    }
}
