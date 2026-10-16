// Round 4: Apple FM numbers on shared case files, with machine-readable per-case outputs.
// Usage: round4.sh <understanding-dir> <out-dir> [trials]   (see run-round4.sh)
import Foundation
import FoundationModels

struct Case: Decodable {
    let lang: String, input: String
    let title: String?
    let kind: String
    let day: Int
    let hasDay: Bool
    let hour: Int?, minute: Int?, duration: Int?
}
struct Suite: Decodable { let now: String, timeZone: String, cases: [Case] }

struct EditItem: Decodable { let id: String }
struct EditCase: Decodable { let lang: String, input: String, op: String, target: String?, start: String? }
struct EditSuite: Decodable { let now: String, timeZone: String, items: [EditItem], cases: [EditCase] }

@Generable
enum EditOp: String { case move, delete, clarify, none }

@Generable
struct EditIntent {
    var op: EditOp
    var target: String?
    var dayOffset: Int?
    var hour: Int?
    var minute: Int?
}

struct Row {
    var kind = false, day = false, hasDay = false, hour = false, minute = false, title = false, duration = false
    var all: Bool { kind && day && hasDay && hour && minute && title && duration }
}

func jsonOut(_ obj: Any, to path: String) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}
func nul(_ v: Any?) -> Any { v ?? NSNull() }

func makeCal(_ tz: String, _ nowStr: String) -> (Calendar, Date) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tz)!
    let f = DateFormatter()
    f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return (cal, f.date(from: nowStr)!)
}

