import Foundation

/// Reads a spoken or typed length of time for "Start a timer in Today": "ten minutes", "an hour and a half",
/// "half an hour", "1h30", "90 seconds", "十分钟", "半小时", "一个半小时". Foundation only, so it runs under `swift test`.
/// A bare number ("10", "ten") means minutes. nil when there is no length in the text.
enum TimerPhrase {
    static func seconds(from text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return nil }
        let isCJK = t.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let value = isCJK ? chinese(t) : english(t)
        guard let value, value > 0 else { return nil }
        return Int(value.rounded())
    }

    // MARK: English

    private static let ones: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let units: [String: Double] = [
        "second": 1, "seconds": 1, "sec": 1, "secs": 1, "s": 1,
        "minute": 60, "minutes": 60, "min": 60, "mins": 60, "m": 60,
        "hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600, "h": 3600,
    ]

    private static func english(_ input: String) -> Double? {
        // "an hour and a half", "two and a half hours", "one and half hours" → a "plushalf" token after the number or unit.
        var text = input.replacingOccurrences(of: #"(?:\band\s+)?\ba\s+half\b|\band\s+half\b"#, with: " plushalf ",
                                              options: .regularExpression)
        text = text.replacingOccurrences(of: "-", with: " ")
        let tokens = tokenize(text)

        var total = 0.0
        var number: Double?
        var fromArticle = false
        var lastUnit: Double?
        for token in tokens {
            if let n = Double(token) {
                number = n; fromArticle = false
            } else if let n = ones[token] {
                if let current = number, current >= 20, current.truncatingRemainder(dividingBy: 10) == 0, n < 10 {
                    number = current + n
                } else {
                    number = n
                }
                fromArticle = false
            } else if let n = tens[token] {
                number = n; fromArticle = false
            } else if token == "a" || token == "an" {
                if number == nil { number = 1; fromArticle = true }
            } else if token == "half" {
                number = number ?? 0.5
                fromArticle = false
            } else if token == "plushalf" {
                if let current = number {
                    number = current + 0.5
                } else if let lastUnit {
                    total += lastUnit / 2
                    number = nil
                } else {
                    number = 0.5
                }
                fromArticle = false
            } else if token == "quarter" || token == "quarters" {
                number = (fromArticle ? 1 : (number ?? 1)) * 0.25
                fromArticle = false
            } else if let unit = units[token] {
                if let n = number {
                    total += n * unit
                    lastUnit = unit
                    number = nil
                    fromArticle = false
                }
            }
            // Anything else ("set", "timer", "for", "of", "and", a name) is not a length.
        }
        if let n = number, !fromArticle {
            if total == 0 { total = n * 60 }              // "10", "ten": minutes
            else if lastUnit == 3600 { total += n * 60 }  // "1h30": minutes
            else if lastUnit == 60 { total += n }         // "1 min 30": seconds
        }
        return total > 0 ? total : nil
    }

    /// Numbers (digits and a dot) and words (letters); everything else separates.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        enum Kind { case digit, letter }
        var kind: Kind?
        func flush() { if !current.isEmpty { tokens.append(current) }; current = ""; kind = nil }
        for ch in text {
            let next: Kind?
            if ch.isASCII, ch.isNumber || (ch == "." && kind == .digit) { next = .digit }
            else if ch.isASCII, ch.isLetter { next = .letter }
            else { next = nil }
            if next != kind { flush() }
            if let next { kind = next; current.append(ch) }
        }
        flush()
        return tokens
    }

    // MARK: Chinese

    private static func chinese(_ text: String) -> Double? {
        let number = #"[0-9零一二两三四五六七八九十百]+"#
        var total = 0.0
        var found = false
        var rest = text

        // "一个半小时", "两个半钟头": n hours and a half.
        if let re = try? NSRegularExpression(pattern: "(" + number + #")\s*个半\s*(?:小时|钟头)"#) {
            rest = replaceMatches(re, in: rest) { n in
                total += (n * 60 + 30) * 60; found = true
            }
        }
        // "半小时", "半个小时", "半分钟": half of a unit.
        if let re = try? NSRegularExpression(pattern: #"半\s*个?\s*(小时|钟头|分钟|分|秒钟)"#) {
            let ns = rest as NSString
            var out = rest
            for m in re.matches(in: rest, range: NSRange(location: 0, length: ns.length)).reversed() {
                let unit = unitSeconds(ns.substring(with: m.range(at: 1)))
                total += unit / 2; found = true
                out = (out as NSString).replacingCharacters(in: m.range, with: " ")
            }
            rest = out
        }
        // "十分钟", "一小时", "三十秒", "两刻钟", each optionally followed by 半 ("一小时半").
        if let re = try? NSRegularExpression(pattern: "(" + number + #")\s*个?\s*(小时|钟头|分钟|分|秒钟|秒|刻钟)(半)?"#) {
            let ns = rest as NSString
            for m in re.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
                guard let n = zhNumber(ns.substring(with: m.range(at: 1))) else { continue }
                let unit = unitSeconds(ns.substring(with: m.range(at: 2)))
                total += Double(n) * unit
                if m.range(at: 3).location != NSNotFound { total += unit / 2 }
                found = true
            }
        }
        // A bare number ("十", "25") is minutes.
        if !found, let n = zhNumber(text.trimmingCharacters(in: .whitespaces)) {
            total = Double(n) * 60; found = true
        }
        return found && total > 0 ? total : nil
    }

    private static func unitSeconds(_ unit: String) -> Double {
        switch unit {
        case "小时", "钟头": 3600
        case "分钟", "分": 60
        case "刻钟": 900
        default: 1
        }
    }

    /// Runs `body` with the hours of each match of `re` and returns the text with the matches blanked.
    private static func replaceMatches(_ re: NSRegularExpression, in text: String, _ body: (Double) -> Void) -> String {
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let n = zhNumber(ns.substring(with: m.range(at: 1))) { body(Double(n)) }
            out = (out as NSString).replacingCharacters(in: m.range, with: " ")
        }
        return out
    }

    /// 0–999 from digits or Chinese numerals: 十, 十二, 二十, 二十五, 一百, 两.
    static func zhNumber(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var total = 0, current = 0
        var any = false
        for ch in s {
            if let d = digits[ch] { current = d; any = true }
            else if ch == "十" { total += (current == 0 ? 1 : current) * 10; current = 0; any = true }
            else if ch == "百" { total += (current == 0 ? 1 : current) * 100; current = 0; any = true }
            else { return nil }
        }
        return any ? total + current : nil
    }
}
