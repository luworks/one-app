import XCTest

@testable import TodayCore

final class RecurringUploadDateTests: XCTestCase {
  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return c
  }
  private var now: Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 8, minute: 30))!
  }

  func testOpenUndatedRepeatingReminderUploadsDatedToday() {
    XCTAssertEqual(
      RecurringUploadDate.plan(repeats: true, due: nil, isDone: false, today: now, calendar: cal),
      .uploadDated(cal.startOfDay(for: now)))
  }

  func testFinishedUndatedRepeatingReminderStaysLocal() {
    XCTAssertEqual(
      RecurringUploadDate.plan(repeats: true, due: nil, isDone: true, today: now, calendar: cal),
      .keepLocal)
  }

  func testDatedOrOneOffRemindersUploadUnchanged() {
    XCTAssertEqual(
      RecurringUploadDate.plan(repeats: true, due: now, isDone: false, today: now, calendar: cal),
      .upload)
    XCTAssertEqual(
      RecurringUploadDate.plan(repeats: false, due: nil, isDone: false, today: now, calendar: cal),
      .upload)
    XCTAssertEqual(
      RecurringUploadDate.plan(repeats: false, due: nil, isDone: true, today: now, calendar: cal),
      .upload)
  }
}
