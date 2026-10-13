import Foundation

/// What the composer understood from a line of text. Shown as a preview card;
/// nothing is created until the user taps 添加.
struct Capture: Equatable {
    var title: String
    var day: Date
    var hasDay: Bool
    var hour: Int?
    var minute: Int = 0

    var plannedStart: Date? {
        guard let hour else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    var summary: String {
        if let start = plannedStart { return "计划 " + DayLabel.withTime(start) }
        if hasDay { return "截止 " + DayLabel.text(for: day) }
        return "不安排时间，放进任务列表"
    }

    func makeTask() -> OneTask {
        OneTask(title: title, plannedStart: plannedStart, due: plannedStart == nil && hasDay ? day : nil)
    }
}

enum CaptureParser {
    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Capture {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = calendar.startOfDay(for: now)
        var day = today
        var hasDay = false

        let dayWords: [(String, Int)] = [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0), ("tomorrow", 1), ("today", 0)]
        for (word, offset) in dayWords {
            if let r = text.range(of: word, options: .caseInsensitive) {
                day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                hasDay = true
                text.removeSubrange(r)
                break
            }
        }

        var hour: Int?
        var minute = 0
        if let m = match(#"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})[:：](\d{2})\s*(am|pm)?"#, in: text) {
            hour = Int(m.groups[1] ?? "")
            minute = Int(m.groups[2] ?? "") ?? 0
            hour = adjust(hour, period: m.groups[0] ?? m.groups[3])
            text.removeSubrange(m.range)
        } else if let m = match(#"(\d{1,2})\s*(am|pm)\b"#, in: text) {
            hour = adjust(Int(m.groups[0] ?? ""), period: m.groups[1])
            text.removeSubrange(m.range)
        } else if let m = match(#"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})\s*点\s*(半|(\d{1,2})\s*分?)?"#, in: text) {
            hour = adjust(Int(m.groups[1] ?? ""), period: m.groups[0])
            if m.groups[2] == "半" { minute = 30 } else { minute = Int(m.groups[3] ?? "") ?? 0 }
            text.removeSubrange(m.range)
        }
        if let h = hour, !(0...23).contains(h) || !(0...59).contains(minute) {
            hour = nil
            minute = 0
        }
        // A time with no day word: if it has already passed today, it most likely means tomorrow.
        if let h = hour, !hasDay,
           let t = calendar.date(bySettingHour: h, minute: minute, second: 0, of: today), t < now {
            day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            hasDay = true
        }

        let title = text
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,，。.、"))
        return Capture(title: title.isEmpty ? raw : title, day: day, hasDay: hasDay, hour: hour, minute: minute)
    }

    private static func adjust(_ hour: Int?, period: String?) -> Int? {
        guard var h = hour else { return nil }
        switch period?.lowercased() {
        case "pm", "下午", "晚上": if h < 12 { h += 12 }
        case "中午": if h < 11 { h += 12 }
        case "am", "上午", "早上": if h == 12 { h = 0 }
        case nil: if (1...6).contains(h) { h += 12 } // "3点开会" almost always means 3 PM
        default: break
        }
        return h
    }

    private static func match(_ pattern: String, in text: String) -> (groups: [String?], range: Range<String.Index>)? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(m.range, in: text) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i -> String? in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
        return (groups, whole)
    }
}
