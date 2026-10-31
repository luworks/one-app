import Foundation
import XCTest

@testable import TodayCore

final class CalendarMoveTimingTests: XCTestCase {
  func testAllDayBecomesOneHourRegardlessOfOriginalLength() {
    let old = Date(timeIntervalSince1970: 100_000)
    let moved = old.addingTimeInterval(90_000)
    XCTAssertEqual(
      CalendarMoveTiming.end(
        newStart: moved, oldStart: old,
        oldEnd: old.addingTimeInterval(3 * 86_400), wasAllDay: true), moved.addingTimeInterval(3600)
    )
  }

  func testTimedMovePreservesDurationAndRejectsInvalidDuration() {
    let old = Date(timeIntervalSince1970: 100_000)
    let moved = old.addingTimeInterval(90_000)
    XCTAssertEqual(
      CalendarMoveTiming.end(
        newStart: moved, oldStart: old,
        oldEnd: old.addingTimeInterval(2700), wasAllDay: false), moved.addingTimeInterval(2700))
    XCTAssertNil(
      CalendarMoveTiming.end(
        newStart: moved, oldStart: old,
        oldEnd: old, wasAllDay: false))
  }
}
