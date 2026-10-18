import XCTest
import CryptoKit
@testable import OneLogic

/// Actual pure production fallback observations. UI gates, writes, EventKit and FM remain unmeasured.
final class RecurringReminderExportTests: XCTestCase {
    func testExportDevelopmentRecurringObservations() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["AI_RECURRING_EVAL_FIXTURES"], let output = env["AI_RECURRING_EVAL_OUTPUT"] else {
            throw XCTSkip("Set recurring fixture and canonical evidence directory to export actual observations")
        }
        let suite = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let cases = try XCTUnwrap(suite["cases"] as? [[String: Any]])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: suite["timeZone"] as? String ?? ""))
        let date = DateFormatter()
        date.calendar = cal; date.timeZone = cal.timeZone; date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let now = try XCTUnwrap(date.date(from: suite["now"] as? String ?? ""))
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        for entry in cases where entry["split"] as? String == "development" {
            let id = try XCTUnwrap(entry["id"] as? String)
            let turns = try XCTUnwrap(entry["turns"] as? [[String: Any]])
            var users: [(isUser: Bool, text: String)] = []
            var pending: Capture?
            for (index, turn) in turns.enumerated() {
                let input = try XCTUnwrap(turn["input"] as? String)
                let intent = ChatRouting.intent(input)
                var route = "conversation", action = "chat"
                var shown: Capture?
                if let result = CaptureConversation.resolve(input, context: ConversationContext(users), pending: pending, now: now, calendar: cal) {
                    route = "capture"; action = pending == nil ? "create" : "revise_preview"; shown = result
                } else if intent != .conversation {
                    if let old = pending, case .updated(let result) = Dialogue.refine(old, with: input, now: now, calendar: cal) {
                        route = "capture"; action = "revise_preview"; shown = result
                    } else if intent == .capture {
                        shown = CaptureConversation.parse(input, now: now, calendar: cal)
                        route = "capture"; action = "create"
                    } else { route = "clarify"; action = "clarify" }
                }
                if let capture = shown {
                    shown = await CaptureTitleRefinement.refine(capture, source: input, available: false) { _ in
                        XCTFail("The fallback exporter must not invoke a model"); return nil
                    }
                    pending = shown
                }
                var items: [[String: Any]] = []
                if let c = shown {
                    var recurrence: Any = NSNull()
                    if let rule = c.repeatRule.flatMap(RepeatRule.init(rawValue:)) {
                        let days: [Int]?
                        switch rule {
                        case .weeklyOn(let selected): days = selected
                        case .weekdays: days = [2, 3, 4, 5, 6]
                        case .weekly: days = [cal.component(.weekday, from: c.day)]
                        default: days = nil
                        }
                        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
                        recurrence = days.map { selected in "weekly:" + [2, 3, 4, 5, 6, 7, 1].filter { selected.contains($0) }.map { names[$0 - 1] }.joined(separator: ",") } ?? rule.rawValue
                    }
                    items.append(["kind": c.ringsAsAlarm ? "alarm" : c.kind.rawValue, "title": c.title,
                                  "notes": c.notes as Any? ?? NSNull(),
                                  "day": cal.dateComponents([.day], from: cal.startOfDay(for: now), to: c.day).day as Any? ?? NSNull(),
                                  "time": c.hour.map { String(format: "%02d:%02d", $0, c.minute) } as Any? ?? NSNull(),
                                  "repeat": recurrence])
                }
                // Omit unobserved gates/write counts; null would mean an observed value in this scorer.
                let out: [String: Any] = ["route": route, "intent": action, "items": items]
                let raw: [String: Any] = ["backend": "production-pure-routing-context-parser-dialogue", "modelInvoked": false,
                                          "appSHA": env["AI_RECURRING_EVAL_SHA"] ?? "working-tree", "input": input, "out": out,
                                          "limitations": "Host seam; UI gate, local/Apple writes and Foundation Models unmeasured. Unsure is reported clarify without simulating a model. Conversation items describe newly shown proposals only."]
                let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
                let artifact = directory.appendingPathComponent("\(id)-turn-\(index).json")
                try bytes.write(to: artifact)
                rows.append(["caseId": id, "turn": index, "out": out,
                             "artifact": ["path": artifact.path, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]])
                users.append((true, input))
            }
        }
        let observations: [String: Any] = ["evidence": "Actual host fallback content; reserved validation not executed; FM/UI/persistence unmeasured", "rows": rows]
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("observations.json"))
    }
}
