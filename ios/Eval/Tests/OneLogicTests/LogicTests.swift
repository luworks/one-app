import XCTest
@testable import OneLogic

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

final class ListNameTests: XCTestCase {
    func testStripsOrderingNumber() {
        XCTAssertEqual(ListName.display("01 Work"), "Work")
        XCTAssertEqual(ListName.display("00 收件箱"), "收件箱")
        XCTAssertEqual(ListName.display("Home"), "Home")
        XCTAssertEqual(ListName.display("2026 plans"), "2026 plans")
    }
}

final class AlarmPlanTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US")
        return c
    }
    /// Oct 12 2026 is a Monday.
    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    func testRepeatLabels() {
        XCTAssertEqual(AlarmPlan.repeatLabel(weekdays: [], calendar: cal), "Once")
        XCTAssertEqual(AlarmPlan.repeatLabel(weekdays: [1, 2, 3, 4, 5, 6, 7], calendar: cal), "Every day")
        XCTAssertEqual(AlarmPlan.repeatLabel(weekdays: [2, 3, 4, 5, 6], calendar: cal), "Weekdays")
        XCTAssertEqual(AlarmPlan.repeatLabel(weekdays: [7, 1], calendar: cal), "Weekends")
        XCTAssertEqual(AlarmPlan.repeatLabel(weekdays: [4, 2], calendar: cal), "Mon, Wed")
    }

    func testOneTimeAlarmRingsTodayIfStillAhead_elseTomorrow() {
        XCTAssertEqual(AlarmPlan.nextFire(hour: 18, minute: 0, weekdays: [], after: at(12, 9, 41), calendar: cal), at(12, 18, 0))
        XCTAssertEqual(AlarmPlan.nextFire(hour: 7, minute: 0, weekdays: [], after: at(12, 9, 41), calendar: cal), at(13, 7, 0))
    }

    func testWeekdayAlarmSkipsTheWeekend() {
        // Friday 9:41 → 7:00 alarm on weekdays next rings Monday.
        XCTAssertEqual(AlarmPlan.nextFire(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], after: at(16, 9, 41), calendar: cal), at(19, 7, 0))
    }

    func testClockRepeatWording() {
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [], calendar: cal), "Never")
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [1, 2, 3, 4, 5, 6, 7], calendar: cal), "Every day")
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [2, 3, 4, 5, 6], calendar: cal), "Weekdays")
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [1, 7], calendar: cal), "Weekends")
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [2], calendar: cal), "Every Monday")
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [4, 2], calendar: cal), "Every Mon, Wed")
        // Sunday-first calendar (US): Sunday leads, so Sun + Mon reads "Sun, Mon".
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [2, 1], calendar: cal), "Every Sun, Mon")
        XCTAssertEqual(AlarmPlan.orderedWeekdays(calendar: cal), [1, 2, 3, 4, 5, 6, 7])
        var monday = cal
        monday.firstWeekday = 2
        XCTAssertEqual(AlarmPlan.orderedWeekdays(calendar: monday), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(AlarmPlan.repeatValue(weekdays: [2, 1], calendar: monday), "Every Mon, Sun")
    }

    func testRowSubtitle() {
        XCTAssertEqual(AlarmPlan.rowSubtitle(label: "", weekdays: [], calendar: cal), "Alarm")
        XCTAssertEqual(AlarmPlan.rowSubtitle(label: "  ", weekdays: [1, 2, 3, 4, 5, 6, 7], calendar: cal), "Alarm, Every day")
        XCTAssertEqual(AlarmPlan.rowSubtitle(label: "Gym", weekdays: [2, 3, 4, 5, 6], calendar: cal), "Gym, Weekdays")
        XCTAssertEqual(AlarmPlan.rowSubtitle(label: "Gym", weekdays: [], calendar: cal), "Gym")
    }

    func testTimePartsFollowTheClockSetting() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 7, minute: 5, locale: us).time, "7:05")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 7, minute: 5, locale: us).suffix, "AM")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 0, minute: 0, locale: us).time, "12:00")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 12, minute: 30, locale: us).suffix, "PM")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 19, minute: 45, locale: us).time, "7:45")
        let de = Locale(identifier: "de_DE")
        XCTAssertEqual(AlarmPlan.timeParts(hour: 7, minute: 5, locale: de).time, "07:05")
        XCTAssertNil(AlarmPlan.timeParts(hour: 19, minute: 45, locale: de).suffix)
        XCTAssertEqual(AlarmPlan.timeParts(hour: 19, minute: 45, locale: de).time, "19:45")
    }

    func testNextRing() {
        let now = at(12, 9, 41)   // Monday
        // One-time alarm switched on at 9:00 for 18:00 rings today; for 7:00 it rings tomorrow.
        XCTAssertEqual(AlarmPlan.nextRing(hour: 18, minute: 0, weekdays: [], switchedOn: at(12, 9, 0), now: now, calendar: cal), at(12, 18, 0))
        XCTAssertEqual(AlarmPlan.nextRing(hour: 7, minute: 0, weekdays: [], switchedOn: at(12, 9, 0), now: now, calendar: cal), at(13, 7, 0))
        // A one-time alarm that already rang (switched on yesterday for 7:00) has nothing next.
        XCTAssertNil(AlarmPlan.nextRing(hour: 7, minute: 0, weekdays: [], switchedOn: at(11, 20, 0), now: now, calendar: cal))
        // Repeating alarms count from now.
        XCTAssertEqual(AlarmPlan.nextRing(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], switchedOn: at(1, 0, 0), now: at(16, 9, 41), calendar: cal), at(19, 7, 0))
    }

    func testNextAlarmText() {
        let now = at(12, 9, 41)
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [at(12, 16, 53)], now: now), "Next alarm in 7 hr 12 min")
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [at(13, 7, 0), at(12, 10, 41)], now: now), "Next alarm in 1 hr")
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [at(12, 9, 53)], now: now), "Next alarm in 12 min")
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [now.addingTimeInterval(20)], now: now), "Next alarm in 1 min")
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [at(14, 12, 41)], now: now), "Next alarm in 2 days 3 hr")
        XCTAssertEqual(AlarmPlan.nextAlarmText(rings: [at(13, 9, 41)], now: now), "Next alarm in 1 day")
        XCTAssertNil(AlarmPlan.nextAlarmText(rings: [], now: now))
        XCTAssertNil(AlarmPlan.nextAlarmText(rings: [at(12, 8, 0)], now: now), "an alarm in the past is not next")
    }

    func testFireOnDay() {
        let now = at(12, 9, 41)
        XCTAssertEqual(AlarmPlan.fire(on: at(12, 0, 0), hour: 18, minute: 0, weekdays: [], now: now, calendar: cal), at(12, 18, 0))
        XCTAssertNil(AlarmPlan.fire(on: at(13, 0, 0), hour: 18, minute: 0, weekdays: [], now: now, calendar: cal), "once rings only on its next day")
        XCTAssertEqual(AlarmPlan.fire(on: at(14, 0, 0), hour: 7, minute: 0, weekdays: [4], now: now, calendar: cal), at(14, 7, 0))
        XCTAssertNil(AlarmPlan.fire(on: at(15, 0, 0), hour: 7, minute: 0, weekdays: [4], now: now, calendar: cal))
    }
}
