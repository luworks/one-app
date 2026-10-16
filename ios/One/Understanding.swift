import Foundation
import FoundationModels

/// Turns a line of text into a `Capture` preview.
/// `CaptureParser` reads the day, time, length and title. Apple's on-device model (Apple Intelligence) only decides
/// task / event / alarm, because that is what it is good at (round 2-3 of the spike; it was much worse at dates).
/// With no model (device without Apple Intelligence, model not ready) or on any model error, the parser result is used as is.
/// The result only feeds the preview card; nothing is written until the user taps Add.
enum Understander {
    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) async -> Capture {
        let parsed = CaptureParser.parse(text, now: now, calendar: calendar)
        // The first request after launch can take a long time while the model loads: the parser result is used instead.
        guard let kind = await ModelTimeout.run(seconds: 8, { await Understanding.classify(text) }) else { return parsed }
        // "Remind me" is not an alarm: the model's alarm answer only counts when the text asks for one.
        return Understanding.combine(parser: parsed, kind: kind, text: text)
    }

    /// Loads the model ahead of the first request. No-op where the model isn't available.
    static func prewarm() {
        Understanding.prewarm()
    }
}

/// Whichever finishes first: the work, or nil when the time is up (a late result is dropped).
enum ModelTimeout {
    static func run<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            let once = Once<T>(cont)
            let job = Task { once.resume(await work()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(nil)
                job.cancel()
            }
        }
    }

    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<T?, Never>?
        init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }
        func resume(_ value: T?) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: value)
        }
    }
}

/// What the model extracts. Field names are part of the prompt, so they stay short.
/// The model only gives relative numbers (`dayOffset`, `hour`); code turns them into real dates.
@Generable
enum ActionKind: String {
    case addTask, addEvent, addAlarm, other
}

@Generable
struct ParsedAction {
    var kind: ActionKind
    @Guide(description: "Short title in the user's own language, without date or time words")
    var title: String
    @Guide(description: "Days from today: 0 today, 1 tomorrow. Empty if the user gave no day", .range(0...365))
    var dayOffset: Int?
    @Guide(description: "Hour on a 24-hour clock. Empty if the user gave no time", .range(0...23))
    var hour: Int?
    @Guide(.range(0...59))
    var minute: Int?
    @Guide(description: "Length in minutes, only if the user gave a length or a time range")
    var durationMinutes: Int?
}

/// Round 2, variant A: the parser owns day / time / duration / title; the model only classifies.
@Generable
struct KindIntent {
    @Guide(description: "true if the user asks to be woken up or rung at a time: alarm, wake me, 叫我起床, 闹钟")
    var alarm: Bool
    @Guide(description: "true for a meeting, appointment, meal, trip or class; false for a to-do")
    var event: Bool
}

/// Round 2, variant A2 (added after A's two flags over-said "event"): one enum instead of two booleans.
@Generable
struct KindOnly {
    var kind: SimpleKind
}

/// Round 2, variant B: the model copies the date/time words as text; the parser turns them into a date.
@Generable
enum SimpleKind: String {
    case task, event, alarm
}

@Generable
struct WhenAction {
    var kind: SimpleKind
    @Guide(description: "Title in the user's original language, without date or time words")
    var title: String
    @Guide(description: "The date and time words copied exactly from the message, e.g. 下周一上午10点. Empty if none")
    var when: String?
}

