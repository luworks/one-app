import XCTest

/// Simulator fallback baseline only. Each repetition restores identical fixture and chat history.
/// XCTest interaction time is never used as AI latency; raw app-side monotonic endpoints are retained.
@MainActor
final class AIResponsePerformanceTests: XCTestCase {
  private var app: XCUIApplication!
  private let stages: Set<String> = [
    "ai_send_to_feedback_layout", "ai_send_to_first_response_ready",
    "ai_send_to_full_response_ready",
    "ai_ready_to_response_layout", "ai_turn_to_response_layout",
  ]

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments =
        TestData.launchArguments + ["-performanceTrace", "-uiTestingNow", "09:41"]
    }
  }

  override func tearDown() async throws {
    await MainActor.run {
      app.terminate()
      super.tearDown()
    }
  }

  private func freshAsk(journey: String, repetition: Int) {
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["Ask AI or add anything"].waitForExistence(timeout: 10))
    app.buttons["Ask AI or add anything"].tap()
    let input = app.textViews["Ask AI or add anything"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    // Ask's destination modifier exposes its own report while the modal hides the presenter.
    let reports = app.staticTexts.matching(identifier: "performance.trace")
    let opened = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        reports.allElementsBoundByIndex.contains {
          $0.label.contains(";name=page.ai;") && $0.label.contains(";route=ai;")
        }
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter().wait(for: [opened], timeout: 10), .completed, "Ask content layout endpoint")
    guard
      let report = reports.allElementsBoundByIndex.map({ $0.label }).first(where: {
        $0.contains(";name=page.ai;") && $0.contains(";route=ai;")
      })
    else {
      XCTFail("Missing modal page.ai report")
      return
    }
    let values = fields(report)
    guard let start = UInt64(values["start_ns"] ?? ""), let end = UInt64(values["end_ns"] ?? ""),
      let ms = Double(values["ms"] ?? "")
    else {
      XCTFail("Malformed page.ai sample: \(report)")
      return
    }
    XCTAssertEqual(values["v"], "1")
    XCTAssertGreaterThanOrEqual(end, start)
    XCTAssertTrue(ms.isFinite && ms >= 0)
    XCTAssertEqual(ms, Double(end - start) / 1_000_000, accuracy: 0.000_001)
    XCTAssertTrue(input.isHittable, "Ask input is usable before sending")
    print("PERF_SAMPLE_APP \(report)")
    let pageSample = XCTAttachment(string: report)
    pageSample.name = "page.ai - \(journey).fresh.\(repetition)"
    pageSample.lifetime = .keepAlways
    add(pageSample)
    XCTAssertTrue(app.staticTexts["performance.ai.history"].firstMatch.waitForExistence(timeout: 5))
    print(
      "PERF_CONTEXT v=1;journey=\(journey);rep=\(repetition);launch=process_cold_os_warm;chat=fresh;store=in_memory;fixture=today-dataset.json;clock=09:41;prewarm=default;backend_track=simulator_fallback;wall_epoch=\(Date.now.timeIntervalSince1970)"
    )
  }

  private var history: String { app.staticTexts["performance.ai.history"].firstMatch.label }

  private func fields(_ sample: String) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: sample.split(separator: ";").compactMap { part -> (String, String)? in
        let pair = part.split(separator: "=", maxSplits: 1)
        return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
      })
  }

  private func rows(_ history: String) -> [String] {
    history.components(separatedBy: "\n").filter { $0.hasPrefix("v=1;name=ai_") }
  }

  /// Wait for all reports from the one new turn, including feedback that may arrive after ready.
  @discardableResult
  private func sendAndSample(
    _ text: String, context: String, backend: String, diagnoseConversation: Bool = false
  ) -> [String] {
    let previous = Set(rows(history).compactMap { fields($0)["turn"] })
    let field = app.textViews["Ask AI or add anything"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(text + "\n")
    var samples: [String] = []
    var diagnostics: [String] = []
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { [self] _, _ in
        let snapshot = history
        let fresh = rows(snapshot).filter { !previous.contains(fields($0)["turn"] ?? "") }
        guard let token = fresh.last.flatMap({ fields($0)["turn"] }) else { return false }
        samples = fresh.filter { fields($0)["turn"] == token }
        diagnostics = snapshot.components(separatedBy: "\n").filter {
          $0.hasPrefix("PERF_STAGE_AI v=1;") && fields($0)["turn"] == token
        }
        return Set(samples.compactMap { fields($0)["name"] }) == stages
          && (!diagnoseConversation || diagnostics.count == 1)
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter().wait(for: [ready], timeout: 15), .completed,
      "Missing app-side turn endpoint: \(context)")
    XCTAssertEqual(samples.count, stages.count, "Exactly one raw sample per keyed stage")
    var starts: [String: UInt64] = [:]
    var ends: [String: UInt64] = [:]
    for sample in samples {
      let values = fields(sample)
      guard let start = UInt64(values["start_ns"] ?? ""), let end = UInt64(values["end_ns"] ?? ""),
        let ms = Double(values["ms"] ?? ""), let name = values["name"]
      else {
        XCTFail("Malformed app sample: \(sample)")
        continue
      }
      XCTAssertGreaterThanOrEqual(end, start)
      XCTAssertTrue(ms.isFinite && ms >= 0)
      XCTAssertEqual(ms, Double(end - start) / 1_000_000, accuracy: 0.000_001)
      XCTAssertEqual(values["backend"], backend)
      XCTAssertEqual(values["model_available"], "0", "This is the simulator fallback track")
      XCTAssertEqual(values["streaming"], "0")
      XCTAssertEqual(values["first_full_same_emission"], "1")
      XCTAssertFalse(sample.contains(text), "Performance metadata must not contain the input")
      starts[name] = start
      ends[name] = end
      print("PERF_SAMPLE_APP \(sample)")
    }
    XCTAssertEqual(
      ends["ai_send_to_first_response_ready"], ends["ai_send_to_full_response_ready"],
      "No streaming: one emitted result")
    XCTAssertEqual(starts["ai_ready_to_response_layout"], ends["ai_send_to_full_response_ready"])
    XCTAssertEqual(ends["ai_ready_to_response_layout"], ends["ai_turn_to_response_layout"])
    if diagnoseConversation {
      XCTAssertEqual(
        diagnostics.count, 1, "One complete conversation diagnostic after both layout endpoints")
      if let diagnostic = diagnostics.first {
        let values = fields(diagnostic)
        XCTAssertEqual(values["turn"], samples.first.flatMap { fields($0)["turn"] })
        XCTAssertEqual(values["backend"], backend)
        XCTAssertFalse(diagnostic.contains(text), "Stage metadata must not contain the input")
        for key in [
          "context_complete", "respond_enter", "record_turn_before", "record_turn_after",
          "finish_emission_enter", "finish_emission_assigned", "on_change_enter",
          "send", "ready", "feedback_layout", "response_layout",
        ] {
          XCTAssertNotNil(UInt64(values[key + "_ns"] ?? ""), "Missing conversation stage: \(key)")
        }
        for phase in ["feedback", "response"] {
          let keys = ["probe_arm", "probe_callback", "probe_eligible"].map {
            phase + "_" + $0 + "_ns"
          }
          let timestamps = keys.compactMap { UInt64(values[$0] ?? "") }
          XCTAssertEqual(timestamps.count, keys.count, "Complete probe attribution: \(phase)")
          XCTAssertEqual(timestamps, timestamps.sorted(), "Arm/callback/eligible order: \(phase)")
        }
        for pair in [
          ("persist_before", "persist_after"), ("scroll_request_before", "scroll_request_after"),
        ] {
          guard let before = UInt64(values[pair.0 + "_ns"] ?? ""),
            let after = UInt64(values[pair.1 + "_ns"] ?? "")
          else {
            XCTFail("Missing message observer attribution: \(pair)")
            continue
          }
          XCTAssertGreaterThanOrEqual(after, before)
        }
        switch values["dispatch"] ?? "" {
        case "async":
          for key in ["task_enter", "chat_response_await_before", "chat_response_await_after"] {
            XCTAssertNotNil(UInt64(values[key + "_ns"] ?? ""), "Missing async stage: \(key)")
          }
          XCTAssertFalse(
            values.keys.contains { $0.hasPrefix("local_reply_") },
            "Async dispatch has no local reply markers")
        case "local_sync":
          for key in ["local_reply_before", "local_reply_after"] {
            XCTAssertNotNil(UInt64(values[key + "_ns"] ?? ""), "Missing local reply stage: \(key)")
          }
          XCTAssertFalse(
            values.keys.contains {
              $0.hasPrefix("task_enter_") || $0.hasPrefix("chat_response_await_")
            }, "Synchronous dispatch must not fabricate async timestamps")
          if let before = UInt64(values["local_reply_before_ns"] ?? ""),
            let after = UInt64(values["local_reply_after_ns"] ?? "")
          {
            XCTAssertGreaterThanOrEqual(after, before)
          }
        default:
          XCTFail("Unknown conversation dispatch mode: \(values["dispatch"] ?? "missing")")
        }
        XCTAssertEqual(UInt64(values["send_ns"] ?? ""), starts["ai_send_to_feedback_layout"])
        XCTAssertEqual(UInt64(values["ready_ns"] ?? ""), ends["ai_send_to_full_response_ready"])
        XCTAssertEqual(
          UInt64(values["feedback_layout_ns"] ?? ""), ends["ai_send_to_feedback_layout"])
        XCTAssertEqual(
          UInt64(values["response_layout_ns"] ?? ""), ends["ai_turn_to_response_layout"])
        // Export from XCTest so the complete app-side line survives in the runner log.
        print(diagnostic)
      }
    }
    let attachment = XCTAttachment(
      string: "context=\(context)\n" + (samples + diagnostics).joined(separator: "\n"))
    attachment.name = "AI raw app endpoints - " + context
    attachment.lifetime = .keepAlways
    add(attachment)
    return samples
  }

  private func text(_ fragment: String) -> XCUIElement {
    app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
  }

  private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

  /// Shortest first-window baseline: n=3 first sends, each in a fresh process and fresh chat.
  func testConversationFreshLaunchN3() {
    for repetition in 1...3 {
      freshAsk(journey: "conversation", repetition: repetition)
      sendAndSample(
        "Hello", context: "conversation.fresh.\(repetition).turn1",
        backend: "fallback_model_unavailable", diagnoseConversation: true)
      XCTAssertTrue(text("What's on your mind?").exists)
      XCTAssertFalse(app.buttons["Add"].exists)
      XCTAssertFalse(app.buttons["capture-add-all"].exists)
      XCTAssertFalse(any("change-card").exists)
      XCTAssertFalse(app.buttons["plan.apply"].exists)
    }
  }

  /// n=3 identical recurring-preview journeys. Explicit recurrence retains Add under the one-off Send exception.
  /// Follow-up samples have exactly one prior request, never growing history.
  func testCaptureFollowupConfirmationFreshLaunchN3() {
    for repetition in 1...3 {
      freshAsk(journey: "capture_followup", repetition: repetition)
      sendAndSample(
        "Call Alex tomorrow at 3pm every week", context: "capture.fresh.\(repetition).turn1",
        backend: "fallback_model_unavailable")
      XCTAssertEqual(app.buttons["capture-title"].label, "Call Alex")
      XCTAssertTrue(text("New reminder").exists)
      XCTAssertTrue(text("Tomorrow").exists)
      XCTAssertTrue(app.buttons["Add"].isEnabled)
      XCTAssertFalse(any("capture-added").exists, "A preview requires Add")
      sendAndSample(
        "How about 5pm?", context: "capture.fixed_history.\(repetition).turn2", backend: "rules")
      XCTAssertEqual(
        app.buttons["capture-title"].label, "Call Alex", "Preserve the full requested title")
      XCTAssertTrue(text("New reminder").exists, "Follow-up preserves reminder type")
      XCTAssertFalse(text("New alarm").exists)
      XCTAssertTrue(text("Tomorrow").exists, "Follow-up preserves the requested day")
      let time = app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS '17:00' OR label CONTAINS '5:00'")
      ).firstMatch
      XCTAssertTrue(time.exists, "Only the requested time changes")
      XCTAssertFalse(any("capture-added").exists)
      XCTAssertTrue(app.buttons["Add"].isEnabled)
      app.buttons["Add"].tap()
      XCTAssertTrue(any("capture-added").waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["capture-open"].exists)
      app.buttons["capture-undo"].tap()
      XCTAssertTrue(any("capture-undone").waitForExistence(timeout: 5))
      XCTAssertFalse(any("capture-added").exists)
      XCTAssertTrue(app.buttons["capture-add-again"].exists)
    }
  }

  /// n=3 local planning previews. Apply/Undo are correctness guards, not save-success latency evidence.
  func testPlanConfirmationFreshLaunchN3() {
    for repetition in 1...3 {
      freshAsk(journey: "plan", repetition: repetition)
      sendAndSample(
        "Can you plan my day?", context: "plan.fresh.\(repetition).turn1", backend: "rules")
      XCTAssertTrue(app.buttons["plan.apply"].isEnabled)
      XCTAssertTrue(text("Meetings stay fixed").exists)
      XCTAssertFalse(app.buttons["Add"].exists)
      XCTAssertFalse(any("ask-undo").exists, "Nothing has been applied before confirmation")
      let applied = app.staticTexts.containing(
        NSPredicate(format: "label BEGINSWITH 'Planned ' AND label ENDSWITH 'for today.'")
      ).firstMatch
      XCTAssertFalse(applied.exists)
      app.buttons["plan.apply"].tap()
      XCTAssertTrue(applied.waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["plan.apply"].exists)
      XCTAssertTrue(app.buttons["ask-undo"].isEnabled)
      app.buttons["ask-undo"].tap()
      XCTAssertTrue(any("ask-undo").waitForNonExistence(timeout: 5))
    }
  }
}
