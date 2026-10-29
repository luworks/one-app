import XCTest

@testable import TodayCore

final class SavedReminderRefinementTests: XCTestCase {
  func testDailyFollowupsPreserveSavedTitleAndTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
    let saved = CaptureParser.parse(
      "Remind me to buy milk tomorrow at 3pm", now: now, calendar: calendar)
    for text in ["Actually make it every day.", "Make that reminder repeat every day at 3pm."] {
      let result = try XCTUnwrap(
        SavedReminderRefinement.preview(saved, text: text, now: now, calendar: calendar))
      XCTAssertEqual(result.title, saved.title)
      XCTAssertEqual(
        result.taskTiming(calendar: calendar).due, saved.taskTiming(calendar: calendar).due)
      XCTAssertEqual(result.repeatRule, RepeatRule.daily.rawValue)
      XCTAssertNil(saved.repeatRule)
    }
  }

  func testNewObligationAndConversationAreNotSavedEdits() {
    for text in [
      "Remind me to buy bread every day at 3pm", "I make it every day",
      "Make that reminder repeat every day and buy bread",
    ] {
      let saved = Capture(title: "buy milk", day: .now, hasDay: true, hour: 15)
      XCTAssertNil(
        SavedReminderRefinement.preview(saved, text: text, now: .now, calendar: .current))
    }
  }
}
