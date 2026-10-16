import Foundation
import FoundationModels

/// "Move / delete / ask" for items that already exist.
/// The model only picks an operation and a target id. Code decides everything that has to be exact: whether the sentence is an
/// edit at all, which item the words name (and when to ask instead), and the new time. Nothing here writes anything: the result
/// feeds a ChangeCard and the user's Apply.
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
}

struct EditDecision: Equatable {
    enum Op: String { case move, delete, clarify, none }
    var op: Op
    var target: String?
    var newStart: Date?
    /// Why code decided this (for logs and tests).
    var reason: String
}

enum Editing {
    // MARK: Model

    static func instructions(items: [EditItem], now: Date, calendar: Calendar, history: String = "") -> String {
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
        ]
        .appending(history.isEmpty ? [] : ["The conversation so far (\"it\" and \"that one\" mean the item talked about last):", history])
        .joined(separator: "\n")
    }

    /// One request, one fresh session. Throws on any model error.
    static func plan(_ text: String, items: [EditItem], now: Date, calendar: Calendar, history: String = "") async throws -> EditPlan {
        let session = LanguageModelSession(instructions: instructions(items: items, now: now, calendar: calendar, history: history))
        return try await session.respond(to: text, generating: EditPlan.self).content
    }

    // MARK: Is it an edit?

    private static func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Questions are answered, not acted on (same test the composer uses).
    static func isQuestion(_ text: String) -> Bool {
        text.hasSuffix("?") || text.hasSuffix("？") || ["什么", "怎么", "吗", "多少", "几"].contains { text.contains($0) }
            || ["what", "how", "when", "which", "do ", "is ", "am ", "any"].contains { text.lowercased().hasPrefix($0) }
    }

    static func mentionsEverything(_ text: String) -> Bool {
        has(text, #"所有|全部|每一?个|\ball\b|\bevery\b|everything|(?:下午|上午|晚上|今天|明天|这周|本周|周.)的(?:事|会|安排|日程|任务|活动|都)|都(?:推|改|挪|取消|删|延)"#)
    }

    static func usesPronoun(_ text: String) -> Bool {
        has(text, #"\b(it|that|this|them)\b|这个|那个|它"#)
    }

    private static let deleteCue = #"取消|删掉|删除|删了|不要了|不去了|\bcancel(l?ed)?\b|\bdelete\b|\bremove\b"#
    private static let moveCue = #"推迟|延后|延期|顺延|提前|推到|改到|改成|改约|约到|约在|调到|调整|换到|换成|调成|挪|移到|移至|排到|拖到|往后推|改一下|改下|修改|\bpostpone|\breschedule|\bmove\b|\bpush\b|\bdelay\b|\bchange\b|\badjust\b|\bupdate\b|bring forward|安排在|安排到|定在|订在|放到|\binstead\b|can we (?:do|make|have|move)|how about|同一?时间|same time"#

    /// Does this sentence talk about existing items (edit) rather than add something new (capture)?
    /// Cancel / delete verbs always do. Move-like verbs only when the message also names an item, "it", a meeting or "everything".
    static func looksLikeEdit(_ text: String, items: [EditItem]) -> Bool {
        if isQuestion(text) { return false }
        if has(text, deleteCue) { return true }
        guard has(text, moveCue) else { return false }
        return !matchingItems(text, in: items).isEmpty || usesPronoun(text) || mentionsEverything(text)
    }

    /// True when the words alone do not settle which item is meant, so the model's pick is needed.
    static func needsModel(_ text: String, items: [EditItem]) -> Bool {
        looksLikeEdit(text, items: items) && !mentionsEverything(text) && !usesPronoun(text) && matchingItems(text, in: items).isEmpty
    }

    // MARK: Which item?

    /// Words that mean the same thing in both languages. A hit counts as one shared "concept", whatever the language.
    private static let conceptGroups: [[String]] = [
        ["lunch", "午饭", "午餐", "午休"], ["dinner", "晚饭", "晚餐"], ["breakfast", "早饭", "早餐"],
        ["meeting", "会议", "开会"], ["dentist", "牙医", "牙科"], ["doctor", "医生", "门诊", "看病"],
        ["weekly report", "周报"], ["report", "报告"], ["email", "邮件", "mail"], ["milk", "牛奶"], ["standup", "stand-up", "站会"],
        ["review", "评审", "复盘"], ["call", "电话"], ["gym", "健身"], ["interview", "面试"], ["flight", "航班", "机票"],
        ["budget", "预算"], ["1:1", "一对一", "one on one"], ["invoice", "发票"], ["groceries", "买菜"],
    ]

    private static let englishStopWords: Set<String> = ["with", "the", "and", "for", "to", "my", "of", "in", "on", "at", "a", "an", "is", "it",
                                                       "or", "by", "be", "move", "push", "delay", "cancel", "delete", "remove", "up", "back"]

    /// Comparable pieces of a string: concept hits, then the leftover English words and two-character Chinese pieces.
    private static func units(_ raw: String) -> Set<String> {
        var s = raw.lowercased()
        var out = Set<String>()
        for (i, group) in conceptGroups.enumerated() {
            for term in group.sorted(by: { $0.count > $1.count }) where s.contains(term) {
                out.insert("c\(i)")
                s = s.replacingOccurrences(of: term, with: " ")
            }
        }
        if let re = try? NSRegularExpression(pattern: "[a-z0-9]{2,}") {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let r = Range(m.range, in: s), !englishStopWords.contains(String(s[r])) { out.insert("w" + s[r]) }
            }
        }
        let cjk = Array(s).filter { $0.unicodeScalars.first.map { $0.value >= 0x4E00 && $0.value <= 0x9FFF } ?? false }
        if cjk.count >= 2 { for i in 0..<(cjk.count - 1) { out.insert("g" + String(cjk[i...(i + 1)])) } }
        return out
    }

    /// The items the words point at: all items sharing the most pieces with the message. Several = ambiguous.
    /// A generic "meeting / 会议 / 把会…" with no specific hit means any event with other people on it.
    static func matchingItems(_ text: String, in items: [EditItem]) -> [EditItem] {
        let t = units(text)
        let hits = items.map { (item: $0, matched: units($0.title).intersection(t)) }
        let best = hits.map(\.matched.count).max() ?? 0
        if best > 0 {
            let top = hits.filter { $0.matched.count == best }
            // A weaker item that matches on something the best one does not is a second item the message names ("牙医和产品周会").
            let covered = top.reduce(into: Set<String>()) { $0.formUnion($1.matched) }
            let others = hits.filter { $0.matched.count > 0 && $0.matched.count < best && !$0.matched.isSubset(of: covered) }
            return (top + others).map(\.item)
        }
        if has(text, #"meeting|会议|开会|[把将的]会(?=[推改挪提延移取都])"#) {
            // With attendee info, meetings are the events other people are on; without it (no calendar access) any event could be it.
            let events = items.filter { $0.type == "event" }
            let withPeople = events.filter { $0.attendees > 0 }
            return withPeople.isEmpty ? events : withPeople
        }
        return []
    }

    // MARK: New time

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
        } else if let g = first(#"\b(\d+|a|an|one|two|three|four|five|six|ten)[\s-]*(hours?|hrs?|minutes?|mins?|days?)\b"#), let u = g[1] {
            let n = g[0].flatMap { Int($0) ?? numberWords[$0] }
            minutes = n.map { $0 * (u.hasPrefix("m") ? 1 : u.hasPrefix("d") ? 1440 : 60) }
        }
        guard let m = minutes else { return nil }
        let earlier = has(lower, #"提前|早半|早一|早点|earlier|ahead|bring forward|move up|pull in"#)
        return earlier ? -m : m
    }

    /// New start time, from the words only (the model's numbers are not used; they were wrong too often).
    /// A day or clock time named in the message replaces that part of the old start and the rest stays. A bare time that is already
    /// past today is still today (it is an edit, not a new item). Otherwise "later / earlier by N" shifts the old start.
    /// Nil when the message gives no new time.
    static func newStart(for item: EditItem, text: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        // Parse as of midnight so "move it to 8am" is not rolled to tomorrow.
        let parsed = CaptureParser.parse(text, now: today, calendar: calendar)
        let keepsTime = has(text, #"同一?时间|同一个时间|same time"#)
        if parsed.hasDay || (parsed.hour != nil && !keepsTime) {
            var day = item.start.map { calendar.startOfDay(for: $0) } ?? today
            if parsed.hasDay { day = parsed.day }
            let hour: Int, minute: Int
            if let h = parsed.hour, !keepsTime {
                (hour, minute) = (h, parsed.minute)
            } else if let s = item.start {
                let c = calendar.dateComponents([.hour, .minute], from: s)
                (hour, minute) = (c.hour ?? 9, c.minute ?? 0)
            } else {
                return nil
            }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        if let m = postponeAmount(in: text), let start = item.start { return start.addingTimeInterval(TimeInterval(m * 60)) }
        return nil
    }

    // MARK: Decision

    /// Message (+ the model's target when the words name no item) + code rules → what the preview card should propose.
    /// The operation comes from the words too (cancel / delete cue = delete, move cue = move): the model only breaks the tie on which item.
    /// `plan` nil means the model was not asked or failed.
    static func decide(text: String, plan: EditPlan?, items: [EditItem], now: Date, calendar: Calendar, focus: EditItem? = nil) -> EditDecision {
        func ask(_ why: String) -> EditDecision { EditDecision(op: .clarify, target: nil, newStart: nil, reason: why) }
        if !looksLikeEdit(text, items: items) { return EditDecision(op: .none, target: nil, newStart: nil, reason: "not an edit") }
        if mentionsEverything(text) { return ask("several items") }
        let wantsDelete = has(text, deleteCue), wantsMove = has(text, moveCue)
        if wantsDelete && wantsMove { return ask("several items") }
        let matches = matchingItems(text, in: items)
        if matches.count > 1 { return ask("several items match: " + matches.map(\.id).joined(separator: ",")) }
        let item: EditItem
        if let only = matches.first {
            item = only
        } else if usesPronoun(text), let focus, items.contains(where: { $0.id == focus.id }) {
            item = focus   // "move it to 5pm": it = the item the conversation touched last
        } else if usesPronoun(text) {
            return ask("no item named")
        } else if let plan, let id = plan.target, let found = items.first(where: { $0.id == id }) {
            item = found
        } else {
            return ask(plan == nil ? "model unavailable" : "no item named")
        }
        if wantsDelete { return EditDecision(op: .delete, target: item.id, newStart: nil, reason: "ok") }
        guard let start = newStart(for: item, text: text, now: now, calendar: calendar) else {
            return EditDecision(op: .clarify, target: item.id, newStart: nil, reason: "no new time")
        }
        return EditDecision(op: .move, target: item.id, newStart: start, reason: "ok")
    }

    /// The user already chose the item (tapped it, or said "the second one"): only the operation and the new time are left to read.
    static func decide(text: String, chosen item: EditItem, delete: Bool, now: Date, calendar: Calendar) -> EditDecision {
        if delete || (has(text, deleteCue) && !has(text, moveCue)) { return EditDecision(op: .delete, target: item.id, newStart: nil, reason: "ok") }
        guard let start = newStart(for: item, text: text, now: now, calendar: calendar) else {
            return EditDecision(op: .clarify, target: item.id, newStart: nil, reason: "no new time")
        }
        return EditDecision(op: .move, target: item.id, newStart: start, reason: "ok")
    }
}

private extension Array {
    func appending(_ other: [Element]) -> [Element] { self + other }
}
