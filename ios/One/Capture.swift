import Foundation

/// What the composer understood from a line of text. Shown as a preview card;
/// nothing is created until the user taps 添加.
struct Capture: Equatable {
    enum Kind: String, CaseIterable { case task, event, habit }

    var title: String
    var day: Date
    var hasDay: Bool
    var hour: Int?
    var minute: Int = 0
    /// RepeatRule raw value; nil = one-off.
    var repeatRule: String? = nil
    /// Set when a time range was given ("3-4pm").
    var durationMinutes: Int? = nil
    /// What the line most likely is. The user can switch it on the preview card.
    var kind: Kind = .task

    var plannedStart: Date? {
        guard let hour else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    var summary: String {
        var parts: [String] = []
        switch kind {
        case .habit:
            parts.append(repeatRule.flatMap(RepeatRule.init(rawValue:))?.label ?? "Every day")
        case .event:
            let start = plannedStart ?? day
            parts.append(DayLabel.withTime(start))
            if let d = durationMinutes { parts.append(DurationLabel.text(minutes: d)) }
        case .task:
            if let start = plannedStart { parts.append("Planned " + DayLabel.withTime(start)) }
            else if hasDay { parts.append("Due " + DayLabel.text(for: day)) }
            else { parts.append("No date, goes to your Inbox") }
            if let rule = repeatRule.flatMap(RepeatRule.init(rawValue:)) { parts.append(rule.label) }
        }
        return parts.joined(separator: " · ")
    }
}

enum CaptureParser {
    /// Words that only connect a date or time to the title ("at 3pm", "on Friday", "by Oct 20").
    private static let lead = #"(?:\b(?:at|on|by|due|before|this)\s+)?"#

    private static let weekdayNames: [(String, Int)] = [
        ("sunday", 1), ("sun", 1), ("monday", 2), ("mon", 2), ("tuesday", 3), ("tues", 3), ("tue", 3),
        ("wednesday", 4), ("wed", 4), ("thursday", 5), ("thurs", 5), ("thur", 5), ("thu", 5),
        ("friday", 6), ("fri", 6), ("saturday", 7), ("sat", 7),
    ]
    private static let chineseWeekdays: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Capture {
        var text = " " + raw.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        let today = calendar.startOfDay(for: now)
        var day = today
        var hasDay = false
        var repeatRule: String?

        func setDay(_ d: Date?) {
            guard let d else { return }
            day = calendar.startOfDay(for: d)
            hasDay = true
        }
        func offset(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: today) }

