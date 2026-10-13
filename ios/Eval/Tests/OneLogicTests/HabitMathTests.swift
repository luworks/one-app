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

final class ReminderPlanTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFutureReminderFiresThenNags() {
        let fires = ReminderPlan.taskFires(reminder: t0.addingTimeInterval(600), now: t0)
        XCTAssertEqual(fires.map(\.isNag), [false, true, true, true])
        XCTAssertEqual(fires.last?.date, t0.addingTimeInterval(600 + 20 * 60))
    }

    func testPastReminderKeepsRemainingNagsOnly() {
        // Reminder was 7 minutes ago: the 5-minute nag has passed, 10 and 20 remain.
        let fires = ReminderPlan.taskFires(reminder: t0.addingTimeInterval(-7 * 60), now: t0)
        XCTAssertEqual(fires.count, 2)
        XCTAssertTrue(fires.allSatisfy(\.isNag))
    }

    func testSnoozePresets() {
        XCTAssertEqual(ReminderPlan.snoozed("SNOOZE_10", now: t0), t0.addingTimeInterval(600))
        XCTAssertEqual(ReminderPlan.snoozed("SNOOZE_60", now: t0), t0.addingTimeInterval(3600))
        XCTAssertNil(ReminderPlan.snoozed("DONE", now: t0))
    }
}

final class DayPlannerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: h, minute: m))! }

    func testFillsGapsAroundMeetingsInOrder() {
        let busy = [DateInterval(start: at(10), end: at(11)), DateInterval(start: at(12), end: at(13))]
        let plan = DayPlanner.plan([.init(id: 1, minutes: 45), .init(id: 2, minutes: 45), .init(id: 3, minutes: 30)],
                                   busy: busy, window: DateInterval(start: at(9, 3), end: at(18)), calendar: cal)
        // 9:05–9:50 fits before the 10:00 meeting; the next 45 min goes after it (+5 buffer); 30 min after that.
        XCTAssertEqual(plan.map(\.id), [1, 2, 3])
        XCTAssertEqual(plan[0].start, at(9, 5))
        XCTAssertEqual(plan[1].start, at(11, 5))
        XCTAssertEqual(plan[2].start, at(13, 5))
    }

    func testSkipsWhatDoesNotFit() {
        let plan = DayPlanner.plan([.init(id: 1, minutes: 120)], busy: [],
                                   window: DateInterval(start: at(17), end: at(18)), calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }
}

final class HabitReminderTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }

    func testSkipsCheckedInDaysAndPastTimes() {
        // 10:00 on the 12th; reminder at 9:00 has passed today; the 13th is already checked in.
        let fires = ReminderPlan.habitFires(checkins: [at(13, 0)], hour: 9, minute: 0, now: at(12, 10), days: 4, calendar: cal)
        XCTAssertEqual(fires, [at(14, 9), at(15, 9)])
    }

    func testTodayStillPendingIfLater() {
        let fires = ReminderPlan.habitFires(checkins: [], hour: 20, minute: 30, now: at(12, 10), days: 1, calendar: cal)
        XCTAssertEqual(fires, [at(12, 20, 30)])
    }
}
