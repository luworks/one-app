// Spike eval: on-device model (FoundationModels) vs scripted CaptureParser on a fixed zh/en/mixed set.
// Build and run with Eval/Understanding/run.sh (macOS host, or the iOS simulator with --sim).
import Foundation
import FoundationModels

struct Case: Decodable {
    let lang: String, input: String
    let level: Int?
    let scenario: String?
    let title: String?
    let kind: String
    let day: Int
    let hasDay: Bool
    let hour: Int?, minute: Int?, duration: Int?
}
struct Suite: Decodable { let now: String, timeZone: String, cases: [Case] }

struct Row {
    var kind = false, day = false, hasDay = false, hour = false, minute = false, title = false, titleExact = false, duration = false
    var all: Bool { kind && day && hasDay && hour && minute && title && duration }
}

func run() async {
    let args = CommandLine.arguments
    guard args.count >= 2, let data = FileManager.default.contents(atPath: args[1]) else { print("usage: eval cases.json [trials] [variants: raw,table,A,B]"); return }
    let trials = args.count > 2 ? Int(args[2]) ?? 2 : 2
    let suite = try! JSONDecoder().decode(Suite.self, from: data)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: suite.timeZone)!
    let fmt = DateFormatter()
    fmt.calendar = cal; fmt.timeZone = cal.timeZone; fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let now = fmt.date(from: suite.now)!
    let today = cal.startOfDay(for: now)

    let model = SystemLanguageModel.default
    print("availability: \(model.availability)")
    print("supportsLocale zh_CN: \(model.supportsLocale(Locale(identifier: "zh_CN")))  en_US: \(model.supportsLocale(Locale(identifier: "en_US")))")
    print("Understanding.unavailableReason(zh_CN): \(Understanding.unavailableReason(localeID: "zh_CN") ?? "nil (ready)")")
    guard Understanding.unavailableReason(localeID: "zh_CN") == nil else { print("MODEL NOT USABLE: stopping, no results to report."); return }

    func norm(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace && !"，。,.、".contains($0) } }
    func score(_ c: Case, _ got: Capture) -> Row {
        var r = Row()
        let gotKind = got.ringsAsAlarm ? "alarm" : got.kind.rawValue
        r.kind = gotKind == c.kind
        r.day = (cal.dateComponents([.day], from: today, to: cal.startOfDay(for: got.day)).day ?? -99) == c.day
        r.hasDay = got.hasDay == c.hasDay
        r.hour = got.hour == c.hour
        r.minute = c.hour == nil || got.minute == (c.minute ?? 0)
        r.duration = c.duration == nil || got.durationMinutes == c.duration
        if let t = c.title {
            let a = norm(got.title), b = norm(t)
            r.titleExact = a == b
            r.title = a == b || a.contains(b) || b.contains(a)
        } else { r.title = true; r.titleExact = true }
        return r
    }

    let wanted = Set((args.count > 3 ? args[3] : "raw,table,A,B").split(separator: ",").map(String.init))
    let deviceLocale = Locale.current.identifier
    print("device locale (Locale.current.identifier): \(deviceLocale)")
    func dayOf(_ c: Capture) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: c.day)).day ?? -99 }
    func show(_ c: Capture) -> String {
        "\(c.ringsAsAlarm ? "alarm" : c.kind.rawValue) '\(c.title)' day \(dayOf(c)) hasDay \(c.hasDay) \(c.hour.map(String.init) ?? "nil"):\(c.minute) dur \(c.durationMinutes.map(String.init) ?? "nil")"
    }

    func summarize(_ name: String, _ rows: [(Case, Row)], times: [Double] = []) {
        let n = Double(rows.count)
        func pct(_ f: (Row) -> Bool) -> String { String(format: "%5.1f%%", 100 * Double(rows.filter { f($0.1) }.count) / n) }
        print(String(format: "%-34@ all %@ | kind %@ day %@ hasDay %@ hour %@ min %@ dur %@ title~ %@ titleExact %@",
                     name as NSString, pct { $0.all }, pct { $0.kind }, pct { $0.day }, pct { $0.hasDay }, pct { $0.hour },
                     pct { $0.minute }, pct { $0.duration }, pct { $0.title }, pct { $0.titleExact }))
        if !times.isEmpty {
            let s = times.sorted()
            print(String(format: "    latency s: p50 %.2f  p90 %.2f  max %.2f  mean %.2f", s[s.count / 2], s[Int(Double(s.count - 1) * 0.9)], s.last!, s.reduce(0, +) / Double(s.count)))
        }
    }

    print("\n== \(suite.cases.count) cases, now \(suite.now) \(suite.timeZone), \(trials) trial(s) per model variant")
    let parserRows = suite.cases.map { c in (c, score(c, CaptureParser.parse(c.input, now: now, calendar: cal))) }
    summarize("CaptureParser", parserRows)
    for lang in ["zh", "en", "mixed"] { summarize("  CaptureParser [\(lang)]", parserRows.filter { $0.0.lang == lang }) }
    let levels = Set(suite.cases.compactMap(\.level)).sorted()
    for lv in levels { summarize("  CaptureParser [L\(lv)]", parserRows.filter { $0.0.level == lv }) }
    let scenarios = Array(Set(suite.cases.compactMap(\.scenario))).sorted()
    for sc in scenarios { summarize("  CaptureParser <\(sc.prefix(14))>", parserRows.filter { $0.0.scenario == sc }) }
    // Ceiling for variant A: how often the parser's own day/time/duration/title are right (kind ignored).
    let ceiling = parserRows.filter { var r = $0.1; r.kind = true; return r.all }.count
    print("variant-A ceiling (parser day/hasDay/hour/min/dur/title all right, kind ignored): \(ceiling)/\(suite.cases.count)")
    // Non-kind misses only (kind is the model's job in variant A2).
    for (c, r) in parserRows where !(r.day && r.hasDay && r.hour && r.minute && r.duration && r.title) {
        print("  ✗ \(c.input) → \(show(CaptureParser.parse(c.input, now: now, calendar: cal)))  [expected \(c.kind) day \(c.day) hour \(c.hour.map(String.init) ?? "nil")]")
    }

    /// A variant maps one case to several labelled captures (nil = would fall back) and a debug line.
    struct Variant { let key: String, name: String, run: (Case) async throws -> (outs: [(String, Capture?)], debug: String) }
    let variants: [Variant] = [
        Variant(key: "raw", name: "model raw, no table") { c in
            let a = try await Understanding.extract(c.input, now: now, calendar: cal, localeID: "zh_CN", calendarTable: false)
            let raw = Understanding.capture(from: a, now: now, calendar: cal)
            // Hybrid: the raw model's fields, but the parser's day when it found one.
            var hybrid = raw
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            if hybrid != nil, p.hasDay { hybrid!.day = p.day; hybrid!.hasDay = true }
            return ([("model raw, no table", raw), ("hybrid: raw model + parser day", hybrid)], "\(a)")
        },
        Variant(key: "table", name: "model raw, + calendar table") { c in
            let a = try await Understanding.extract(c.input, now: now, calendar: cal, localeID: "zh_CN", calendarTable: true)
            return ([("model raw, + calendar table", Understanding.capture(from: a, now: now, calendar: cal))], "\(a)")
        },
        Variant(key: "A", name: "A: parser fields + model kind") { c in
            let i = try await Understanding.extractKind(c.input, localeID: deviceLocale)
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ([("A: parser + model kind", Understanding.combine(parser: p, intent: i)),
                     ("A+: also keep parser's event", Understanding.combine(parser: p, intent: i, keepParserEvent: true))],
                    "alarm \(i.alarm) event \(i.event)")
        },
        Variant(key: "A2", name: "A2: parser fields + model kind (one enum)") { c in
            let k = try await Understanding.extractKindOnly(c.input, localeID: deviceLocale)
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ([("A2: parser + model kind enum", Understanding.combine(parser: p, kind: k.kind))], "kind \(k.kind)")
        },
        Variant(key: "A2g", name: "A2g: as wired in the app (A2 instructions + alarm-word guard)") { c in
            let k = try await Understanding.extractKindOnly(c.input, localeID: deviceLocale)
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ([("A2g: parser + kind + alarm guard", Understanding.combine(parser: p, kind: k.kind, text: c.input))], "kind \(k.kind)")
        },
        // Prompt experiments: KIND_PROMPT=<file with {LOCALE}>, KIND_VOTES=<odd number> (majority of that many samples).
        Variant(key: "KP", name: "KP: prompt file + A2g combination") { c in
            let env = ProcessInfo.processInfo.environment
            let file = env["KIND_PROMPT"] ?? ""
            let prompt = try String(contentsOfFile: file, encoding: .utf8).replacingOccurrences(of: "{LOCALE}", with: deviceLocale)
            let votes = max(1, Int(env["KIND_VOTES"] ?? "1") ?? 1)
            var counts: [SimpleKind: Int] = [:]
            for _ in 0..<votes { counts[try await Understanding.extractKindOnly(c.input, localeID: deviceLocale, instructions: prompt).kind, default: 0] += 1 }
            let k = counts.max { $0.value < $1.value }!.key
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ([("KP: parser + kind (prompt file)", Understanding.combine(parser: p, kind: k, text: c.input))], "kind \(k) votes \(counts)")
        },
        Variant(key: "A3", name: "A3: A2 + stricter instructions + alarm-word guard") { c in
            let k = try await Understanding.extractKindOnly(c.input, localeID: deviceLocale, strict: true)
            let p = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ([("A3: parser + strict kind", Understanding.combine(parser: p, kind: k.kind, text: c.input)),
                     ("C0: parser + alarm-word rule (no model)", Understanding.combineRules(parser: p, text: c.input, model: nil)),
                     ("C1: C0 + model event vote", Understanding.combineRules(parser: p, text: c.input, model: k.kind))], "kind \(k.kind)")
        },
        Variant(key: "B", name: "B: model date phrase → parser") { c in
            let a = try await Understanding.extractWhen(c.input, localeID: deviceLocale)
            return ([("B: model phrase → parser", Understanding.combine(when: a, now: now, calendar: cal))], "kind \(a.kind) title '\(a.title)' when '\(a.when ?? "nil")'")
        },
    ]

    for v in variants where wanted.contains(v.key) {
        print("\n== \(v.name)")
        let w0 = Date()
        _ = try? await v.run(suite.cases.first { $0.input == "买牛奶" } ?? suite.cases[0])
        print(String(format: "first request (cold): %.2fs", Date().timeIntervalSince(w0)))
        var rows: [String: [(Case, Row)]] = [:]
        var order: [String] = []
        var times: [Double] = []
        var fallbacks = 0
        var errors: [String: Int] = [:]
        var failures: [String: [String]] = [:]
        for trial in 0..<trials {
            for c in suite.cases {
                let t0 = Date()
                do {
                    let (outs, debug) = try await v.run(c)
                    times.append(Date().timeIntervalSince(t0))
                    for (label, cap) in outs {
                        if !order.contains(label) { order.append(label) }
                        guard let cap else { rows[label, default: []].append((c, Row())); if label == outs[0].0 { fallbacks += 1 }; failures[c.input, default: []].append("t\(trial) [\(label)]: → nil  (\(debug))"); continue }
                        let r = score(c, cap)
                        rows[label, default: []].append((c, r))
                        if !r.all { failures[c.input, default: []].append("t\(trial) [\(label)]: \(show(cap))  (\(debug))") }
                    }
                } catch {
                    times.append(Date().timeIntervalSince(t0))
                    errors[String("\(error)".prefix(90)), default: 0] += 1
                    for label in (order.isEmpty ? [v.name] : order) { rows[label, default: []].append((c, Row())) }
                    failures[c.input, default: []].append("t\(trial): ERROR \(String("\(error)".prefix(90)))")
                }
            }
        }
        for label in order {
            summarize(label, rows[label] ?? [], times: label == order[0] ? times : [])
            if label == order[0] { for lang in ["zh", "en", "mixed"] { summarize("  [\(lang)]", (rows[label] ?? []).filter { $0.0.lang == lang }) } }
            for lv in levels { summarize("  [L\(lv)] \(label.prefix(12))", (rows[label] ?? []).filter { $0.0.level == lv }) }
            for sc in scenarios { summarize("  <\(sc.prefix(14))> \(label.prefix(6))", (rows[label] ?? []).filter { $0.0.scenario == sc }) }
        }
        print("returned nil (would fall back): \(fallbacks);  errors: \(errors.isEmpty ? "none" : "\(errors)")")
        print("Failures (any trial, first label shown per trial plus extras):")
        for c in suite.cases { if let f = failures[c.input] { print("  ✗ \(c.input)\n      " + f.joined(separator: "\n      ")) } }
    }
}

await run()
