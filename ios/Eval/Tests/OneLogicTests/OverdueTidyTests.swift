import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

final class OverdueTidyTests: XCTestCase {
  let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()
  // Friday 16 Oct 2026, 10:00
  lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10))!

  private func daysAgo(_ n: Int, hour: Int = 0) -> Date {
    cal.date(
      byAdding: .day, value: -n, to: cal.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
  }

  private func parts(_ d: Date?) -> DateComponents? {
    d.map { cal.dateComponents([.month, .day, .hour, .minute], from: $0) }
  }

  func testFlaggedFirstThenMostRecentThreeADay() {
    let items =
      (1...8).map { OverdueTidy.Item(id: $0, due: daysAgo($0)) } + [
        OverdueTidy.Item(id: 99, due: daysAgo(20), flagged: true)
      ]
    let s = OverdueTidy.suggest(items, now: now, calendar: cal)
    XCTAssertEqual(s.map(\.id), [99, 1, 2, 3, 4, 5, 6, 7, 8])
    XCTAssertEqual(
      s.map(\.choice),
      [.today, .today, .today, .tomorrow, .tomorrow, .tomorrow, .nextWeek, .nextWeek, .nextWeek])
  }

  func testStaleOnesLoseTheirDateUnlessFlaggedOrRepeating() {
    let items = [
      OverdueTidy.Item(id: 1, due: daysAgo(45)),
      OverdueTidy.Item(id: 2, due: daysAgo(45), flagged: true),
      OverdueTidy.Item(id: 3, due: daysAgo(45), repeats: true),
    ]
    let s = Dictionary(
      uniqueKeysWithValues: OverdueTidy.suggest(items, now: now, calendar: cal).map {
        ($0.id, $0.choice)
      })
    XCTAssertEqual(s[1], .noDate)
    XCTAssertEqual(s[2], .today)
    XCTAssertEqual(s[3], .today)
    XCTAssertFalse(OverdueTidy.choices(repeats: true).contains(.noDate), "a repeat needs a date")
  }

  func testNewDueKeepsTheTimeOfDay() {
    let timed = daysAgo(3, hour: 15)
    XCTAssertEqual(
      parts(OverdueTidy.newDue(timed, .today, now: now, calendar: cal)),
      DateComponents(month: 10, day: 16, hour: 15, minute: 0))
    XCTAssertEqual(
      parts(OverdueTidy.newDue(timed, .tomorrow, now: now, calendar: cal)),
      DateComponents(month: 10, day: 17, hour: 15, minute: 0))
    XCTAssertEqual(
      parts(OverdueTidy.newDue(timed, .nextWeek, now: now, calendar: cal)),
      DateComponents(month: 10, day: 19, hour: 15, minute: 0))
    XCTAssertEqual(
      parts(OverdueTidy.newDue(daysAgo(3), .today, now: now, calendar: cal)),
      DateComponents(month: 10, day: 16, hour: 0, minute: 0),
      "a date-only reminder stays date-only")
    XCTAssertNil(OverdueTidy.newDue(timed, .noDate, now: now, calendar: cal))
    XCTAssertEqual(OverdueTidy.newDue(timed, .keep, now: now, calendar: cal), timed)
  }

  func testRequests() {
    XCTAssertTrue(OverdueTidy.isRequest("Tidy overdue"))
    XCTAssertTrue(OverdueTidy.isRequest("帮我整理过期的提醒"))
    XCTAssertFalse(OverdueTidy.isRequest("What's overdue?"))
  }

  func testCountedAndChineseRequests() {
    for text in ["Tidy 3 overdue", "tidy my 12 overdue reminders", "Tidy up 2 overdue", "整理3条过期提醒"]
    {
      XCTAssertTrue(OverdueTidy.isRequest(text), text)
    }
    for text in ["Tidy my desk", "I have 3 overdue things to do", "整理房间"] {
      XCTAssertFalse(OverdueTidy.isRequest(text), text)
    }
  }
}
