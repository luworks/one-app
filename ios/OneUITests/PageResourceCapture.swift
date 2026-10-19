import XCTest

/// Shared raw resource validation; latency and functional assertions remain in each journey.
@MainActor
extension XCTestCase {
  func capturePageResourceWindow(
    app: XCUIApplication, sequence: Int, start: UInt64, layout: UInt64, route: String
  ) -> String? {
    let reports = app.staticTexts.matching(identifier: "performance.trace")
    let prefix = "v=1;seq=\(sequence);"
    let predicate = NSPredicate { _, _ in
      reports.allElementsBoundByIndex.contains {
        $0.label.hasPrefix(prefix) && $0.label.contains(";resource_b64=")
      }
    }
    XCTAssertEqual(
      XCTWaiter().wait(
        for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5),
      .completed, "Same-sequence resource window: \(route)")
    guard
      let report = reports.allElementsBoundByIndex.map({ $0.label }).first(where: {
        $0.hasPrefix(prefix) && $0.contains(";resource_b64=")
      }), let encoded = report.components(separatedBy: ";resource_b64=").last,
      let data = Data(base64Encoded: encoded), let json = String(data: data, encoding: .utf8),
      let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let samples = payload["samples"] as? [[String: Any]]
    else {
      XCTFail("Missing or invalid resource payload: \(route)")
      return nil
    }
    // Retain raw errors before checking acceptance, including in a failed functional attempt.
    print("PERF_RESOURCE_APP \(json)")
    let attachment = XCTAttachment(string: json)
    attachment.name = "resources.\(route).seq\(sequence)"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(payload["schema"] as? Int, 1)
    XCTAssertEqual(payload["seq"] as? Int, sequence)
    XCTAssertEqual(payload["route"] as? String, route)
    XCTAssertEqual((payload["start_ns"] as? NSNumber)?.uint64Value, start)
    XCTAssertEqual((payload["layout_ns"] as? NSNumber)?.uint64Value, layout)
    XCTAssertEqual((payload["window_end_ns"] as? NSNumber)?.uint64Value, layout + 1_000_000_000)
    XCTAssertEqual(payload["status"] as? String, "complete")
    XCTAssertFalse(samples.isEmpty)
    XCTAssertGreaterThan(payload["postlayout_valid_count"] as? Int ?? 0, 0)
    var previous: UInt64 = 0
    for sample in samples {
      XCTAssertEqual(sample["valid"] as? Bool, true)
      XCTAssertEqual(sample["kern_return"] as? Int, 0)
      let timestamp = (sample["ns"] as? NSNumber)?.uint64Value ?? 0
      XCTAssertGreaterThanOrEqual(timestamp, start)
      XCTAssertGreaterThan(timestamp, previous)
      previous = timestamp
      for key in ["phys_footprint_bytes", "resident_size_bytes"] {
        let value = (sample[key] as? NSNumber)?.doubleValue ?? .nan
        XCTAssertTrue(value.isFinite && value > 0, "Valid app memory sample: \(key)")
      }
    }
    return report
  }

}
