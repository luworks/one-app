import XCTest
@testable import OneLogic

final class PomodoroTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testChipsAndLabels() {
        XCTAssertEqual(Pomodoro.chips, [.focus, .shortBreak, .longBreak])
        XCTAssertEqual(Pomodoro.chips.map(\.minutes), [25, 5, 15])
        XCTAssertEqual(Pomodoro.chips.map(\.chipLabel), ["Focus 25", "Short break 5", "Long break 15"])
        XCTAssertEqual(PomodoroPhase.focus.title, "Focus")
        XCTAssertEqual(PomodoroPhase.shortBreak.title, "Break")
        XCTAssertEqual(PomodoroPhase.longBreak.title, "Break")
    }

    func testCustomDurationCountsAsFocus() {
        XCTAssertEqual(Pomodoro.phase(seconds: 25 * 60, chosen: .focus), .focus)
        XCTAssertEqual(Pomodoro.phase(seconds: 5 * 60, chosen: .shortBreak), .shortBreak)
        XCTAssertEqual(Pomodoro.phase(seconds: 15 * 60, chosen: .longBreak), .longBreak)
        XCTAssertEqual(Pomodoro.phase(seconds: 5 * 60 + 30, chosen: .shortBreak), .focus, "turning the dial off a break makes it Focus")
        XCTAssertEqual(Pomodoro.phase(seconds: 40 * 60, chosen: .focus), .focus)
        XCTAssertEqual(Pomodoro.phase(seconds: 5 * 60, chosen: nil), .focus, "5:00 from the dial alone is Focus")
        XCTAssertEqual(Pomodoro.phase(seconds: 15 * 60, chosen: .shortBreak), .focus)
    }

    func testNextStepEveryFourthIsLong() {
        XCTAssertEqual(Pomodoro.next(after: .focus, roundsToday: 1), .shortBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, roundsToday: 3), .shortBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, roundsToday: 4), .longBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, roundsToday: 5), .shortBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, roundsToday: 8), .longBreak)
        XCTAssertEqual(Pomodoro.next(after: .shortBreak, roundsToday: 4), .focus)
        XCTAssertEqual(Pomodoro.next(after: .longBreak, roundsToday: 4), .focus)
        XCTAssertEqual(Pomodoro.nextTitle(.shortBreak), "Start 5-min break")
        XCTAssertEqual(Pomodoro.nextTitle(.longBreak), "Start 15-min long break")
        XCTAssertEqual(Pomodoro.nextTitle(.focus), "Focus again")
    }

    func testDots() {
        XCTAssertEqual(Pomodoro.dots(0), ["○○○○"])
        XCTAssertEqual(Pomodoro.dots(3), ["●●●○"])
        XCTAssertEqual(Pomodoro.dots(4), ["●●●●"])
        XCTAssertEqual(Pomodoro.dots(5), ["●●●●", "●○○○"])
        XCTAssertEqual(Pomodoro.dots(8), ["●●●●", "●●●●"])
        XCTAssertEqual(Pomodoro.dots(-2), ["○○○○"])
        XCTAssertEqual(Pomodoro.spokenRounds(0), "No focus rounds yet today")
        XCTAssertEqual(Pomodoro.spokenRounds(1), "1 focus round today")
        XCTAssertEqual(Pomodoro.spokenRounds(3), "3 focus rounds today")
    }

    func testCompletingCountsFocusOnceAndOffersNextStep() {
        let a = UUID(), b = UUID(), c = UUID()
        var log = PomodoroLog.empty(date(16, 9), calendar: calendar)
        log = log.completing(.focus, id: a, now: date(16, 9, 25), calendar: calendar)
        XCTAssertEqual(log.rounds, 1)
        XCTAssertEqual(log.nextStep, .shortBreak)
        log = log.completing(.focus, id: a, now: date(16, 9, 26), calendar: calendar)
        XCTAssertEqual(log.rounds, 1, "the same countdown seen ringing and then gone counts once")
        log = log.completing(.shortBreak, id: b, now: date(16, 9, 31), calendar: calendar)
        XCTAssertEqual(log.rounds, 1, "a break is not a round")
        XCTAssertEqual(log.nextStep, .focus)
        log.rounds = 3
        log = log.completing(.focus, id: c, now: date(16, 11), calendar: calendar)
        XCTAssertEqual(log.rounds, 4)
        XCTAssertEqual(log.nextStep, .longBreak)
        log.pending = nil
        XCTAssertNil(log.nextStep, "Done for now clears the offer")
    }

    func testResetsAtMidnight() {
        var log = PomodoroLog.empty(date(16, 22), calendar: calendar)
        log = log.completing(.focus, id: UUID(), now: date(16, 23, 50), calendar: calendar)
        XCTAssertEqual(log.current(date(16, 23, 59), calendar: calendar).rounds, 1)
        let tomorrow = log.current(date(17, 0, 1), calendar: calendar)
        XCTAssertEqual(tomorrow.rounds, 0)
        XCTAssertNil(tomorrow.pending)
        XCTAssertEqual(tomorrow.day, "2026-10-17")
        let next = log.completing(.focus, id: UUID(), now: date(17, 9), calendar: calendar)
        XCTAssertEqual(next.rounds, 1, "the first round of a new day starts from zero")
    }

    func testStorageRoundTrip() {
        let defaults = UserDefaults(suiteName: "PomodoroTests")!
        defaults.removePersistentDomain(forName: "PomodoroTests")
        let now = date(16, 10)
        XCTAssertEqual(PomodoroLog.load(defaults, now: now, calendar: calendar).rounds, 0)
        let log = PomodoroLog.empty(now, calendar: calendar).completing(.focus, id: UUID(), now: now, calendar: calendar)
        PomodoroLog.save(log, defaults)
        XCTAssertEqual(PomodoroLog.load(defaults, now: now, calendar: calendar), log)
        XCTAssertEqual(PomodoroLog.load(defaults, now: date(17, 8), calendar: calendar).rounds, 0)
    }

    func testRanToEndVersusCancelled() {
        let start = date(16, 9)
        let t = RunningTimer.start(id: UUID(), seconds: 300, now: start, phase: .shortBreak)
        XCTAssertEqual(t.pomodoroPhase, .shortBreak)
        XCTAssertFalse(t.ranToEnd(now: start.addingTimeInterval(120)), "gone early means cancelled")
        XCTAssertTrue(t.ranToEnd(now: start.addingTimeInterval(300)))
        XCTAssertTrue(t.ranToEnd(now: start.addingTimeInterval(900)))
        XCTAssertFalse(t.paused(now: start.addingTimeInterval(10)).ranToEnd(now: start.addingTimeInterval(900)))
        XCTAssertEqual(t.paused(now: start).resumed(now: start).phase, .shortBreak, "pause/resume keep the phase")
    }

    func testOldSavedTimerDecodesAsFocus() throws {
        let json = #"{"id":"6A1E2B9C-1111-4C1D-9E2F-000000000001","total":300,"endsAt":0}"#
        let t = try JSONDecoder().decode(RunningTimer.self, from: Data(json.utf8))
        XCTAssertNil(t.phase)
        XCTAssertEqual(t.pomodoroPhase, .focus)
    }
}