func run() async {
    let args = CommandLine.arguments
    guard args.count >= 3 else { print("usage: round4 <understanding-dir> <out-dir> [trials] [mine-dir]"); return }
    let theirs = args[1], out = args[2]
    let trials = args.count > 3 ? Int(args[3]) ?? 5 : 5
    let mine = args.count > 4 ? args[4] : "."
    let deviceLocale = Locale.current.identifier
    func load<T: Decodable>(_ t: T.Type, _ path: String) -> T { try! JSONDecoder().decode(T.self, from: FileManager.default.contents(atPath: path)!) }

    // MARK: 1. parser outputs
    func dayOffset(_ cal: Calendar, _ today: Date, _ d: Date) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? -99 }
    func parserJSON(_ path: String, _ name: String) {
        let s = load(Suite.self, path)
        let (cal, now) = makeCal(s.timeZone, s.now)
        let today = cal.startOfDay(for: now)
        let arr: [[String: Any]] = s.cases.map { c in
            let g = CaptureParser.parse(c.input, now: now, calendar: cal)
            return ["input": c.input, "kind": g.ringsAsAlarm ? "alarm" : g.kind.rawValue, "day": dayOffset(cal, today, g.day),
                    "hasDay": g.hasDay, "hour": nul(g.hour), "minute": g.minute, "duration": nul(g.durationMinutes),
                    "title": g.title, "repeat": nul(g.repeatRule)]
        }
        jsonOut(arr, to: "\(out)/parser-outputs-\(name).json")
    }
    parserJSON("\(mine)/Eval/Understanding/understanding-cases.json", "r1")
    parserJSON("\(mine)/Eval/Understanding/understanding-cases-r3.json", "r3")
    parserJSON("\(theirs)/understanding-cases-r4.json", "r4")

    let model = SystemLanguageModel.default
    print("availability: \(model.availability); zh_CN \(model.supportsLocale(Locale(identifier: "zh_CN"))); device locale \(deviceLocale)")
    guard case .available = model.availability else { print("MODEL NOT AVAILABLE"); return }

    // MARK: 2. capture r4
    let suite = load(Suite.self, "\(theirs)/understanding-cases-r4.json")
    let (cal, now) = makeCal(suite.timeZone, suite.now)
    let today = cal.startOfDay(for: now)

    func norm(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace && !"，。,.、".contains($0) } }
    func score(_ c: Case, _ got: Capture) -> Row {
        var r = Row()
        r.kind = (got.ringsAsAlarm ? "alarm" : got.kind.rawValue) == c.kind
        r.day = dayOffset(cal, today, got.day) == c.day
        r.hasDay = got.hasDay == c.hasDay
        r.hour = got.hour == c.hour
        r.minute = c.hour == nil || got.minute == (c.minute ?? 0)
        r.duration = c.duration == nil || got.durationMinutes == c.duration
        if let t = c.title { let a = norm(got.title), b = norm(t); r.title = a == b || a.contains(b) || b.contains(a) } else { r.title = true }
        return r
    }
    var summaryRows: [String: [(Case, Row)]] = [:]
    var summaryOrder: [String] = []
    func record(_ label: String, _ c: Case, _ cap: Capture?) {
        if !summaryOrder.contains(label) { summaryOrder.append(label) }
        summaryRows[label, default: []].append((c, cap.map { score(c, $0) } ?? Row()))
    }
    for c in suite.cases { record("CaptureParser", c, CaptureParser.parse(c.input, now: now, calendar: cal)) }

    var entries: [[String: Any]] = []
    func timed<T>(_ f: () async throws -> T) async -> (T?, String?, Double) {
        let t0 = Date()
        do { let v = try await f(); return (v, nil, Date().timeIntervalSince(t0)) }
        catch { return (nil, String("\(error)".prefix(160)), Date().timeIntervalSince(t0)) }
    }

    // Tagging model (content-tagging use case) with the A2 prompt and schema.
    let tagModel = SystemLanguageModel(useCase: .contentTagging)
    print("contentTagging availability: \(tagModel.availability)")
    func tagKind(_ text: String) async throws -> KindOnly {
        let s = LanguageModelSession(model: tagModel, instructions: Understanding.kindOnlyInstructions(localeID: deviceLocale))
        return try await s.respond(to: text, generating: KindOnly.self).content
    }
    var taggingWorks = true

    // Warm-up (not recorded).
    _ = try? await Understanding.extractKindOnly("买牛奶", localeID: deviceLocale)
    _ = try? await Understanding.extract("买牛奶", now: now, calendar: cal, localeID: deviceLocale, calendarTable: true)

    for trial in 1...trials {
        for c in suite.cases {
            let parsed = CaptureParser.parse(c.input, now: now, calendar: cal)

            // full: ParsedAction raw extraction (14-day calendar table, device locale).
            let (a, ea, sa) = await timed { try await Understanding.extract(c.input, now: now, calendar: cal, localeID: deviceLocale, calendarTable: true) }
            entries.append(["input": c.input, "trial": trial, "mode": "full",
                            "out": a.map { ["kind": "\($0.kind)", "title": $0.title, "dayOffset": nul($0.dayOffset), "hour": nul($0.hour),
                                            "minute": nul($0.minute), "durationMinutes": nul($0.durationMinutes)] as [String: Any] } ?? NSNull(),
                            "error": nul(ea), "seconds": sa])
            let raw = a.flatMap { Understanding.capture(from: $0, now: now, calendar: cal) }
            record("model raw (full)", c, raw)
            var hybrid = raw
            if hybrid != nil, parsed.hasDay { hybrid!.day = parsed.day; hybrid!.hasDay = true }
            record("hybrid (raw + parser day)", c, hybrid)

            // kind: A2 KindOnly enum on the default model.
            let (k, ek, sk) = await timed { try await Understanding.extractKindOnly(c.input, localeID: deviceLocale).kind }
            entries.append(["input": c.input, "trial": trial, "mode": "kind", "out": k.map { ["kind": $0.rawValue] as [String: Any] } ?? NSNull(),
                            "error": nul(ek), "seconds": sk])
            record("A2 (parser + kind)", c, k.map { Understanding.combine(parser: parsed, kind: $0) } ?? parsed)

            // kind-tagging
            if taggingWorks {
                let (t, et, st) = await timed { try await tagKind(c.input).kind }
                entries.append(["input": c.input, "trial": trial, "mode": "kind-tagging", "out": t.map { ["kind": $0.rawValue] as [String: Any] } ?? NSNull(),
                                "error": nul(et), "seconds": st])
                if t == nil, trial == 1, c.input == suite.cases[0].input { print("kind-tagging first call error: \(et ?? "?")") }
                record("A2 tagging (parser + kind)", c, t.map { Understanding.combine(parser: parsed, kind: $0) } ?? parsed)
            }
        }
        print("capture trial \(trial)/\(trials) done")
    }
    jsonOut(entries, to: "\(out)/apple-fm-r4-capture.json")

    var table = "| variant | n | all | kind | day | hour |\n|---|---|---|---|---|---|\n"
    func pct(_ rows: [(Case, Row)], _ f: (Row) -> Bool) -> String { rows.isEmpty ? "-" : String(format: "%.1f%%", 100 * Double(rows.filter { f($0.1) }.count) / Double(rows.count)) }
    for label in summaryOrder {
        let rows = summaryRows[label]!
        table += "| \(label) | \(rows.count) | \(pct(rows) { $0.all }) | \(pct(rows) { $0.kind }) | \(pct(rows) { $0.day }) | \(pct(rows) { $0.hour }) |\n"
        for lang in ["zh", "en", "mixed"] {
            let r = rows.filter { $0.0.lang == lang }
            table += "|   \(lang) | \(r.count) | \(pct(r) { $0.all }) | \(pct(r) { $0.kind }) | \(pct(r) { $0.day }) | \(pct(r) { $0.hour }) |\n"
        }
    }
    print("\n== capture r4 summary\n" + table)
    for mode in ["full", "kind", "kind-tagging"] {
        let ts = entries.filter { $0["mode"] as? String == mode }.compactMap { $0["seconds"] as? Double }.sorted()
        let errs = entries.filter { $0["mode"] as? String == mode && !($0["error"] is NSNull) }.count
        if !ts.isEmpty { print(String(format: "%@: n %d, errors %d, p50 %.2fs p90 %.2fs max %.2fs", mode, ts.count, errs, ts[ts.count / 2], ts[Int(Double(ts.count - 1) * 0.9)], ts.last!)) }
    }
    try? table.write(toFile: "\(out)/apple-fm-r4-capture-summary.md", atomically: true, encoding: .utf8)

    // MARK: 3. edit r4
    let es = load(EditSuite.self, "\(theirs)/edit-cases-r4.json")
    let (ecal, enow) = makeCal(es.timeZone, es.now)
    let etoday = ecal.startOfDay(for: enow)
    let template = try! String(contentsOfFile: "\(theirs)/edit-prompt-r4.txt", encoding: .utf8)
    let itemsText = try! String(contentsOfFile: "\(out)/edit-items-r4.txt", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let instructions = template.replacingOccurrences(of: "{ITEMS}", with: itemsText)
    let sf = DateFormatter(); sf.calendar = ecal; sf.timeZone = ecal.timeZone; sf.dateFormat = "yyyy-MM-dd'T'HH:mm"
    var editEntries: [[String: Any]] = []
    struct Res { var op: String?, target: String?, day: Int?, hour: Int?, minute: Int? }
    var results: [(EditCase, Res?)] = []
    _ = try? await LanguageModelSession(instructions: instructions).respond(to: "What's on tomorrow?", generating: EditIntent.self)
    for trial in 1...trials {
        for c in es.cases {
            let (r, er, sr) = await timed { try await LanguageModelSession(instructions: instructions).respond(to: c.input, generating: EditIntent.self).content }
            editEntries.append(["input": c.input, "trial": trial,
                                "out": r.map { ["op": $0.op.rawValue, "target": nul($0.target), "dayOffset": nul($0.dayOffset), "hour": nul($0.hour), "minute": nul($0.minute)] as [String: Any] } ?? NSNull(),
                                "error": nul(er), "seconds": sr])
            results.append((c, r.map { Res(op: $0.op.rawValue, target: $0.target, day: $0.dayOffset, hour: $0.hour, minute: $0.minute) }))
        }
        print("edit trial \(trial)/\(trials) done")
    }
    jsonOut(editEntries, to: "\(out)/apple-fm-r4-edit.json")

    func exp(_ c: EditCase) -> (day: Int, hour: Int, minute: Int)? {
        guard let s = c.start, let d = sf.date(from: s) else { return nil }
        let comps = ecal.dateComponents([.hour, .minute], from: d)
        return (dayOffset(ecal, etoday, d), comps.hour!, comps.minute!)
    }
    func ratio(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b) }
    var opOK = 0, tgtOK = 0, tgtN = 0, timeOK = 0, timeN = 0, timeGivenOK = 0, timeGivenN = 0, errN = 0
    var perOp: [String: (Int, Int)] = [:]
    for (c, r) in results {
        guard let r else { errN += 1; perOp[c.op, default: (0, 0)].1 += 1; if c.target != nil { tgtN += 1 }; if c.op == "move" { timeN += 1 }; continue }
        let ok = r.op == c.op
        if ok { opOK += 1 }
        perOp[c.op, default: (0, 0)].0 += ok ? 1 : 0
        perOp[c.op, default: (0, 0)].1 += 1
        if c.target != nil { tgtN += 1; if r.target == c.target { tgtOK += 1 } }
        if c.op == "move", let e = exp(c) {
            timeN += 1
            let exact = r.op == "move" && r.day == e.day && r.hour == e.hour && (r.minute ?? 0) == e.minute
            if exact { timeOK += 1 }
            if r.op == "move" && r.target == c.target { timeGivenN += 1; if exact { timeGivenOK += 1 } }
        }
    }
    var et = "| metric | result |\n|---|---|\n"
    et += "| op accuracy | \(ratio(opOK, results.count)) |\n"
    for op in ["move", "delete", "clarify", "none"] { let v = perOp[op] ?? (0, 0); et += "|   op=\(op) | \(ratio(v.0, v.1)) |\n" }
    et += "| target accuracy (move/delete cases) | \(ratio(tgtOK, tgtN)) |\n"
    et += "| move time exact (dayOffset+hour+minute), all move cases | \(ratio(timeOK, timeN)) |\n"
    et += "| move time exact, given op=move and right target | \(ratio(timeGivenOK, timeGivenN)) |\n"
    et += "| errors (guardrail etc.) | \(errN)/\(results.count) |\n"
    let ets = editEntries.compactMap { $0["seconds"] as? Double }.sorted()
    et += String(format: "| latency p50 / p90 / max | %.2fs / %.2fs / %.2fs |\n", ets[ets.count / 2], ets[Int(Double(ets.count - 1) * 0.9)], ets.last!)
    print("\n== edit r4 summary\n" + et)
    try? et.write(toFile: "\(out)/apple-fm-r4-edit-summary.md", atomically: true, encoding: .utf8)
}

await run()
