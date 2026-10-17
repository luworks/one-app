import XCTest
@testable import OneLogic

final class QuickTimeTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    // Friday 16 Oct 2026, 22:17
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 22, minute: 17))!

    private func parts(_ d: Date) -> DateComponents { cal.dateComponents([.month, .day, .hour, .minute], from: d) }

    func testStartsAtTheNextQuarterHour() {
        XCTAssertEqual(parts(QuickTime.start(now: now, calendar: cal)), DateComponents(month: 10, day: 16, hour: 22, minute: 30))
    }

    func testAPastPresetMovesToTomorrow() {
        XCTAssertEqual(parts(QuickTime.preset(hour: 9, minute: 30, on: now, now: now, calendar: cal)),
                       DateComponents(month: 10, day: 17, hour: 9, minute: 30))
        XCTAssertEqual(parts(QuickTime.preset(hour: 22, minute: 0, on: now, now: now, calendar: cal)),
                       DateComponents(month: 10, day: 17, hour: 22, minute: 0))
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(parts(QuickTime.preset(hour: 12, minute: 0, on: tomorrow, now: now, calendar: cal)),
                       DateComponents(month: 10, day: 17, hour: 12, minute: 0), "a future day keeps the preset as is")
    }

    func testNudges() {
        XCTAssertEqual(parts(QuickTime.nudge(now, minutes: 10, calendar: cal)), DateComponents(month: 10, day: 16, hour: 22, minute: 27))
        XCTAssertEqual(parts(QuickTime.nudge(now, minutes: -1440, calendar: cal)), DateComponents(month: 10, day: 15, hour: 22, minute: 17))
        XCTAssertEqual(QuickTime.nudgeLabel(180), "+3 hr")
        XCTAssertEqual(QuickTime.nudgeLabel(-10), "−10 min")
        XCTAssertEqual(QuickTime.nudgeLabel(1440), "+1 day")
    }

    func testDaysKeepTheTime() {
        let nine = cal.date(bySettingHour: 9, minute: 30, second: 0, of: now)!
        XCTAssertEqual(parts(QuickTime.move(nine, to: .tomorrow, now: now, calendar: cal)), DateComponents(month: 10, day: 17, hour: 9, minute: 30))
        XCTAssertEqual(parts(QuickTime.move(nine, to: .weekend, now: now, calendar: cal)), DateComponents(month: 10, day: 17, hour: 9, minute: 30),
                       "Friday: the weekend starts tomorrow")
        XCTAssertEqual(parts(QuickTime.move(nine, to: .nextWeek, now: now, calendar: cal)), DateComponents(month: 10, day: 19, hour: 9, minute: 30))
    }

    func testRelativeText() {
        XCTAssertEqual(QuickTime.relative(now, now: now), "Now")
        XCTAssertEqual(QuickTime.relative(now.addingTimeInterval(25 * 60), now: now), "in 25 min")
        XCTAssertEqual(QuickTime.relative(now.addingTimeInterval(150 * 60), now: now), "in 2 hr 30 min")
        XCTAssertEqual(QuickTime.relative(now.addingTimeInterval(-10 * 60), now: now), "10 min ago")
        XCTAssertEqual(QuickTime.relative(now.addingTimeInterval(3 * 86_400), now: now), "in 3 days")
    }
}
