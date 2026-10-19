import CryptoKit
import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// Exports actual production fallback content on the frozen development inputs.
/// This host seam cannot observe UI gates or persisted writes; those stay null/unmeasured.
final class CaptureTitleQualityExportTests: XCTestCase {
  func testExportDevelopmentFallbackObservations() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let fixture = env["AI_TITLE_EVAL_FIXTURES"], let output = env["AI_TITLE_EVAL_OUTPUT"]
    else {
      throw XCTSkip(
        "Set frozen TitleQuality fixture and canonical evidence output paths to export observations"
      )
    }
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixture)))
        as? [String: Any])
    let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: root["timeZone"] as? String ?? ""))
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let now = try XCTUnwrap(formatter.date(from: root["now"] as? String ?? ""))
    let subset: Set<String> = ["watch-sleep-zh", "must-sleep-zh", "no-peanuts-en"]
    let directory = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var rows: [[String: Any]] = []
    for entry in cases {
      guard let id = entry["id"] as? String, subset.contains(id),
        entry["split"] as? String == "development"
      else { continue }
      let turns = try XCTUnwrap(entry["turns"] as? [[String: Any]])
      let input = try XCTUnwrap(turns.first?["input"] as? String)
      let intent = ChatRouting.intent(input)
      let parsed = CaptureParser.parse(input, now: now, calendar: calendar)
      let capture = await CaptureTitleRefinement.refine(parsed, source: input, available: false) {
        _ in
        XCTFail("offline observations must not invoke a model")
        return nil
      }
      let route =
        intent == .capture ? "capture" : (intent == .conversation ? "conversation" : "clarify")
      let item: [String: Any] = [
        "kind": capture.ringsAsAlarm ? "alarm" : (capture.kind == .event ? "event" : "task"),
        "title": capture.title, "notes": capture.notes as Any? ?? NSNull(),
        "day": calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: capture.day)
          .day as Any? ?? NSNull(),
        "time": capture.hour.map { String(format: "%02d:%02d", $0, capture.minute) } as Any?
          ?? NSNull(),
        "repeat": capture.repeatRule as Any? ?? NSNull(),
      ]
      let out: [String: Any] = [
        "route": route, "intent": intent == .capture ? "create" : "chat",
        "gate": NSNull(), "writesBeforeConfirmation": NSNull(), "items": [item],
      ]
      let raw: [String: Any] = [
        "backend": "production-parser-and-offline-title-refinement", "modelInvoked": false,
        "appSHA": env["AI_TITLE_EVAL_SHA"] ?? "unknown", "input": input, "out": out,
        "limitations":
          "Host content seam only; UI gate, persisted writes and FoundationModels generation unmeasured",
      ]
      let data = try JSONSerialization.data(
        withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
      let artifact = directory.appendingPathComponent(id + "-turn-0.json")
      try data.write(to: artifact)
      let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      rows.append([
        "caseId": id, "turn": 0, "artifact": ["path": artifact.path, "sha256": hash], "out": out,
      ])
    }
    XCTAssertEqual(
      rows.count, subset.count,
      "all selected development inputs must exist; reserved inputs are untouched")
    let observations: [String: Any] = [
      "evidence": "Production pure fallback execution only; FM and app gates unmeasured",
      "rows": rows,
    ]
    try JSONSerialization.data(
      withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]
    )
    .write(to: directory.appendingPathComponent("observations.json"))
  }
}
