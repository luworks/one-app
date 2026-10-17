import XCTest
@testable import OneLogic

final class TimerDialTests: XCTestCase {
    func testStepSizes() {
        XCTAssertEqual(TimerDial.step(at: 0), 15)
        XCTAssertEqual(TimerDial.step(at: 299), 15)
        XCTAssertEqual(TimerDial.step(at: 300), 30)
        XCTAssertEqual(TimerDial.step(at: 899), 30)
        XCTAssertEqual(TimerDial.step(at: 900), 60)
        XCTAssertEqual(TimerDial.step(at: 5400), 60)
    }

    func testSnapAndClamp() {
        XCTAssertEqual(TimerDial.snap(-50), 0)
        XCTAssertEqual(TimerDial.snap(7), 0)
        XCTAssertEqual(TimerDial.snap(8), 15)
        XCTAssertEqual(TimerDial.snap(310), 300)
        XCTAssertEqual(TimerDial.snap(320), 330)
        XCTAssertEqual(TimerDial.snap(925), 900)
        XCTAssertEqual(TimerDial.snap(935), 960)
        XCTAssertEqual(TimerDial.snap(99_999), 5400)
        XCTAssertEqual(TimerDial.clamp(-1), 0)
        XCTAssertEqual(TimerDial.clamp(6000), 5400)
    }

    func testOneTurnIsFiveMinutes() {
        XCTAssertEqual(TimerDial.rotate(0, by: 2 * .pi), 300, accuracy: 0.001)
        XCTAssertEqual(TimerDial.rotate(300, by: .pi / 2), 375, accuracy: 0.001, "a quarter turn clockwise adds 75 s")
        XCTAssertEqual(TimerDial.rotate(300, by: -.pi / 2), 225, accuracy: 0.001, "counter-clockwise takes time away")
        XCTAssertEqual(TimerDial.rotate(10, by: -.pi), 0, "never below zero")
        XCTAssertEqual(TimerDial.rotate(5390, by: .pi), 5400, "never above 90:00")
    }

    func testAngleDeltaTakesTheShortWayAcrossTheSeam() {
        let deg = Double.pi / 180
        XCTAssertEqual(TimerDial.angleDelta(from: 170 * deg, to: -170 * deg), 20 * deg, accuracy: 1e-9)
        XCTAssertEqual(TimerDial.angleDelta(from: -170 * deg, to: 170 * deg), -20 * deg, accuracy: 1e-9)
        XCTAssertEqual(TimerDial.angleDelta(from: 10 * deg, to: 40 * deg), 30 * deg, accuracy: 1e-9)
    }

    func testIncrementAndDecrementCrossRanges() {
        XCTAssertEqual(TimerDial.increment(0), 15)
        XCTAssertEqual(TimerDial.increment(285), 300)
        XCTAssertEqual(TimerDial.increment(300), 330)
        XCTAssertEqual(TimerDial.increment(870), 900)
        XCTAssertEqual(TimerDial.increment(900), 960)
        XCTAssertEqual(TimerDial.increment(5400), 5400)
        XCTAssertEqual(TimerDial.decrement(0), 0)
        XCTAssertEqual(TimerDial.decrement(300), 285)
        XCTAssertEqual(TimerDial.decrement(900), 870)
        XCTAssertEqual(TimerDial.decrement(960), 900)
        XCTAssertEqual(TimerDial.decrement(15), 0)
    }

    func testKnobPosition() {
        XCTAssertEqual(TimerDial.knobFraction(0), 0)
        XCTAssertEqual(TimerDial.knobFraction(75), 0.25, accuracy: 1e-9)
        XCTAssertEqual(TimerDial.knobFraction(375), 0.25, accuracy: 1e-9)
    }

    func testFormatting() {
        XCTAssertEqual(TimerDial.format(0), "00:00")
        XCTAssertEqual(TimerDial.format(300), "05:00")
        XCTAssertEqual(TimerDial.format(75), "01:15")
        XCTAssertEqual(TimerDial.format(5400), "90:00")
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
