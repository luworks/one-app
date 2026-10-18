import XCTest
@testable import OneLogic

/// The length limits and `RunningTimer` (pause, resume, storage). The kitchen-timer dial was replaced by Apple's wheel picker.
final class TimerDialTests: XCTestCase {
    func testLimitsAndSpokenLength() {
        XCTAssertEqual(TimerDial.maxSeconds, 23 * 3600 + 59 * 60, "the longest timer is 23 h 59 min, like Clock")
        XCTAssertEqual(TimerDial.maxSeconds % 60, 0, "whole minutes, so Siri can ask for the maximum")
        XCTAssertEqual(TimerDial.spoken(480), "8 minutes 0 seconds")
        XCTAssertEqual(TimerDial.spoken(61), "1 minute 1 second")
    }

    func testRunningTimerPauseAndResume() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        var timer = RunningTimer.start(id: id, seconds: 300, now: t0)
        XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(60)), 240)
        timer = timer.paused(now: t0.addingTimeInterval(100))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(1000)), 200, "paused time does not run")
        timer = timer.resumed(now: t0.addingTimeInterval(1000))
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(timer.endsAt, t0.addingTimeInterval(1200))
        XCTAssertEqual(timer.remaining(now: t0.addingTimeInterval(5000)), 0, "never negative")
    }

    func testRunningTimerStorage() {
        let defaults = UserDefaults(suiteName: "TimerDialTests")!
        defaults.removePersistentDomain(forName: "TimerDialTests")
        XCTAssertNil(RunningTimer.load(defaults))
        let timer = RunningTimer.start(id: UUID(), seconds: 90, now: Date(timeIntervalSince1970: 0))
        RunningTimer.save(timer, defaults)
        XCTAssertEqual(RunningTimer.load(defaults), timer)
        RunningTimer.save(nil, defaults)
        XCTAssertNil(RunningTimer.load(defaults))
    }
}
