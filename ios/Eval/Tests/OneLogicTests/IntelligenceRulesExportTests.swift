import Foundation
import TodayTestSupport
import XCTest

@testable import TodayCore

/// Measures pure production rules. This is not the app reducer, a model call, or a write test.
final class IntelligenceRulesExportTests: XCTestCase {
  func testFrozenDevelopmentRulesAndPreviewFollowups() throws {
    try exportRules(split: "development", fixtureName: "ai-chat-capability-eval.json")
  }

  func testFrozenHoldoutRulesAndPreviewFollowups() throws {
    try exportRules(split: "holdout", fixtureName: "intelligence-model-selection-holdout.json")
  }

  private func exportRules(split: String, fixtureName: String) throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    let fixture = repository.appendingPathComponent("tests/fixtures/" + fixtureName)
    let suite = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
    let cases = try XCTUnwrap(suite["cases"] as? [[String: Any]])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let now = try XCTUnwrap(formatter.date(from: "2026-10-28 09:00"))
    let existingItems = try [15, 16].map { hour in
      EditItem(
        id: "qa-visit-\(hour)00", type: "task", title: "[QA] dentist / follow-up / 复诊",
        start: try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)),
        minutes: 30, attendees: 0)
    }
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = calendar
    dayFormatter.timeZone = calendar.timeZone
    dayFormatter.locale = formatter.locale
    dayFormatter.dateFormat = "yyyy-MM-dd"
    var rows: [[String: Any]] = []
    var expectedCount = 0
    var identifiers = Set<String>()
    for entry in cases {
      let id = try XCTUnwrap(entry["id"] as? String)
      XCTAssertTrue(identifiers.insert(id).inserted, "Duplicate fixture id")
      let turns = try XCTUnwrap(entry["turns"] as? [[String: Any]])
      expectedCount += turns.count
      var pending: Capture?
      for (index, turn) in turns.enumerated() {
        let input = try XCTUnwrap(turn["input"] as? String)
        let started = Date()
        let ruleIntent = ChatRouting.intent(input)
        let direct = OneOffReminderRequest.capture(
          input, now: now, calendar: calendar, existingItems: { existingItems })
        let editEligible =
          direct == nil
          && Editing.looksLikeEdit(
            input, items: existingItems, now: now, calendar: calendar)
        var capture: Capture?
        var resolution = "new_parse"
        if let prior = pending {
          switch Dialogue.refine(prior, with: input, now: now, calendar: calendar) {
          case .updated(let value):
            capture = value
            resolution = "preview_refinement"
          case .needsTime: resolution = "needs_time"
          case .dismissed:
            pending = nil
            resolution = "dismissed"
          case .notARefinement: break
          }
        }
        if capture == nil && resolution == "new_parse" && ruleIntent != .conversation {
          capture = CaptureConversation.parse(input, now: now, calendar: calendar)
        }
        var output: [String: Any] = [
          "intent": ruleIntent == .conversation ? "chat" : "UNKNOWN",
          "reply": NSNull(), "title": NSNull(), "date": NSNull(), "time": NSNull(),
          "repeat": NSNull(), "weekdays": [], "duration_minutes": NSNull(),
          "target": NSNull(),
        ]
        if let value = capture, !editEligible {
          // An unsure route still has observable parser fields, but no resolved action.
          if ruleIntent == .capture || resolution == "preview_refinement" {
            pending = value
            output["intent"] =
              value.ringsAsAlarm ? "alarm" : (value.kind == .event ? "event" : "reminder")
          }
          output["title"] = value.title
          output["date"] = value.hasDay ? dayFormatter.string(from: value.day) as Any : NSNull()
          output["time"] =
            value.hour.map { String(format: "%02d:%02d", $0, value.minute) } as Any? ?? NSNull()
          output["duration_minutes"] = value.durationMinutes as Any? ?? NSNull()
          let repeatRule = value.repeatRule.flatMap(RepeatRule.init(rawValue:))
          if let repeatRule, case .weeklyOn(let days) = repeatRule {
            output["repeat"] = "weekly"
            output["weekdays"] = days
          } else {
            output["repeat"] = value.repeatRule ?? "once"
          }
        }
        var editObservation: Any = NSNull()
        if editEligible {
          let decision = Editing.decide(
            text: input, plan: nil, items: existingItems, now: now, calendar: calendar)
          output["intent"] =
            decision.op == .move ? "edit" : (decision.op == .clarify ? "clarify" : "UNKNOWN")
          output["target"] = decision.target as Any? ?? NSNull()
          if let start = decision.newStart {
            output["date"] = dayFormatter.string(from: start)
            output["time"] = String(
              format: "%02d:%02d", calendar.component(.hour, from: start),
              calendar.component(.minute, from: start))
          }
          editObservation =
            [
              "op": decision.op.rawValue, "reason": decision.reason,
              "needs_model": Editing.needsModel(
                input, items: existingItems, now: now, calendar: calendar),
            ] as [String: Any]
        }
        let row: [String: Any] = [
          "case": id, "turn": index, "input": input, "output": output,
          "rule_route": String(describing: ruleIntent), "resolution": resolution,
          "elapsed_ms": Date().timeIntervalSince(started) * 1000,
          "model_attempted": false, "writes": NSNull(), "product_gate": NSNull(),
          "rule_direct_submission_eligible": direct != nil,
          "edit_rule_decision": editObservation,
          "layer":
            "CaptureConversation.parse + Dialogue.refine + ChatRouting.intent + Editing.decide(plan:nil) + OneOffReminderRequest.capture",
          "limitations":
            "Pure rules with an open synthetic proposal across turns and two synthetic edit targets; no app reducer, model, save, or Undo. UNKNOWN is unresolved, never a successful model response.",
        ]
        rows.append(row)
      }
    }
    XCTAssertEqual(rows.count, expectedCount, "Every fixture turn must be observed")
    let result: [String: Any] = [
      "split": split, "fixture": fixtureName,
      "reference": "2026-10-28 09:00 America/Los_Angeles", "rows": rows,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    // XCTest can truncate a long stdout line; only the explicit file is complete evidence.
    if let path = ProcessInfo.processInfo.environment["AI_RULES_EVAL_OUTPUT"] {
      try data.write(to: URL(fileURLWithPath: path), options: [.withoutOverwriting])
      print("INTELLIGENCE_RULES observed=\(rows.count) bytes=\(data.count) output=\(path)")
    } else {
      print(
        "INTELLIGENCE_RULES observed=\(rows.count); set AI_RULES_EVAL_OUTPUT to retain full observations"
      )
    }
  }
}
