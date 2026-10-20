import Foundation
import XCTest

@testable import TodayCore

final class SnoozeSelectionTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }

  func testRelativeHourStartsAtTapAfterSheetWaits() throws {
    let opened = Date(timeIntervalSince1970: 1_792_530_000)
    let tapped = opened.addingTimeInterval(1800)
    let until = try XCTUnwrap(SnoozeSelection.inOneHour.resolve(now: tapped, calendar: calendar))
    XCTAssertEqual(until.timeIntervalSince(tapped), 3600)
    XCTAssertEqual(until.timeIntervalSince(opened), 5400)
  }

  func testTomorrowMorningUsesTapDayAcrossMidnightAndDST() throws {
    let opened = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 55)))
    let tapped = opened.addingTimeInterval(600)
    let until = try XCTUnwrap(
      SnoozeSelection.tomorrowMorning.resolve(now: tapped, calendar: calendar))
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: until)
    XCTAssertEqual(parts, DateComponents(year: 2026, month: 11, day: 2, hour: 9, minute: 0))
  }

  func testCustomChoiceBecomingPastIsRejectedAndCanBeCorrected() {
    let opened = Date(timeIntervalSince1970: 1_792_530_000)
    let selected = opened.addingTimeInterval(60)
    XCTAssertEqual(
      SnoozeSelection.custom(selected).resolve(now: opened, calendar: calendar), selected)
    XCTAssertNil(SnoozeSelection.custom(selected).resolve(now: selected, calendar: calendar))
    let committed = selected.addingTimeInterval(1)
    XCTAssertNil(SnoozeSelection.custom(selected).resolve(now: committed, calendar: calendar))
    let corrected = committed.addingTimeInterval(3600)
    XCTAssertEqual(
      SnoozeSelection.custom(corrected).resolve(now: committed, calendar: calendar), corrected)
    XCTAssertNil(
      SnoozeSelection.custom(Date(timeIntervalSinceReferenceDate: .infinity)).resolve(
        now: committed, calendar: calendar))
  }
}
