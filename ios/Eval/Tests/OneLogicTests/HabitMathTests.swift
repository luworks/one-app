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

final class RepeatRuleTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDailyKeepsTime() {
        XCTAssertEqual(RepeatRule.daily.next(after: date(2026, 10, 12, 15), calendar: cal), date(2026, 10, 13, 15))
    }

    func testWeekdaysSkipsWeekend() {
        // Fri Oct 16 → Mon Oct 19
        XCTAssertEqual(RepeatRule.weekdays.next(after: date(2026, 10, 16), calendar: cal), date(2026, 10, 19))
    }

    func testMonthlyClampsToMonthEnd() {
        XCTAssertEqual(RepeatRule.monthly.next(after: date(2026, 1, 31), calendar: cal), date(2026, 2, 28))
    }

    func testWeekly() {
        XCTAssertEqual(RepeatRule.weekly.next(after: date(2026, 10, 12), calendar: cal), date(2026, 10, 19))
    }
}
