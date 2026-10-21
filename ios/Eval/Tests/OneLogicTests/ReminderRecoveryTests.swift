import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

final class ReminderRecoveryTests: XCTestCase {
  private struct Case: Decodable {
    let name: String
    let text: String
    let history: [[String]]?
    let capture: Bool?
    let title: String?
    let day: Int?
    let repeatRule: String?
  }

  func testBilingualActionableRecoveryFixtures() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("../../../../tests/fixtures/ai-reminder-recovery-cases.json")
      .standardized
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: root))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))!
    for entry in cases {
      let context = ConversationContext((entry.history ?? []).map { ($0[0] == "user", $0[1]) })
      let recovered = CaptureConversation.resolve(
        entry.text, context: context, pending: nil, now: now, calendar: calendar)
      let result =
        recovered
        ?? (ChatRouting.intent(entry.text) == .capture
          ? CaptureConversation.parse(entry.text, now: now, calendar: calendar) : nil)
      guard entry.capture != false else {
        XCTAssertNil(result, entry.name)
        continue
      }
      let preview = try XCTUnwrap(
        result, entry.name + ": must produce an actionable Capture, not a chat reply")
      XCTAssertEqual(preview.title, entry.title, entry.name)
      XCTAssertEqual(preview.kind, .task, entry.name)
      XCTAssertFalse(preview.ringsAsAlarm, entry.name)
      XCTAssertNil(preview.hour, entry.name + ": never invent a time")
      XCTAssertTrue(preview.hasDay, entry.name)
      XCTAssertTrue(
        preview.isReadyToAdd, entry.name + ": date-only reminders do not need an alarm time")
      XCTAssertEqual(preview.repeatRule, entry.repeatRule, entry.name)
      XCTAssertEqual(
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: preview.day).day,
        entry.day, entry.name)
      XCTAssertEqual(preview.taskTiming.due, preview.day, entry.name)
    }
  }
}
