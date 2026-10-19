import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

final class RepeatWeekdayTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 30)
    -> Date
  {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  func testLegacyRawValuesAndSingleStringCodableStayUnchanged() throws {
    let values = ["daily", "weekdays", "weekly", "monthly", "yearly"]
    XCTAssertEqual(RepeatRule.allCases.map(\.rawValue), values)
    for raw in values {
      let rule = try XCTUnwrap(RepeatRule(rawValue: raw))
      let wire = Data("\"\(raw)\"".utf8)
      XCTAssertEqual(rule.rawValue, raw)
      XCTAssertEqual(try JSONEncoder().encode(rule), wire)
      XCTAssertEqual(try JSONDecoder().decode(RepeatRule.self, from: wire), rule)
    }
  }

  func testCustomDaysCanonicalizeAndRoundTripAsOneString() throws {
    let rule = RepeatRule.weeklyOn([6, 1, 6])
    XCTAssertEqual(rule.rawValue, "weekly:1,6")
    XCTAssertEqual(RepeatRule(rawValue: "weekly:6,1,6"), .weeklyOn([1, 6]))
    XCTAssertEqual(rule, .weeklyOn([1, 6]))
    XCTAssertEqual(Set([rule, .weeklyOn([1, 6])]).count, 1)
    let wire = Data("\"weekly:1,6\"".utf8)
    XCTAssertEqual(try JSONEncoder().encode(rule), wire)
    XCTAssertEqual(try JSONDecoder().decode(RepeatRule.self, from: wire), rule)
    XCTAssertEqual(
      try JSONDecoder().decode(RepeatRule.self, from: Data("\"weekly:6,1,6\"".utf8)), rule)
    XCTAssertNotEqual(RepeatRule.weeklyOn([6]), .weekly)
    XCTAssertEqual(RepeatRule(rawValue: "weekly:7"), .weeklyOn([7]))
  }

  func testMalformedDaysAreRejectedWithoutPartialRecovery() {
    for raw in [
      "", "Weekly", "weekly:", "weekly:0", "weekly:8", "weekly:-1", "weekly:+1",
      "weekly:01", "weekly:1,", "weekly:,1", "weekly:1,,6", "weekly:1,8",
      "weekly:1, 6", "weekly:1.0", "weekly:１", "weekly:1️", "weekly:1;6", "weekly:1\n",
    ] {
      XCTAssertNil(RepeatRule(rawValue: raw), raw)
      XCTAssertThrowsError(
        try JSONDecoder().decode(RepeatRule.self, from: JSONEncoder().encode(raw)), raw)
    }
    for wire in ["[1,6]", "{\"weeklyOn\":[1,6]}", "null", "6"] {
      XCTAssertThrowsError(try JSONDecoder().decode(RepeatRule.self, from: Data(wire.utf8)))
    }
  }

  func testPickerKeepsCustomSelectionAndLabelNamesEveryDay() {
    let rule = RepeatRule.weeklyOn([1, 6, 6])
    XCTAssertEqual(rule.label, "Every Fri, Sun")
    XCTAssertEqual(RepeatRule.weeklyOn([7]).label, "Every Sat")
    XCTAssertEqual(RepeatRule.choices(including: nil), RepeatRule.allCases)
    XCTAssertEqual(RepeatRule.choices(including: .weekly), RepeatRule.allCases)
    XCTAssertEqual(RepeatRule.choices(including: rule), RepeatRule.allCases + [rule])
  }

  func testNextChoosesEarliestSelectedDayStrictlyAfterIncludingWeekWrap() {
    let rule = RepeatRule.weeklyOn([1, 6, 6])
    let thursday = date(2026, 10, 15)
    let friday = date(2026, 10, 16)
    let sunday = date(2026, 10, 18)
    XCTAssertEqual(rule.next(after: thursday, calendar: calendar), friday)
    XCTAssertEqual(rule.next(after: friday, calendar: calendar), sunday)
    XCTAssertEqual(rule.next(after: sunday, calendar: calendar), date(2026, 10, 23))
    XCTAssertEqual(
      RepeatRule.weeklyOn([6]).next(after: friday, calendar: calendar), date(2026, 10, 23))
    XCTAssertGreaterThan(rule.next(after: sunday, calendar: calendar), sunday)
  }

  func testNextKeepsLocalClockAcrossSpringAndFallDST() {
    let rule = RepeatRule.weeklyOn([1, 6])
    for (start, expected, hours) in [
      (date(2026, 3, 6), date(2026, 3, 8), 47.0),
      (date(2026, 10, 30), date(2026, 11, 1), 49.0),
    ] {
      let next = rule.next(after: start, calendar: calendar)
      XCTAssertEqual(next, expected)
      XCTAssertEqual(next.timeIntervalSince(start), hours * 3600, accuracy: 0.001)
      XCTAssertEqual(calendar.component(.hour, from: next), 9)
      XCTAssertEqual(calendar.component(.minute, from: next), 30)
    }
    // Crossing a skipped 02:30 on an unselected Sunday must not shift Monday's clock.
    XCTAssertEqual(
      RepeatRule.weeklyOn([2]).next(after: date(2026, 3, 6, 2), calendar: calendar),
      date(2026, 3, 9, 2))
  }
}
