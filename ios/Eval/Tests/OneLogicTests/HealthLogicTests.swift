import XCTest
@testable import OneLogic

final class HealthLogicTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testSleepBelongsToTheMorningYouWakeUp() {
        let now = date(16, 9)
        let nights = HealthMath.nights([
            SleepInterval(start: date(15, 23, 10), end: date(16, 2), stage: .core),
            SleepInterval(start: date(16, 2), end: date(16, 2, 10), stage: .awake),
            SleepInterval(start: date(16, 2, 10), end: date(16, 6, 40), stage: .deep),
            SleepInterval(start: date(14, 0, 30), end: date(14, 7), stage: .unspecified),
        ], count: 7, now: now, calendar: cal)
        XCTAssertEqual(nights.map(\.day), [cal.startOfDay(for: date(14, 0)), cal.startOfDay(for: date(16, 0))])
        XCTAssertEqual(nights.last?.asleep, (2 * 60 + 50 + 4 * 60 + 30) * 60, "awake is not sleep")
        XCTAssertEqual(nights.last?.start, date(15, 23, 10))
        XCTAssertEqual(nights.last?.end, date(16, 6, 40))
    }

    func testStagedSleepDropsDuplicatePlainAsleep() {
        let now = date(16, 9)
        let nights = HealthMath.nights([
            SleepInterval(start: date(15, 23), end: date(16, 7), stage: .unspecified),   // iPhone
            SleepInterval(start: date(15, 23), end: date(16, 3), stage: .core),          // Watch
            SleepInterval(start: date(16, 3), end: date(16, 7), stage: .rem),
        ], count: 7, now: now, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].asleep, 8 * 3600, "8 hours, not 16")
        XCTAssertEqual(nights[0].stages, [.rem, .core])
    }

    func testDurationText() {
        XCTAssertEqual(HealthMath.duration(45 * 60), "45 min")
        XCTAssertEqual(HealthMath.duration(7 * 3600), "7 hr")
        XCTAssertEqual(HealthMath.duration(7 * 3600 + 12 * 60), "7 hr 12 min")
    }
}
