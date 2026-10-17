import XCTest

/// The Pomodoro focus-timer card on top of the Alarms tab: chips set the dial, turning the dial changes the time,
/// today's rounds show as dots, and after a round the card offers one next step.
/// The simulator denies AlarmKit, so Start only shows the "needs alarm access" line here; ringing is checked on a phone.
final class TimerTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(rounds: Int? = nil) {
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + (rounds.map { ["-pomodoroRounds", "\($0)"] } ?? [])
        app.launch()
        let alarms = app.buttons["Alarms"].firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5))
        alarms.tap()
    }

    private var dial: XCUIElement { app.descendants(matching: .any)["timer.dial"].firstMatch }
    private var digits: XCUIElement { app.staticTexts["timer.digits"].firstMatch }
    private var dots: XCUIElement { app.staticTexts["pomodoro.rounds"].firstMatch }

    func testPomodoroChipsSetTheDial() {
        launch()
        let focus = app.buttons["timer.chip.25"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "the timer card is on the Alarms tab")
        XCTAssertFalse(app.buttons["timer.chip.1"].exists, "the 1 min chip is gone")
        XCTAssertFalse(app.buttons["timer.chip.10"].exists, "the 10 min chip is gone")
        XCTAssertEqual(digits.label, "25:00", "Focus 25 is the default")

        app.buttons["timer.chip.5"].tap()
        XCTAssertEqual(digits.label, "05:00", "Short break 5")
        app.buttons["timer.chip.15"].tap()
        XCTAssertEqual(digits.label, "15:00", "Long break 15")
        focus.tap()
        XCTAssertEqual(digits.label, "25:00")
        XCTAssertEqual(dial.value as? String, "25 minutes 0 seconds")
    }

    func testTurningTheDialChangesTheTime() {
        launch()
        let five = app.buttons["timer.chip.5"].firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 5))
        five.tap()
        XCTAssertEqual(digits.label, "05:00")

        // XCUIElement has no increment(); turn the dial a quarter clockwise (3 o'clock → 6 o'clock) instead: +75 s.
        let from = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let to = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        let mid = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
        from.press(forDuration: 0.1, thenDragTo: mid, withVelocity: .slow, thenHoldForDuration: 0)
        mid.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        let turned = digits.label
        XCTAssertNotEqual(turned, "05:00", "turning the dial clockwise adds time")
        XCTAssertGreaterThan(turned, "05:00", "clockwise adds, it does not take away: \(turned)")
    }

    func testNoRoundsYetShowsEmptyDots() {
        launch()
        XCTAssertTrue(dots.waitForExistence(timeout: 5))
        XCTAssertEqual(dots.label, "No focus rounds yet today")
        XCTAssertFalse(app.buttons["pomodoro.next"].exists, "no next step before any round")
    }

    func testAfterThreeRoundsOffersShortBreak() {
        launch(rounds: 3)
        XCTAssertTrue(dots.waitForExistence(timeout: 5))
        XCTAssertEqual(dots.label, "3 focus rounds today")
        let next = app.buttons["pomodoro.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.label, "Start 5-min break")
        XCTAssertEqual(digits.label, "05:00", "the dial shows the break it offers")

        // "Done for now" puts the chips back; the rounds stay.
        app.buttons["pomodoro.done"].tap()
        XCTAssertTrue(app.buttons["timer.chip.25"].waitForExistence(timeout: 5))
        XCTAssertFalse(next.exists)
        XCTAssertEqual(dots.label, "3 focus rounds today")
    }

    func testEveryFourthRoundOffersLongBreak() {
        launch(rounds: 4)
        let next = app.buttons["pomodoro.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.label, "Start 15-min long break")
        XCTAssertEqual(digits.label, "15:00")
        XCTAssertEqual(dots.label, "4 focus rounds today")
    }

    func testStartWithoutAlarmAccessExplains() {
        launch()
        let start = app.buttons["timer.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["timer.chip.5"].tap()
        start.tap()
        // The simulator denies AlarmKit; a phone that allowed alarms shows the countdown instead.
        let message = app.staticTexts["timer.message"]
        let remaining = app.staticTexts["timer.remaining"]
        XCTAssertTrue(message.waitForExistence(timeout: 5) || remaining.exists, "Start either runs or says why it can't")
        if remaining.exists { app.buttons["timer.cancel"].tap() }
        XCTAssertEqual(dots.label, "No focus rounds yet today", "a countdown that did not run out is not a round")
    }
}
