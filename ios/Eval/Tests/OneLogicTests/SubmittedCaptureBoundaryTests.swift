import Foundation
import XCTest

@testable import TodayCore

final class SubmittedCaptureBoundaryTests: XCTestCase {
  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
  }
  private var now: Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
  }

  func testTwoSeparateActionsNeedPreviewsInsteadOfASingleDirectWrite() {
    let text = "Tomorrow remind me to buy [QA] milk at 9am and call [QA] Alex at 3pm"
    XCTAssertEqual(ChatRouting.intent(text), .capture)
    XCTAssertTrue(ChatRouting.hasMultipleActions(text))
    XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar))
    XCTAssertFalse(
      OneOffReminderRequest.contextAllows(
        ConversationContext(turns: [.init(isUser: true, text: text, timestamp: now)])))
  }

  func testConjunctionInsideASingleObjectKeepsItsReminderAuthority() throws {
    let text = "Remind me to buy milk and bread tomorrow at 9am"
    XCTAssertFalse(ChatRouting.hasMultipleActions(text))
    let capture = try XCTUnwrap(OneOffReminderRequest.capture(text, now: now, calendar: calendar))
    XCTAssertEqual(capture.title, "buy milk and bread")
    XCTAssertEqual(capture.hour, 9)
  }

  func testMaterialDateCorrectionCannotSilentlySaveTheFirstDate() {
    let text = "提醒我周四，不对，周五下午两点买[QA]面包"
    XCTAssertTrue(ChatRouting.hasMaterialCorrection(text))
    XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar))
    XCTAssertFalse(
      OneOffReminderRequest.contextAllows(
        ConversationContext(turns: [.init(isUser: true, text: text, timestamp: now)])))
    XCTAssertFalse(ChatRouting.hasMaterialCorrection("Remind me to check the date tomorrow"))
    XCTAssertFalse(ChatRouting.hasMaterialCorrection("Actually make it every day"))
  }

  func testExplicitUntimedAlarmStaysAnUnreadyAlarmRatherThanAReminder() {
    for text in ["帮我设一个[QA]闹钟", "Set an alarm", "Wake me up"] {
      XCTAssertEqual(ChatRouting.intent(text), .capture, text)
      XCTAssertTrue(ChatRouting.requestsAlarm(text), text)
      let capture = CaptureConversation.parse(text, now: now, calendar: calendar)
      XCTAssertTrue(capture.ringsAsAlarm, text)
      XCTAssertNil(capture.hour, text)
      XCTAssertFalse(capture.isReadyToAdd, text)
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
  }

  func testReminderAboutSettingAnAlarmRemainsAReminder() throws {
    let text = "Remind me to set an alarm tomorrow at 9am"
    XCTAssertFalse(ChatRouting.requestsAlarm(text))
    let capture = CaptureConversation.parse(text, now: now, calendar: calendar)
    XCTAssertFalse(capture.ringsAsAlarm)
    XCTAssertEqual(capture.kind, .task)
  }
}
