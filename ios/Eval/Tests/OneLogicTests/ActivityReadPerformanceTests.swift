import Dispatch
import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// Portable to the frozen source baseline: uses only the existing store API.
/// This is a warm host SQLite read benchmark, not app UI latency or cold I/O.
final class ActivityReadPerformanceTests: XCTestCase {
  func testWarmPageReads() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["ACTIVITY_READ_BENCH"] == "1" else { throw XCTSkip("set ACTIVITY_READ_BENCH=1") }
    let samples = Int(env["ACTIVITY_READ_SAMPLES"] ?? "5") ?? 5
    guard (3...5).contains(samples) else { throw XCTSkip("ACTIVITY_READ_SAMPLES must be 3...5") }
    let rowCount = 100_000
    let iterations = 25
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "activity-read-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ActivityStore(location: .file(directory.appendingPathComponent("read.sqlite")))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_792_000_000)
    // Versioned deterministic generator; generation/insertion/cursor discovery are outside timing.
    for base in stride(from: 0, to: rowCount, by: 1000) {
      let events = (base..<min(base + 1000, rowCount)).map { i -> ActivityEvent in
        var e = ActivityEvent(
          kind: "change.completed", actor: i.isMultiple(of: 2) ? "you" : "ai",
          channel: "app", at: start.addingTimeInterval(Double(i) * 20), calendar: calendar)
        e.uid = "read-\(i)"
        e.device = "read-fixture-v1"
        e.title = i.isMultiple(of: 5) ? "买牛奶 \(i)" : "Write report \(i)"
        e.beforeText = "Not planned"
        e.afterText = "Today 10:00"
        e.subjectKind = "task"
        e.subjectRef = "ref-\(i % 5000)"
        e.approval = "user"
        return e
      }
      try store.insert(events)
    }
    let query = ActivityQuery(tiers: [.changes], actors: .you)
    let preceding = try store.page(query, limit: 10_000)
    let cursor = try XCTUnwrap(ActivityCursor(after: preceding.last))
    let search = ActivityQuery(tiers: [.changes], search: "牛奶")
    let cases: [(String, ActivityQuery, ActivityCursor?)] = [
      ("activity_read_newest", query, nil),
      ("activity_read_deep", query, cursor),
      ("activity_read_search", search, nil),
    ]
    for (_, q, after) in cases {
      XCTAssertEqual(try store.page(q, after: after, limit: 150).count, 150)
    }
    for sample in 1...samples {
      for (metric, q, after) in cases {
        var readRows = 0
        let startNs = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
          readRows += try store.page(q, after: after, limit: 150).count
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000
        XCTAssertEqual(readRows, iterations * 150)
        let record: [String: Any] = [
          "metric": metric, "sample": sample, "n": samples, "unit": "ms",
          "value": elapsedMs / Double(iterations), "batch_ms": elapsedMs,
          "iterations": iterations, "rows": rowCount, "page_size": 150,
          "fixture": "activity-read-v1", "cache": "warm", "clock": "uptimeNanoseconds",
        ]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("PERF_SAMPLE " + String(decoding: json, as: UTF8.self))
      }
    }
  }
}
