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

final class RecurrenceTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)

    func testWeeklyOccurrencesInAMonth() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
        let month = DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!,
                                 end: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        let dates = Recurrence.occurrences(start: start, duration: 3600, rule: .weekly, in: month, calendar: cal)
        XCTAssertEqual(dates.map { cal.component(.day, from: $0) }, [5, 12, 19, 26])
    }

    func testOneOffOnlyWhenOverlapping() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 23))!
        let nextDay = DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 6))!, duration: 86400)
        // 2-hour event crosses midnight, so it shows on the next day too.
        XCTAssertEqual(Recurrence.occurrences(start: start, duration: 7200, rule: nil, in: nextDay, calendar: cal).count, 1)
        XCTAssertEqual(Recurrence.occurrences(start: start, duration: 1800, rule: nil, in: nextDay, calendar: cal).count, 0)
    }
}

final class HabitStatsTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 8))! }

    func testWeekCountStartsMonday() {
        // Wed Oct 14; week is Mon 12 – Sun 18. Sun 11 belongs to the previous week.
        XCTAssertEqual(HabitMath.weekCount([d(11), d(12), d(14), d(14)], now: d(14), calendar: cal), 2)
    }

    func testBestStreak() {
        XCTAssertEqual(HabitMath.bestStreak([d(1), d(2), d(3), d(5), d(6)], calendar: cal), 3)
        XCTAssertEqual(HabitMath.bestStreak([], calendar: cal), 0)
    }
}
