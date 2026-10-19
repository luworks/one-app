import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

final class CalendarBoundaryTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDailySeriesStillAppearsYearsAfterCreation() {
        let window = DateInterval(start: date(2026, 10, 18), end: date(2026, 10, 21))
        let starts = Recurrence.occurrences(start: date(2020, 1, 1, 9), duration: 3600, rule: .daily,
                                           in: window, calendar: calendar)
        XCTAssertEqual(starts, [date(2026, 10, 18, 9), date(2026, 10, 19, 9), date(2026, 10, 20, 9)])
    }

    func testLimitBoundsVisibleOccurrencesRatherThanSeriesAge() {
        let window = DateInterval(start: date(2026, 12, 31), end: date(2027, 1, 4))
        let starts = Recurrence.occurrences(start: date(2020, 1, 1, 23), duration: 7200, rule: .daily,
                                           in: window, calendar: calendar, limit: 2)
        XCTAssertEqual(starts, [date(2026, 12, 30, 23), date(2026, 12, 31, 23)],
                       "An occurrence starting before the window still counts when it crosses midnight.")
    }

    func testWeeklySeriesStillAppearsAfterTwentyYears() {
        let window = DateInterval(start: date(2026, 10, 18), end: date(2026, 10, 25))
        XCTAssertEqual(Recurrence.occurrences(start: date(2000, 1, 3, 9), duration: 3600, rule: .weekly,
                                            in: window, calendar: calendar), [date(2026, 10, 19, 9)])
    }

    func testOldDailySeriesKeepsWallClockTimeAcrossDST() {
        for (month, day) in [(3, 8), (11, 1)] {
            let window = DateInterval(start: date(2026, month, day - 1), end: date(2026, month, day + 1))
            XCTAssertEqual(Recurrence.occurrences(start: date(2020, 1, 1, 9), duration: 3600, rule: .daily,
                                                in: window, calendar: calendar),
                           [date(2026, month, day - 1, 9), date(2026, month, day, 9)])
        }
    }

    func testSystemAllDaySpanKeepsItsExclusiveEndInEveryView() {
        for (month, day, endDay) in [(3, 8, 9), (11, 1, 2), (12, 30, 31)] {
            let start = date(2026, month, day)
            let end = date(2026, month, endDay)
            for yearView in [false, true] {
                let displayedEnd = CalendarEntryDates.systemEnd(end, isAllDay: true, forYearMarks: yearView,
                                                               calendar: calendar)
                XCTAssertEqual(displayedEnd, end)
                XCTAssertTrue(CalendarEntryDates.overlaps(start: start, end: displayedEnd, day: start, calendar: calendar))
                XCTAssertFalse(CalendarEntryDates.overlaps(start: start, end: displayedEnd, day: end, calendar: calendar),
                               "A one-day holiday must not also appear on its exclusive end date.")
            }
        }
    }

    func testMidnightAlarmBelongsOnlyToTheDayItRings() {
        let midnight = date(2027, 1, 1)
        XCTAssertFalse(CalendarEntryDates.overlaps(start: midnight, end: midnight,
                                                  day: date(2026, 12, 31), calendar: calendar))
        XCTAssertTrue(CalendarEntryDates.overlaps(start: midnight, end: midnight,
                                                 day: midnight, calendar: calendar))
        XCTAssertFalse(CalendarEntryDates.overlaps(start: midnight, end: midnight,
                                                  day: date(2027, 1, 2), calendar: calendar))
    }

    func testAlarmProjectionUsesCalendarDaysAcrossDST() {
        let spec = AlarmSpec(hour: 9, minute: 0, label: "Morning", weekdays: [1, 2, 3, 4, 5, 6, 7], isOn: true)
        for (month, day) in [(3, 8), (11, 1)] {
            let window = DateInterval(start: date(2026, month, day - 1), end: date(2026, month, day + 2))
            let rings = CalendarAlarms.occurrences(of: [spec], in: window, now: window.start, calendar: calendar)
            XCTAssertEqual(rings.map(\.date), [date(2026, month, day - 1, 9), date(2026, month, day, 9),
                                               date(2026, month, day + 1, 9)])
            XCTAssertEqual(rings, (-1...1).flatMap {
                CalendarAlarms.occurrences(of: [spec], on: date(2026, month, day + $0),
                                          now: window.start, calendar: calendar)
            })
        }
    }

    func testAlarmRangeExcludesNextYearMidnight() {
        let spec = AlarmSpec(hour: 0, minute: 0, label: "Midnight", weekdays: [1, 2, 3, 4, 5, 6, 7], isOn: true)
        let yearEnd = DateInterval(start: date(2026, 12, 31), end: date(2027, 1, 1))
        let rings = CalendarAlarms.occurrences(of: [spec], in: yearEnd, now: yearEnd.start, calendar: calendar)
        XCTAssertEqual(rings.map(\.date), [date(2026, 12, 31)])
    }

    func testYearDayNavigationDatesStayUniqueAcrossDSTAndLeapDay() {
        for month in [2, 3, 11, 12] {
            let days = CalendarMath.monthWeeks(of: date(2028, month, 15), calendar: calendar)
                .flatMap { $0 }.compactMap { $0 }
            let count = calendar.range(of: .day, in: .month, for: date(2028, month, 1))!.count
            XCTAssertEqual(days.count, count)
            XCTAssertEqual(Set(days).count, count)
            XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, Array(1...count))
            XCTAssertTrue(days.allSatisfy { $0 == calendar.startOfDay(for: $0) })
        }
    }
}
