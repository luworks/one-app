import XCTest

@testable import TodayCore

/// The top bar's month label: one month, a span across months or years, the short fallback, other locales.
final class MonthLabelTests: XCTestCase {
  private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()

  private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
  }

  /// ICU may put thin or no-break spaces around the dash; compare with plain spaces.
  private func label(
    _ first: Date, _ last: Date, _ length: MonthLabel.Length, locale: String = "en_US"
  ) -> String {
    MonthLabel.text(
      first: first, last: last, length: length, calendar: cal, locale: Locale(identifier: locale)
    )
    .replacingOccurrences(of: "\u{2009}", with: " ")
    .replacingOccurrences(of: "\u{202F}", with: " ")
    .replacingOccurrences(of: "\u{00A0}", with: " ")
  }

  func testOneMonth() {
    let day = date(2026, 10, 26)
    XCTAssertEqual(label(day, day, .full), "October 2026")
    XCTAssertEqual(label(day, day, .short), "Oct 2026")
    XCTAssertEqual(label(date(2026, 10, 1), date(2026, 10, 31), .full), "October 2026")
  }

  func testDaysAcrossTwoMonths() {
    XCTAssertEqual(label(date(2026, 10, 30), date(2026, 11, 1), .full), "Oct – Nov 2026")
    XCTAssertEqual(label(date(2026, 10, 30), date(2026, 11, 1), .short), "Oct – Nov")
  }

  func testDaysAcrossTwoYears() {
    XCTAssertEqual(label(date(2026, 12, 31), date(2027, 1, 2), .full), "Dec 2026 – Jan 2027")
    XCTAssertEqual(label(date(2026, 12, 31), date(2027, 1, 2), .short), "Dec – Jan")
  }

  func testOrderDoesNotMatter() {
    XCTAssertEqual(
      label(date(2026, 11, 1), date(2026, 10, 30), .full),
      label(date(2026, 10, 30), date(2026, 11, 1), .full))
  }

  func testFollowsTheLocale() {
    let day = date(2026, 10, 26)
    XCTAssertEqual(label(day, day, .full, locale: "de_DE"), "Oktober 2026")
    XCTAssertEqual(label(day, day, .full, locale: "ja_JP"), "2026年10月")
  }
}
