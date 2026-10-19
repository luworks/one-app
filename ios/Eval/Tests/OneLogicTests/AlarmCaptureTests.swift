import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// Alarm sentences: relative times in every common form, and a clean alarm name.
final class AlarmCaptureTests: XCTestCase {
  let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()
  lazy var now = cal.date(
    from: DateComponents(year: 2026, month: 10, day: 16, hour: 22, minute: 12))!

  private func time(_ text: String) -> (Int?, Int) {
    let c = CaptureParser.parse(text, now: now, calendar: cal)
    return (c.hour, c.minute)
  }

  func testRelativeMinutesInEveryForm() {
    for text in [
      "alarm in 30 minutes", "Adding alarm after 30 minutes remind me to walking",
      "walk 30 minutes later", "walk 30 minutes from now", "30分钟后去散步",
    ] {
      let (h, m) = time(text)
      XCTAssertEqual(h, 22, text)
      XCTAssertEqual(m, 42, text)
    }
  }

  func testAlarmLabelDropsTheInstructionWords() {
    XCTAssertEqual(CaptureParser.alarmLabel("Adding alarm after remind me to walking"), "Walking")
    XCTAssertEqual(CaptureParser.alarmLabel("Set an alarm for gym"), "Gym")
    XCTAssertEqual(CaptureParser.alarmLabel("wake me up"), "Alarm")
    XCTAssertEqual(CaptureParser.alarmLabel("起床"), "起床")
    XCTAssertEqual(CaptureParser.alarmLabel("帮我定个闹钟去开会"), "去开会")
  }

  func testBecomingAnAlarmCleansTheTitleAndTheSummarySaysAlarm() {
    var c = CaptureParser.parse(
      "Adding alarm after 30 minutes remind me to walking", now: now, calendar: cal)
    c.ringsAsAlarm = true
    XCTAssertEqual(c.title, "Walking")
    XCTAssertTrue(c.summary.hasPrefix("Alarm "), c.summary)
    XCTAssertFalse(c.summary.contains("Rings as alarm"))
  }
}
