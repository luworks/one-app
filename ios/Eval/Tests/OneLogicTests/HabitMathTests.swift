import XCTest
@testable import OneLogic

final class HabitMathTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    var today: Date { cal.startOfDay(for: Date(timeIntervalSince1970: 1_791_000_000)) }
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    func testStreakCountsBackFromToday() {
        XCTAssertEqual(HabitMath.streak([day(0), day(-1), day(-2), day(-4)], now: today, calendar: cal), 3)
    }

    func testStreakStillCountsWhenTodayNotCheckedYet() {
        XCTAssertEqual(HabitMath.streak([day(-1), day(-2)], now: today, calendar: cal), 2)
    }

    func testStreakBreaksAfterAMissedDay() {
        XCTAssertEqual(HabitMath.streak([day(-2), day(-3)], now: today, calendar: cal), 0)
    }

    func testEmpty() {
        XCTAssertEqual(HabitMath.streak([], now: today, calendar: cal), 0)
    }
}
