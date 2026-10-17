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

    func testDaysFillsMissingWithZeroAndEndsToday() {
        let now = date(16, 15)
        let days = HealthMath.days([cal.startOfDay(for: date(16, 0)): 4_200, cal.startOfDay(for: date(13, 0)): 9_000],
                                   count: 7, now: now, calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.day, cal.startOfDay(for: now))
        XCTAssertEqual(days.last?.value, 4_200)
        XCTAssertEqual(days[3].value, 9_000, "Oct 13 is the 4th of Oct 10…16")
        XCTAssertEqual(days[0].value, 0)
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

    func testWeightWindowAndChange() {
        let now = date(16, 9)
        let samples = [
            WeightSample(date: date(16, 7) - 80 * 86_400, kilograms: 72),
            WeightSample(date: date(16, 7) - 20 * 86_400, kilograms: 71),
            WeightSample(date: date(16, 7), kilograms: 70.4),
        ]
        let last30 = HealthMath.weights(samples, lastDays: 30, now: now, calendar: cal)
        XCTAssertEqual(last30.count, 2)
        XCTAssertEqual(HealthMath.weightChange(last30)!, -0.6, accuracy: 0.001)
        XCTAssertNil(HealthMath.weightChange(Array(last30.prefix(1))))
    }

    func testDurationText() {
        XCTAssertEqual(HealthMath.duration(45 * 60), "45 min")
        XCTAssertEqual(HealthMath.duration(7 * 3600), "7 hr")
        XCTAssertEqual(HealthMath.duration(7 * 3600 + 12 * 60), "7 hr 12 min")
    }

    func testSampleIsStableAndPlausible() {
        let now = date(16, 15)
        let a = HealthSample.snapshot(now: now, calendar: cal)
        XCTAssertEqual(a, HealthSample.snapshot(now: now, calendar: cal), "seeded: same data every run")
        XCTAssertTrue(a.isSample)
        XCTAssertEqual(a.steps.count, 7)
        XCTAssertTrue(a.steps.dropLast().allSatisfy { (3_000...13_000).contains($0.value) })
        XCTAssertEqual(a.nights.count, 7)
        XCTAssertTrue(a.nights.allSatisfy { (5.5 * 3600...8.5 * 3600).contains($0.asleep) })
        XCTAssertEqual(a.lastNight?.day, cal.startOfDay(for: now))
        XCTAssertGreaterThan(a.weights.count, 40)
        XCTAssertTrue(a.weights.allSatisfy { (69...73).contains($0.kilograms) })
        XCTAssertTrue(a.weights.allSatisfy { $0.date <= now })
    }
}