enum Understanding {
    /// Why the model path isn't used, or nil when it is ready.
    static func unavailableReason(localeID: String = "zh_CN") -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return "\(model.availability)" }
        guard model.supportsLocale(Locale(identifier: localeID)) || model.supportsLocale(Locale(identifier: "en_US")) else {
            return "locale \(localeID) not supported"
        }
        return nil
    }

    /// Instructions only carry facts and rules. The user's text goes in the prompt, never in here.
    /// `calendarTable` adds the next 14 days with weekday names so "周五" / "下周一" map to a number.
    static func instructions(now: Date, calendar: Calendar, localeID: String, calendarTable: Bool = true) -> String {
        let en = DateFormatter()
        en.calendar = calendar
        en.timeZone = calendar.timeZone
        en.locale = Locale(identifier: "en_US_POSIX")
        en.dateFormat = "EEEE yyyy-MM-dd"
        var lines = [
            "You extract ONE action from the user's message for a planner app.",
            "Today is \(en.string(from: now)), timezone \(calendar.timeZone.identifier).",
            "The person's locale is \(localeID).",
            "kind: addTask = something to do. addEvent = a meeting, appointment, meal or trip at a fixed time. "
                + "addAlarm = the user asks to be woken up or rung at a time. other = not an action.",
            "dayOffset counts days from today. hour is a 24-hour clock: 3pm and 下午3点 are 15.",
            "If no day is given leave dayOffset empty. If no time is given leave hour and minute empty. Never invent them.",
            "Keep the title in the user's original language.",
        ]
        if calendarTable {
            let weekday = DateFormatter()
            weekday.calendar = calendar
            weekday.timeZone = calendar.timeZone
            weekday.locale = Locale(identifier: "en_US_POSIX")
            weekday.dateFormat = "EEE"
            let zh = ["日", "一", "二", "三", "四", "五", "六"]
            let start = calendar.startOfDay(for: now)
            var cal = calendar
            cal.firstWeekday = 2
            let thisMonday = cal.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            lines.append("Calendar (dayOffset, weekday). A bare weekday means its next occurrence; 下周X / next X is in the week starting Monday "
                         + "\(en.string(from: cal.date(byAdding: .day, value: 7, to: thisMonday) ?? start)):")
            for n in 0..<14 {
                guard let d = calendar.date(byAdding: .day, value: n, to: start) else { continue }
                let w = calendar.component(.weekday, from: d) - 1
                lines.append("\(n) = \(weekday.string(from: d)) 周\(zh[w])")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One request, one fresh session (the context window is only 4096 tokens). Throws on any model error.
    static func extract(_ text: String, now: Date, calendar: Calendar, localeID: String,
                        calendarTable: Bool = true) async throws -> ParsedAction {
        let session = LanguageModelSession(
            instructions: instructions(now: now, calendar: calendar, localeID: localeID, calendarTable: calendarTable))
        return try await session.respond(to: text, generating: ParsedAction.self).content
    }

    /// Model output → preview. Pure and testable. Nil means "didn't understand", so the caller falls back.
    static func capture(from action: ParsedAction, now: Date, calendar: Calendar) -> Capture? {
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard action.kind != .other, !title.isEmpty else { return nil }

        let today = calendar.startOfDay(for: now)
        var day = today
        var hasDay = false
        if let n = action.dayOffset, (0...365).contains(n), let d = calendar.date(byAdding: .day, value: n, to: today) {
            day = d
            hasDay = true
        }
        let hour = action.hour.flatMap { (0...23).contains($0) ? $0 : nil }
        let minute = hour == nil ? 0 : action.minute.flatMap { (0...59).contains($0) ? $0 : nil } ?? 0
        // An alarm without a time can't ring; let the scripted parser make a plain task instead.
        if action.kind == .addAlarm, hour == nil { return nil }
        // A time with no day that has already passed today means tomorrow (same rule as CaptureParser).
        if let h = hour, !hasDay,
           let t = calendar.date(bySettingHour: h, minute: minute, second: 0, of: today), t < now,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            day = tomorrow
            hasDay = true
        }

        var capture = Capture(title: title, day: day, hasDay: hasDay, hour: hour, minute: minute)
        switch action.kind {
        case .addTask: capture.kind = .task
        case .addEvent:
            capture.kind = .event
            if let d = action.durationMinutes, (1...1440).contains(d) { capture.durationMinutes = d }
        case .addAlarm:
            capture.kind = .task
            capture.ringsAsAlarm = true
        case .other: return nil
        }
        return capture
    }

    /// Model call plus mapping. Nil on any failure or when the model isn't usable.
    static func capture(for text: String, now: Date, calendar: Calendar,
                        localeID: String = Locale.current.identifier) async -> Capture? {
        guard unavailableReason(localeID: localeID) == nil else { return nil }
        do {
            let action = try await extract(text, now: now, calendar: calendar, localeID: localeID)
            return capture(from: action, now: now, calendar: calendar)
        } catch {
            return nil // guardrail, unsupported language, context size, cancelled…: scripted parser takes over
        }
    }

    // MARK: Round 2 variants

    static func kindInstructions(localeID: String) -> String {
        [
            "You classify ONE message for a planner app.",
            "The person's locale is \(localeID).",
            "Reply with two flags only. Ignore dates and times.",
        ].joined(separator: "\n")
    }

    static func extractKind(_ text: String, localeID: String) async throws -> KindIntent {
        let session = LanguageModelSession(instructions: kindInstructions(localeID: localeID))
        return try await session.respond(to: text, generating: KindIntent.self).content
    }

    static func kindOnlyInstructions(localeID: String, strict: Bool = false) -> String {
        if strict {
            return [
                "You classify ONE message for a planner app.",
                "The person's locale is \(localeID).",
                "task = something to do, including errands and chores even when they have a day or time, and anything that starts with \"remind me\".",
                "event = a meeting, appointment, interview, class, trip, flight, or a meal with other people, at a set time.",
                "alarm = ONLY when the person asks to be woken up or asks for an alarm. \"Remind me\" is a task, not an alarm.",
                "Ignore dates and times.",
            ].joined(separator: "\n")
        }
        // Few-shot prompt chosen on the ladder dev set and checked on a held-out set (Eval/Understanding/prompts/kind-p2.txt).
        return """
        You classify ONE message for a day planner. The person's locale is \(localeID).
        Answer with exactly one kind:
        - event: a meeting (including standup, sync, 1:1, review), appointment, interview, class, show, flight or trip, meeting someone in person, or a meal or outing with other people. It happens at a booked time, with someone else or somewhere else.
        - alarm: ONLY when the person asks to be woken up or asks for an alarm.
        - task: everything else. Things the person does alone (calls, emails, reports, errands, chores, workouts, payments), booking or buying something, and every "remind me" request, even when a day or time is given.
        Ignore dates and times when deciding.
        Examples:
        "周三下午2点和客户开会" -> event
        "明天上午10点牙科复诊" -> event
        "Dinner with Mia on Saturday 7pm" -> event
        "周六下午和老同学见面" -> event
        "Flight to Tokyo Friday 8:15am" -> event
        "Team sync Monday 10am" -> event
        "Brunch with the team on Sunday" -> event
        "Doctor appt Monday 9am" -> event
        "晚上8点给妈妈打电话" -> task
        "Call the bank at 3pm" -> task
        "Walk the dog at 6pm" -> task
        "Pick up the dry cleaning at 5" -> task
        "Book a hotel in Rome for March" -> task
        "提醒我周五交报销单" -> task
        "Remind me to take my pills at 9pm" -> task
        "Pay rent on the 1st" -> task
        "下班后去超市买菜" -> task
        "明早6点半叫我起床" -> alarm
        "Set an alarm for 7am" -> alarm
        """
    }

    static func extractKindOnly(_ text: String, localeID: String, strict: Bool = false, instructions: String? = nil) async throws -> KindOnly {
        let session = LanguageModelSession(instructions: instructions ?? kindOnlyInstructions(localeID: localeID, strict: strict))
        return try await session.respond(to: text, generating: KindOnly.self).content
    }

    /// "Wake me up", "alarm", 闹钟, 起床, 叫醒. An alarm answer from the model without one of these is treated as a task.
    static func asksForAlarm(_ text: String) -> Bool {
        text.range(of: #"wake\s+me|\balarm\b|闹钟|起床|叫醒|叫我"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Variant C: code decides the alarm (alarm words + a time); the parser's event words and the model's event vote are OR-ed.
    /// With no model kind it is the parser plus the alarm rule.
    static func combineRules(parser p: Capture, text: String, model: SimpleKind?) -> Capture {
        var c = p
        if asksForAlarm(text), p.hour != nil {
            c.kind = .task
            c.ringsAsAlarm = true
        } else {
            c.kind = (p.kind == .event || model == .event) ? .event : .task
        }
        return c
    }

    /// Variant A3: A2 with the stricter instructions and the alarm-word guard.
    static func combine(parser p: Capture, kind: SimpleKind, text: String) -> Capture {
        combine(parser: p, kind: kind == .alarm && !asksForAlarm(text) ? .task : kind)
    }

    /// Variant A2 (shipped): same combination as A, from the enum.
    static func combine(parser p: Capture, kind: SimpleKind) -> Capture {
        combine(parser: p, intent: KindIntent(alarm: kind == .alarm, event: kind == .event))
    }

    /// Variant A: the parser's fields plus the model's kind / alarm flag.
    /// `keepParserEvent` also keeps "event" when the parser already said so (time range, meeting words).
    static func combine(parser p: Capture, intent: KindIntent, keepParserEvent: Bool = false) -> Capture {
        var c = p
        c.kind = (intent.event || (keepParserEvent && p.kind == .event)) ? .event : .task
        // An alarm needs a time to ring at.
        if intent.alarm, p.hour != nil {
            c.kind = .task
            c.ringsAsAlarm = true
        }
        return c
    }

    static func whenInstructions(localeID: String) -> String {
        [
            "You extract ONE action from the user's message for a planner app.",
            "The person's locale is \(localeID).",
            "kind: task = something to do. event = a meeting, appointment, meal, trip or class. "
                + "alarm = the user asks to be woken up or rung at a time.",
            "Keep the title in the user's original language. Copy the date and time words exactly; never translate or compute them.",
        ].joined(separator: "\n")
    }

    static func extractWhen(_ text: String, localeID: String) async throws -> WhenAction {
        let session = LanguageModelSession(instructions: whenInstructions(localeID: localeID))
        return try await session.respond(to: text, generating: WhenAction.self).content
    }

    /// Variant B: the model's kind and title; day / time / duration come from running the parser on the model's date words.
    static func combine(when a: WhenAction, now: Date, calendar: Calendar) -> Capture? {
        let title = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let p = CaptureParser.parse(a.when ?? "", now: now, calendar: calendar)
        var c = Capture(title: title, day: p.day, hasDay: p.hasDay, hour: p.hour, minute: p.minute,
                        repeatRule: p.repeatRule, durationMinutes: p.durationMinutes)
        switch a.kind {
        case .task: c.kind = .task
        case .event: c.kind = .event
        case .alarm:
            guard p.hour != nil else { return nil }
            c.kind = .task
            c.ringsAsAlarm = true
        }
        return c
    }

    /// task / event / alarm for one message. Nil when the model isn't usable or errors (guardrail, unsupported language, cancelled…).
    static func classify(_ text: String, localeID: String = Locale.current.identifier) async -> SimpleKind? {
        guard unavailableReason(localeID: localeID) == nil else { return nil }
        return try? await extractKindOnly(text, localeID: localeID).kind
    }

    static func prewarm(localeID: String = Locale.current.identifier) {
        guard unavailableReason(localeID: localeID) == nil else { return }
        LanguageModelSession(instructions: kindOnlyInstructions(localeID: localeID)).prewarm()
    }
}