        // Repeat ("every day", "weekly", "每天"…). Weekday first so "every weekday" isn't read as "every week".
        let repeats: [(String, RepeatRule)] = [
            (#"\bevery\s+weekday\b|\bweekdays\b|工作日|每个工作日"#, .weekdays),
            (#"\bevery\s*day\b|\bdaily\b|每天|每日"#, .daily),
            (#"\bevery\s*week\b|\bweekly\b|每周|每星期"#, .weekly),
            (#"\bevery\s*month\b|\bmonthly\b|每月|每个月"#, .monthly),
            (#"\bevery\s*year\b|\byearly\b|\bannually\b|每年"#, .yearly),
        ]
        for (pattern, rule) in repeats where take(pattern, from: &text) != nil {
            repeatRule = rule.rawValue
            break
        }

        // Relative day words.
        let dayWords: [(String, Int)] = [
            (#"\bday\s+after\s+tomorrow\b"#, 2), ("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0), ("今晚", 0),
            (#"\btomorrow\b"#, 1), (#"\btonight\b"#, 0), (#"\btoday\b"#, 0),
        ]
        for (word, n) in dayWords where take(lead + word, from: &text) != nil {
            setDay(offset(n))
            break
        }

        // Weekdays: "next Monday" / 下周一 = next week's; "Friday" / 周五 = the next one after today.
        if !hasDay {
            let english = weekdayNames.map(\.0).joined(separator: "|")
            if let m = take(lead + #"\bnext\s+("# + english + #")\b"#, from: &text) {
                setDay(nextWeek(weekday(m[0]), today: today, calendar: calendar))
            } else if let m = take(#"下(?:周|星期|礼拜)([一二三四五六日天])"#, from: &text) {
                setDay(nextWeek(chinese(m[0]), today: today, calendar: calendar))
            } else if let m = take(lead + #"\b("# + english + #")\b"#, from: &text) {
                setDay(upcoming(weekday(m[0]), today: today, calendar: calendar))
            } else if let m = take(#"(?:这|本)?(?:周|星期|礼拜)([一二三四五六日天])"#, from: &text) {
                setDay(upcoming(chinese(m[0]), today: today, calendar: calendar, allowToday: true))
            }
        }

        // Calendar dates: "Oct 20", "October 20th", "10/20", "10月20日".
        if !hasDay {
            let monthPattern = lead + #"\b("# + months.joined(separator: "|") + #")[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
            if let m = take(monthPattern, from: &text),
               let mi = months.firstIndex(of: String((m[0] ?? "").lowercased().prefix(3))), let d = Int(m[1] ?? "") {
                setDay(date(month: mi + 1, day: d, today: today, calendar: calendar))
            } else if let m = take(#"(\d{1,2})月(\d{1,2})[日号]?"#, from: &text), let mo = Int(m[0] ?? ""), let d = Int(m[1] ?? "") {
                setDay(date(month: mo, day: d, today: today, calendar: calendar))
            } else if let m = take(lead + #"\b(\d{1,2})/(\d{1,2})\b"#, from: &text), let mo = Int(m[0] ?? ""), let d = Int(m[1] ?? "") {
                setDay(date(month: mo, day: d, today: today, calendar: calendar))
            }
        }

        // Times. A range ("3-4pm", "10点到11点") gives a start and a duration.
        var hour: Int?
        var minute = 0
        var duration: Int?
        let rangeEN = lead + #"\b(\d{1,2})(?:[:：](\d{2}))?\s*(am|pm)?\s*(?:-|–|to|~)\s*(\d{1,2})(?:[:：](\d{2}))?\s*(am|pm)\b"#
        let rangeZH = #"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})(?:[:：](\d{2})|点(半)?)?\s*(?:到|至|-|~)\s*(\d{1,2})(?:[:：](\d{2})|点(半)?)"#
        if let m = take(rangeEN, from: &text) {
            let endPeriod = m[5]
            let endH = adjust(Int(m[3] ?? ""), period: endPeriod)
            let endM = Int(m[4] ?? "") ?? 0
            var startH = adjust(Int(m[0] ?? ""), period: m[2] ?? endPeriod)
            // "11-1pm": the start is the morning before a PM end.
            if let s = startH, let e = endH, s > e, m[2] == nil { startH = s - 12 }
            hour = startH
            minute = Int(m[1] ?? "") ?? 0
            if let h = hour, let e = endH { duration = (e * 60 + endM) - (h * 60 + minute) }
        } else if let m = take(rangeZH, from: &text) {
            hour = adjust(Int(m[1] ?? ""), period: m[0])
            minute = m[3] != nil ? 30 : Int(m[2] ?? "") ?? 0
            let endH = adjust(Int(m[4] ?? ""), period: m[0])
            let endM = m[6] != nil ? 30 : Int(m[5] ?? "") ?? 0
            if let h = hour, let e = endH { duration = (e * 60 + endM) - (h * 60 + minute) }
        }
        if let d = duration, d <= 0 { duration = nil }
        if hour != nil {
            // already set by a range
        } else if let m = take(lead + #"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})[:：](\d{2})\s*(am|pm)?\b"#, from: &text) {
            hour = adjust(Int(m[1] ?? ""), period: m[0] ?? m[3])
            minute = Int(m[2] ?? "") ?? 0
        } else if let m = take(lead + #"\b(\d{1,2})\s*(am|pm)\b"#, from: &text) {
            hour = adjust(Int(m[0] ?? ""), period: m[1])
        } else if let m = take(#"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})\s*点\s*(半|(\d{1,2})\s*分?)?"#, from: &text) {
            hour = adjust(Int(m[1] ?? ""), period: m[0])
            minute = m[2] == "半" ? 30 : Int(m[3] ?? "") ?? 0
        } else if take(lead + #"\bnoon\b|中午"#, from: &text) != nil {
            hour = 12
        } else if take(lead + #"\bmidnight\b"#, from: &text) != nil {
            hour = 0
        } else if let m = take(#"\bat\s+(\d{1,2})\b(?![:/])"#, from: &text) {
            hour = adjust(Int(m[0] ?? ""), period: nil)
        }
        if let h = hour, !(0...23).contains(h) || !(0...59).contains(minute) {
            hour = nil
            minute = 0
        }
        // A time with no day: if it has already passed today, it most likely means tomorrow.
        if let h = hour, !hasDay,
           let t = calendar.date(bySettingHour: h, minute: minute, second: 0, of: today), t < now {
            setDay(offset(1))
        }

        // Leftover connectors at either end ("Pay rent on", "at Call").
        var title = text
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,，。.、"))
        let connectors: Set<String> = ["at", "on", "by", "due", "before", "this", "next", "every"]
        var words = title.split(separator: " ").map(String.init)
        while let last = words.last, connectors.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, connectors.contains(first.lowercased()), words.count > 1 { words.removeFirst() }
        title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,，。.、"))

        let finalTitle = title.isEmpty ? raw : title
        return Capture(title: finalTitle, day: day, hasDay: hasDay, hour: hour, minute: minute,
                       repeatRule: repeatRule, durationMinutes: duration,
                       kind: kind(title: finalTitle, hour: hour, duration: duration, repeatRule: repeatRule))
    }

    private static let eventWords = [
        "meeting", "meet ", "appointment", "lunch", "dinner", "breakfast", "brunch", "flight", "interview",
        "party", "class", "会议", "开会", "面试", "午饭", "晚饭", "早饭", "聚餐", "航班", "约会", "上课",
    ]

    /// Habit: repeats daily / on weekdays with no time. Event: a time range, or meeting-like words.
    private static func kind(title: String, hour: Int?, duration: Int?, repeatRule: String?) -> Capture.Kind {
        if hour == nil, repeatRule == RepeatRule.daily.rawValue || repeatRule == RepeatRule.weekdays.rawValue { return .habit }
        if duration != nil { return .event }
        let lower = title.lowercased() + " "
        if eventWords.contains(where: { lower.contains($0) }) { return .event }
        return .task
    }

    // MARK: Helpers

    private static func weekday(_ name: String?) -> Int {
        let n = (name ?? "").lowercased()
        return weekdayNames.first { $0.0 == n }?.1 ?? 2
    }

    private static func chinese(_ s: String?) -> Int {
        s?.first.flatMap { chineseWeekdays[$0] } ?? 2
    }

    /// Next date with that weekday, strictly after today (or today itself when `allowToday`).
    private static func upcoming(_ weekday: Int, today: Date, calendar: Calendar, allowToday: Bool = false) -> Date? {
        let current = calendar.component(.weekday, from: today)
        var diff = (weekday - current + 7) % 7
        if diff == 0 && !allowToday { diff = 7 }
        return calendar.date(byAdding: .day, value: diff, to: today)
    }

    /// That weekday in next week (weeks start on Monday).
    private static func nextWeek(_ weekday: Int, today: Date, calendar: Calendar) -> Date? {
        var cal = calendar
        cal.firstWeekday = 2
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let nextWeek = cal.date(byAdding: .day, value: 7, to: thisWeek) else { return nil }
        let index = (weekday - 2 + 7) % 7 // Monday = 0
        return cal.date(byAdding: .day, value: index, to: nextWeek)
    }

    /// This year's date, or next year's if it has already passed.
    private static func date(month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return d < today ? calendar.date(byAdding: .year, value: 1, to: d) : d
    }

    private static func adjust(_ hour: Int?, period: String?) -> Int? {
        guard var h = hour else { return nil }
        switch period?.lowercased() {
        case "pm"?, "下午"?, "晚上"?: if h < 12 { h += 12 }
        case "中午"?: if h < 11 { h += 12 }
        case "am"?, "上午"?, "早上"?: if h == 12 { h = 0 }
        case nil: if (1...6).contains(h) { h += 12 } // "3点开会" / "at 4" almost always means PM
        default: break
        }
        return h
    }

    /// Finds the first match, removes it from `text`, and returns its capture groups.
    private static func take(_ pattern: String, from text: inout String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(m.range, in: text) else { return nil }
        let groups = (1..<max(m.numberOfRanges, 1)).map { i -> String? in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
        text.replaceSubrange(whole, with: " ")
        return groups
    }
}
