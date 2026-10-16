// Round 5 edit eval: model picks op + target id + a small number; Swift code does the time arithmetic and ambiguity checks.
// Usage: round5.sh <edit-cases.json> <out.json> [trials]
import Foundation
import FoundationModels

struct RawItem: Decodable { let id: String, type: String, title: String, start: String?, minutes: Int, attendees: Int }
struct EditCase: Decodable { let lang: String, input: String, op: String, target: String?, start: String? }
struct EditSuite: Decodable { let now: String, timeZone: String, items: [RawItem], cases: [EditCase] }

func nul(_ v: Any?) -> Any { v ?? NSNull() }

func run() async {
    let args = CommandLine.arguments
    guard args.count >= 3 else { print("usage: round5 <edit-cases.json> <out.json> [trials]"); return }
    let trials = args.count > 3 ? Int(args[3]) ?? 5 : 5
    let suite = try! JSONDecoder().decode(EditSuite.self, from: FileManager.default.contents(atPath: args[1])!)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: suite.timeZone)!
    let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; let now = f.date(from: suite.now)!
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    let items = suite.items.map { EditItem(id: $0.id, type: $0.type, title: $0.title, start: $0.start.flatMap { f.date(from: $0) }, minutes: $0.minutes, attendees: $0.attendees) }
    guard case .available = SystemLanguageModel.default.availability else { print("MODEL NOT AVAILABLE"); return }
    _ = try? await Editing.plan("What's on tomorrow?", items: items, now: now, calendar: cal) // warm-up

    var entries: [[String: Any]] = []
    struct R { var c: EditCase; var raw: EditPlan?; var d: EditDecision; var dm: EditDecision; var err: Bool }
    var results: [R] = []
    for trial in 1...trials {
        for c in suite.cases {
            let t0 = Date()
            var plan: EditPlan?; var err: String?
            do { plan = try await Editing.plan(c.input, items: items, now: now, calendar: cal) } catch { err = String("\(error)".prefix(120)) }
            let secs = Date().timeIntervalSince(t0)
            let d = Editing.decide(text: c.input, plan: plan, items: items, now: now, calendar: cal, codeAmounts: true)
            let dm = Editing.decide(text: c.input, plan: plan, items: items, now: now, calendar: cal, codeAmounts: false)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            entries.append(["input": c.input, "trial": trial,
                            "raw": plan.map { ["op": $0.op.rawValue, "target": nul($0.target), "postponeMinutes": nul($0.postponeMinutes), "targetHour": nul($0.targetHour),
                                               "targetMinute": nul($0.targetMinute), "dayShift": nul($0.dayShift)] as [String: Any] } ?? NSNull(),
                            "final": ["op": d.op.rawValue, "target": nul(d.target), "start": nul(d.newStart.map { f.string(from: $0) }), "reason": d.reason] as [String: Any],
                            "final_model_number": ["op": dm.op.rawValue, "target": nul(dm.target), "start": nul(dm.newStart.map { f.string(from: $0) }), "reason": dm.reason] as [String: Any],
                            "error": nul(err), "seconds": secs])
            results.append(R(c: c, raw: plan, d: d, dm: dm, err: err != nil))
        }
        print("trial \(trial)/\(trials) done")
    }
    try! JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: args[2]))

    func ratio(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b) }
    var timeOKm = 0, timeGivenOKm = 0, timeGivenNm = 0
    var opRaw = 0, opFinal = 0, tgtRaw = 0, tgtFinal = 0, tgtN = 0, timeOK = 0, timeN = 0, timeGivenOK = 0, timeGivenN = 0, errN = 0
    var perOp: [String: (Int, Int)] = [:]
    for r in results {
        if r.err { errN += 1 }
        perOp[r.c.op, default: (0, 0)].1 += 1
        if r.raw?.op.rawValue == r.c.op { opRaw += 1 }
        if r.d.op.rawValue == r.c.op { opFinal += 1; perOp[r.c.op, default: (0, 0)].0 += 1 }
        if r.c.target != nil {
            tgtN += 1
            if r.raw?.target == r.c.target { tgtRaw += 1 }
            if r.d.target == r.c.target { tgtFinal += 1 }
        }
        if r.c.op == "move" {
            timeN += 1
            let exp = r.c.start.flatMap { f.date(from: $0) }
            let exact = r.d.op == .move && r.d.newStart == exp
            if exact { timeOK += 1 }
            let exactM = r.dm.op == .move && r.dm.newStart == exp
            if exactM { timeOKm += 1 }
            if r.dm.op == .move && r.dm.target == r.c.target { timeGivenNm += 1; if exactM { timeGivenOKm += 1 } }
            if r.d.op == .move && r.d.target == r.c.target { timeGivenN += 1; if exact { timeGivenOK += 1 } }
        }
    }
    let n = results.count
    var t = "| metric | model alone (no code rules) | with code rules |\n|---|---|---|\n"
    t += "| op accuracy | \(ratio(opRaw, n)) | \(ratio(opFinal, n)) |\n"
    for op in ["move", "delete", "clarify", "none"] { let v = perOp[op] ?? (0, 0); t += "|   op=\(op) (clarify recall for clarify) | - | \(ratio(v.0, v.1)) |\n" }
    t += "| target accuracy (move/delete cases) | \(ratio(tgtRaw, tgtN)) | \(ratio(tgtFinal, tgtN)) |\n"
    t += "| move time exact (all move cases), amount from the words | - | \(ratio(timeOK, timeN)) |\n"
    t += "| move time exact given op=move and right target, amount from the words | - | \(ratio(timeGivenOK, timeGivenN)) |\n"
    t += "| move time exact (all move cases), amount from the model's number | - | \(ratio(timeOKm, timeN)) |\n"
    t += "| move time exact given op=move and right target, model's number | - | \(ratio(timeGivenOKm, timeGivenNm)) |\n"
    t += "| model errors | \(errN)/\(n) | |\n"
    let secs = entries.compactMap { $0["seconds"] as? Double }.sorted()
    t += String(format: "| latency p50 / p90 / max | %.2fs / %.2fs / %.2fs | |\n", secs[secs.count / 2], secs[Int(Double(secs.count - 1) * 0.9)], secs.last!)
    print("\n== edit summary (\(args[1]))\n" + t)
    try? t.write(toFile: args[2].replacingOccurrences(of: ".json", with: "-summary.md"), atomically: true, encoding: .utf8)
    // Final misses, one line per distinct (input, outcome).
    var seen = Set<String>()
    for r in results {
        let ok = r.d.op.rawValue == r.c.op && r.d.target == r.c.target && (r.c.op != "move" || r.d.newStart == r.c.start.flatMap { f.date(from: $0) })
        guard !ok else { continue }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let line = "✗ \(r.c.input) | want \(r.c.op) \(r.c.target ?? "-") \(r.c.start ?? "-") | got \(r.d.op.rawValue) \(r.d.target ?? "-") \(r.d.newStart.map { f.string(from: $0) } ?? "-") [\(r.d.reason)] raw \(r.raw.map { "\($0.op.rawValue) \($0.target ?? "-") pm\($0.postponeMinutes.map(String.init) ?? "-") h\($0.targetHour.map(String.init) ?? "-") ds\($0.dayShift.map(String.init) ?? "-")" } ?? "ERR")"
        if seen.insert(line).inserted { print(line) }
    }
}

await run()
