import XCTest

@testable import TodayCore

final class MonthLabelTests: XCTestCase {
  func testCurrentMonthRollsOverInLocalTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let boundary = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
    let locale = Locale(identifier: "en_US")
    XCTAssertEqual(
      MonthLabel.text(
        now: boundary.addingTimeInterval(-1), calendar: calendar,
        locale: locale), "Dec 2026")
    XCTAssertEqual(MonthLabel.text(now: boundary, calendar: calendar, locale: locale), "Jan 2027")
    var utc = calendar
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertEqual(
      MonthLabel.text(
        now: boundary.addingTimeInterval(-1), calendar: utc,
        locale: locale), "Jan 2027")
    XCTAssertEqual(
      MonthLabel.text(
        now: boundary, length: .full, calendar: calendar,
        locale: locale), "January 2027")
    XCTAssertEqual(
      MonthLabel.text(
        now: boundary, calendar: calendar,
        locale: Locale(identifier: "ja_JP")), "2027年1月")
  }
}
