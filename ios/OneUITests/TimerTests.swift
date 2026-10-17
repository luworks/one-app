import XCTest

/// The kitchen-timer card on top of the Alarms tab: chips set the dial, turning the dial changes the time.
/// The simulator denies AlarmKit, so Start only shows the "needs alarm access" line here; ringing is checked on a phone.
final class TimerTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()
        let alarms = app.buttons["Alarms"].firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5))
        alarms.tap()
        // The timer is the Timer section of the Alarms tab.
        let timer = app.buttons["clock.section.timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        timer.tap()
    }

    private var dial: XCUIElement { app.descendants(matching: .any)["timer.dial"].firstMatch }
    private var digits: XCUIElement { app.staticTexts["timer.digits"].firstMatch }

    func testChipSetsTheDialAndTurningChangesIt() {
        let five = app.buttons["timer.chip.5"].firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 5), "the timer card is on the Alarms tab")
        app.buttons["timer.chip.1"].tap()
        five.tap()
        XCTAssertEqual(digits.label, "05:00", "the 5 min chip sets the dial")
        XCTAssertEqual(dial.value as? String, "5 minutes 0 seconds")

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

    func testStartWithoutAlarmAccessExplains() {
        let start = app.buttons["timer.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["timer.chip.1"].tap()
        start.tap()
        // The simulator denies AlarmKit; a phone that allowed alarms shows the countdown instead.
        let message = app.staticTexts["timer.message"]
        let remaining = app.staticTexts["timer.remaining"]
        XCTAssertTrue(message.waitForExistence(timeout: 5) || remaining.exists, "Start either runs or says why it can't")
        if remaining.exists { app.buttons["timer.cancel"].tap() }
    }
}
