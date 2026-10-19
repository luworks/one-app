// Round 5 edit eval: model picks op + target id + a small number; Swift code does the time arithmetic and ambiguity checks.
// Usage: round5.sh <edit-cases.json> <out.json> [trials]
import Foundation
import FoundationModels

struct RawItem: Decodable {
  let id: String, type: String, title: String, start: String?, minutes: Int?, attendees: Int?
}
struct EditCase: Decodable {
  let lang: String, input: String, op: String, target: String?, start: String?, level: Int?,
    scenario: String?
}
struct EditSuite: Decodable {
  let now: String, timeZone: String, items: [RawItem], cases: [EditCase]
}

func nul(_ v: Any?) -> Any { v ?? NSNull() }

func run() async {
  let args = CommandLine.arguments
  guard args.count >= 3 else {
    print("usage: round5 <edit-cases.json> <out.json> [trials]")
    return
  }
  let trials = args.count > 3 ? Int(args[3]) ?? 5 : 5
  let suite = try! JSONDecoder().decode(
    EditSuite.self, from: FileManager.default.contents(atPath: args[1])!)
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: suite.timeZone)!
  let f = DateFormatter()
  f.calendar = cal
  f.timeZone = cal.timeZone
  f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
  let now = f.date(from: suite.now)!
  f.dateFormat = "yyyy-MM-dd'T'HH:mm"
  func parseDate(_ s: String) -> Date? { f.date(from: String(s.prefix(16))) }
  let items = suite.items.map {
    EditItem(
      id: $0.id, type: $0.type, title: $0.title, start: $0.start.flatMap { parseDate($0) },
      minutes: $0.minutes ?? 30, attendees: $0.attendees ?? 0)
  }
  guard case .available = SystemLanguageModel.default.availability else {
    print("MODEL NOT AVAILABLE")
    return
  }
  // warm-up
  _ = try? await Editing.plan("What's on tomorrow?", items: items, now: now, calendar: cal)

  var entries: [[String: Any]] = []
  struct R {
    var c: EditCase
    var raw: EditPlan?
    var d: EditDecision
    var err: Bool
  }
  var results: [R] = []
  for trial in 1...trials {
    for c in suite.cases {
      let t0 = Date()
      var plan: EditPlan?
      var err: String?
      do { plan = try await Editing.plan(c.input, items: items, now: now, calendar: cal) } catch {
        err = String("\(error)".prefix(120))
      }
      let secs = Date().timeIntervalSince(t0)
      let d = Editing.decide(text: c.input, plan: plan, items: items, now: now, calendar: cal)
      f.dateFormat = "yyyy-MM-dd'T'HH:mm"
      entries.append([
        "input": c.input, "trial": trial,
        "raw": plan.map { ["op": $0.op.rawValue, "target": nul($0.target)] as [String: Any] }
          ?? NSNull(),
        "final": [
          "op": d.op.rawValue, "target": nul(d.target),
          "start": nul(d.newStart.map { f.string(from: $0) }), "reason": d.reason,
        ] as [String: Any],
        "error": nul(err), "seconds": secs,
      ])
      results.append(R(c: c, raw: plan, d: d, err: err != nil))
    }
    print("trial \(trial)/\(trials) done")
  }
  try! JSONSerialization.data(
    withJSONObject: entries, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  ).write(to: URL(fileURLWithPath: args[2]))

  func ratio(_ a: Int, _ b: Int) -> String {
    b == 0 ? "-" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b)
  }
  var opRaw = 0
  var opFinal = 0
  var tgtRaw = 0
  var tgtFinal = 0
  var tgtN = 0
  var timeOK = 0
  var timeN = 0
  var timeGivenOK = 0
  var timeGivenN = 0
  var errN = 0
  var perOp: [String: (Int, Int)] = [:]
  for r in results {
    if r.err { errN += 1 }
    perOp[r.c.op, default: (0, 0)].1 += 1
    if r.raw?.op.rawValue == r.c.op { opRaw += 1 }
    if r.d.op.rawValue == r.c.op {
      opFinal += 1
      perOp[r.c.op, default: (0, 0)].0 += 1
    }
    if r.c.target != nil {
      tgtN += 1
      if r.raw?.target == r.c.target { tgtRaw += 1 }
      if r.d.target == r.c.target { tgtFinal += 1 }
    }
    if r.c.op == "move" {
      timeN += 1
      let exp = r.c.start.flatMap { parseDate($0) }
      let exact = r.d.op == .move && r.d.newStart == exp
      if exact { timeOK += 1 }
      if r.d.op == .move && r.d.target == r.c.target {
        timeGivenN += 1
        if exact { timeGivenOK += 1 }
      }
    }
  }
  let n = results.count
  var t = "| metric | model alone (no code rules) | with code rules |\n|---|---|---|\n"
  t += "| op accuracy | \(ratio(opRaw, n)) | \(ratio(opFinal, n)) |\n"
  for op in ["move", "delete", "clarify", "none"] {
    let v = perOp[op] ?? (0, 0)
    t += "|   op=\(op) (clarify recall for clarify) | - | \(ratio(v.0, v.1)) |\n"
  }
  t +=
    "| target accuracy (move/delete cases) | \(ratio(tgtRaw, tgtN)) | \(ratio(tgtFinal, tgtN)) |\n"
  t += "| move time exact (all move cases) | - | \(ratio(timeOK, timeN)) |\n"
  t +=
    "| move time exact given op=move and right target | - | \(ratio(timeGivenOK, timeGivenN)) |\n"
  t += "| model errors | \(errN)/\(n) | |\n"
  let secs = entries.compactMap { $0["seconds"] as? Double }.sorted()
  t += String(
    format: "| latency p50 / p90 / max | %.2fs / %.2fs / %.2fs | |\n", secs[secs.count / 2],
    secs[Int(Double(secs.count - 1) * 0.9)], secs.last!)
  print("\n== edit summary (\(args[1]))\n" + t)
  try? t.write(
    toFile: args[2].replacingOccurrences(of: ".json", with: "-summary.md"), atomically: true,
    encoding: .utf8)
  // Unsafe: a card that would move / delete the wrong item, or act when it should ask or ignore.
  let unsafe = results.filter { r in
    (r.d.op == .move || r.d.op == .delete)
      && !(r.d.op.rawValue == r.c.op && r.d.target == r.c.target)
  }.count
  print("unsafe edit rate: \(ratio(unsafe, results.count))")
  // Per level: the whole decision (op + target + new time when moving) right, and the model-alone op.
  let lvls = Set(results.compactMap(\.c.level)).sorted()
  if !lvls.isEmpty {
    print(
      "| level | cases x trials | decision right (op+target+time) | op | model-alone op |\n|---|---|---|---|---|"
    )
    for lv in lvls {
      let rs = results.filter { $0.c.level == lv }
      let right = rs.filter { r in
        r.d.op.rawValue == r.c.op && r.d.target == r.c.target
          && (r.c.op != "move" || r.d.newStart == r.c.start.flatMap { parseDate($0) })
      }.count
      let op = rs.filter { $0.d.op.rawValue == $0.c.op }.count
      let raw = rs.filter { $0.raw?.op.rawValue == $0.c.op }.count
      print(
        "| L\(lv) | \(rs.count) | \(ratio(right, rs.count)) | \(ratio(op, rs.count)) | \(ratio(raw, rs.count)) |"
      )
    }
  }
  let scenarios = Array(Set(results.compactMap(\.c.scenario))).sorted()
  if !scenarios.isEmpty {
    print("| scenario | n | decision right |\n|---|---|---|")
    for sc in scenarios {
      let rs = results.filter { $0.c.scenario == sc }
      let right = rs.filter { r in
        r.d.op.rawValue == r.c.op && r.d.target == r.c.target
          && (r.c.op != "move" || r.d.newStart == r.c.start.flatMap { parseDate($0) })
      }.count
      print("| \(sc) | \(rs.count) | \(ratio(right, rs.count)) |")
    }
  }
  // Final misses, one line per distinct (input, outcome).
  var seen = Set<String>()
  for r in results {
    let ok =
      r.d.op.rawValue == r.c.op && r.d.target == r.c.target
      && (r.c.op != "move" || r.d.newStart == r.c.start.flatMap { parseDate($0) })
    guard !ok else { continue }
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    let line =
      "✗ \(r.c.input) | want \(r.c.op) \(r.c.target ?? "-") \(r.c.start ?? "-") | got \(r.d.op.rawValue) \(r.d.target ?? "-") \(r.d.newStart.map { f.string(from: $0) } ?? "-") [\(r.d.reason)] raw \(r.raw.map { "\($0.op.rawValue) \($0.target ?? "-")" } ?? "ERR")"
    if seen.insert(line).inserted { print(line) }
  }
}

await run()
