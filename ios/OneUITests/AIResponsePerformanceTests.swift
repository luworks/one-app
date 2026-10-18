import XCTest

/// Simulator fallback baseline only. Each repetition restores identical fixture and chat history.
/// XCTest interaction time is never used as AI latency; raw app-side monotonic endpoints are retained.
final class AIResponsePerformanceTests: XCTestCase {
    private var app: XCUIApplication!
    private let stages: Set<String> = [
        "ai_send_to_feedback_layout", "ai_send_to_first_response_ready", "ai_send_to_full_response_ready",
        "ai_ready_to_response_layout", "ai_turn_to_response_layout"
    ]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-performanceTrace", "-uiTestingNow", "09:41"]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    private func freshAsk(journey: String, repetition: Int) {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Ask AI or add anything"].waitForExistence(timeout: 10))
        app.buttons["Ask AI or add anything"].tap()
        let input = app.textFields["Ask AI or add anything"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        // Ask's destination modifier exposes its own report while the modal hides the presenter.
        let reports = app.staticTexts.matching(identifier: "performance.trace")
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reports.allElementsBoundByIndex.contains {
                $0.label.contains(";name=page.ai;") && $0.label.contains(";route=ai;")
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 10), .completed, "Ask content layout endpoint")
        guard let report = reports.allElementsBoundByIndex.map(\.label).first(where: {
            $0.contains(";name=page.ai;") && $0.contains(";route=ai;")
        }) else { XCTFail("Missing modal page.ai report"); return }
        let values = fields(report)
        guard let start = UInt64(values["start_ns"] ?? ""), let end = UInt64(values["end_ns"] ?? ""),
              let ms = Double(values["ms"] ?? "") else {
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
        print("PERF_CONTEXT v=1;journey=\(journey);rep=\(repetition);launch=process_cold_os_warm;chat=fresh;store=in_memory;fixture=today-dataset.json;clock=09:41;prewarm=default;backend_track=simulator_fallback;wall_epoch=\(Date.now.timeIntervalSince1970)")
    }

    private var history: String { app.staticTexts["performance.ai.history"].firstMatch.label }

    private func fields(_ sample: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: sample.split(separator: ";").compactMap { part -> (String, String)? in
            let pair = part.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
    }

    private func rows(_ history: String) -> [String] {
        history.components(separatedBy: "\n").filter { $0.hasPrefix("v=1;name=ai_") }
    }

    /// Wait for all reports from the one new turn, including feedback that may arrive after ready.
    @discardableResult
    private func sendAndSample(_ text: String, context: String, backend: String) -> [String] {
        let previous = Set(rows(history).compactMap { fields($0)["turn"] })
        let field = app.textFields["Ask AI or add anything"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
        var samples: [String] = []
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let fresh = rows(history).filter { !previous.contains(fields($0)["turn"] ?? "") }
            guard let token = fresh.last.flatMap({ fields($0)["turn"] }) else { return false }
            samples = fresh.filter { fields($0)["turn"] == token }
            return Set(samples.compactMap { fields($0)["name"] }) == stages
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed, "Missing app-side turn endpoint: \(context)")
        XCTAssertEqual(samples.count, stages.count, "Exactly one raw sample per keyed stage")
        var starts: [String: UInt64] = [:]
        var ends: [String: UInt64] = [:]
        for sample in samples {
            let values = fields(sample)
            guard let start = UInt64(values["start_ns"] ?? ""), let end = UInt64(values["end_ns"] ?? ""),
                  let ms = Double(values["ms"] ?? ""), let name = values["name"] else {
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
        XCTAssertEqual(ends["ai_send_to_first_response_ready"], ends["ai_send_to_full_response_ready"], "No streaming: one emitted result")
        XCTAssertEqual(starts["ai_ready_to_response_layout"], ends["ai_send_to_full_response_ready"])
        XCTAssertEqual(ends["ai_ready_to_response_layout"], ends["ai_turn_to_response_layout"])
        let attachment = XCTAttachment(string: "context=\(context)\n" + samples.joined(separator: "\n"))
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
            sendAndSample("Hello", context: "conversation.fresh.\(repetition).turn1", backend: "fallback_model_unavailable")
            XCTAssertTrue(text("What's on your mind?").exists)
            XCTAssertFalse(app.buttons["Add"].exists)
            XCTAssertFalse(app.buttons["capture-add-all"].exists)
            XCTAssertFalse(any("change-card").exists)
            XCTAssertFalse(app.buttons["plan.apply"].exists)
        }
    }

    /// n=3 identical two-turn journeys. Follow-up samples have exactly one prior request, never growing history.
    func testCaptureFollowupConfirmationFreshLaunchN3() {
        for repetition in 1...3 {
            freshAsk(journey: "capture_followup", repetition: repetition)
            sendAndSample("Call Alex tomorrow at 3pm", context: "capture.fresh.\(repetition).turn1", backend: "fallback_model_unavailable")
            XCTAssertEqual(app.buttons["capture-title"].label, "Call Alex")
            XCTAssertTrue(text("New reminder").exists)
            XCTAssertTrue(text("Tomorrow").exists)
            XCTAssertTrue(app.buttons["Add"].isEnabled)
            XCTAssertFalse(any("capture-added").exists, "A preview requires Add")
            sendAndSample("How about 5pm?", context: "capture.fixed_history.\(repetition).turn2", backend: "rules")
            XCTAssertEqual(app.buttons["capture-title"].label, "Call Alex", "Preserve the full requested title")
            XCTAssertTrue(text("New reminder").exists, "Follow-up preserves reminder type")
            XCTAssertFalse(text("New alarm").exists)
            XCTAssertTrue(text("Tomorrow").exists, "Follow-up preserves the requested day")
            let time = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '17:00' OR label CONTAINS '5:00'")).firstMatch
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
            sendAndSample("Can you plan my day?", context: "plan.fresh.\(repetition).turn1", backend: "rules")
            XCTAssertTrue(app.buttons["plan.apply"].isEnabled)
            XCTAssertTrue(text("Meetings stay fixed").exists)
            XCTAssertFalse(app.buttons["Add"].exists)
            XCTAssertFalse(any("ask-undo").exists, "Nothing has been applied before confirmation")
            let applied = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Planned ' AND label ENDSWITH 'for today.'")).firstMatch
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
