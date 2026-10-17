import XCTest

/// One tap opens exactly one editor: no second sheet underneath, nothing left behind after Cancel.
/// (A sheet on the row plus one on the list, or a tap handler plus a menu action, would stack two.)
/// Also: long-press an empty slot on the Week grid to make an event there, like Apple Calendar.
/// Uses the test dataset (tests/fixtures/today-dataset.json). Set TEST_RUNNER_PRESENT_SHOTS=<folder> for screenshots.
final class SinglePresentationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PRESENT_SHOTS"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }

    private func labeled(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// After `open`, exactly one editor (one navigation bar) is up; one Cancel closes it and nothing is underneath.
    private func assertOpensOneEditor(_ name: String, cancel: String = "Cancel", open: () -> Void,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.navigationBars.count, 0, "nothing is open before the tap", file: file, line: line)
        open()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5), "an editor opens", file: file, line: line)
        sleep(1)   // a second, late presentation would land by now
        shot(name)
        XCTAssertEqual(app.navigationBars.count, 1, "exactly one editor: \(app.navigationBars.debugDescription)", file: file, line: line)
        app.buttons[cancel].firstMatch.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.navigationBars)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "one Cancel closes it; no second editor underneath",
                       file: file, line: line)
    }

    func testTappingAnEventInWeekOpensOneEditor() {
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar.mode.week"].tap()
        let block = labeled("Product sync")
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        assertOpensOneEditor("week-event") { block.tap() }
    }

    func testTappingAnEventInMonthOpensOneEditor() {
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar.mode.month"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'agenda.row' AND label BEGINSWITH 'Product sync'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        assertOpensOneEditor("month-event") { row.tap() }
    }

    func testTappingAnEventOnTodayOpensOneEditor() {
        let row = labeled("Product sync")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        assertOpensOneEditor("today-event") { row.tap() }
    }

    func testTappingAReminderOpensOneEditor() {
        let row = app.staticTexts["Buy milk"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        assertOpensOneEditor("today-reminder") { row.tap() }
    }

    func testTappingAReminderInAListOpensOneEditor() {
        app.buttons["Reminders"].firstMatch.tap()
        let home = app.buttons["list.Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        let row = app.staticTexts["Buy milk"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // The list screen is pushed: it has its own navigation bar, so count from there.
        let before = app.navigationBars.count
        row.tap()
        sleep(2)
        shot("list-reminder")
        XCTAssertEqual(app.navigationBars.count, before + 1, "exactly one editor over the list")
    }

    func testTappingAnAlarmOpensOneEditor() {
        app.buttons["Alarms"].firstMatch.tap()
        let row = app.buttons.matching(identifier: "alarm.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        assertOpensOneEditor("alarm") { row.tap() }
    }

    // MARK: Long-press to make an event

    /// Where 11:10 and 12:10 are in today's column: measured from the 09:00 "Product sync" block (48pt per hour).
    private func todaySlot(minutesAfterNine: Double) -> XCUICoordinate {
        let block = labeled("Product sync")
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let f = block.frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: f.minX + 4, dy: f.minY + minutesAfterNine / 60 * 48))
    }

    private func showWeek() {
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar.mode.week"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendar.weekTitle"].waitForExistence(timeout: 5))
    }

    /// Press and hold an empty slot (11:00, between Standup and lunch): the new-event editor opens at 11:00-12:00.
    func testLongPressOnAnEmptySlotMakesAnEventThere() {
        showWeek()
        let slot = todaySlot(minutesAfterNine: 130)   // 11:10 snaps down to 11:00
        slot.press(forDuration: 0.8)
        let editor = app.navigationBars["New event"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "releasing opens the new-event editor")
        shot("longpress-editor")
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertTrue(app.buttons["11:00"].exists || labeled("11:00").exists, "starts at the pressed slot")
        XCTAssertTrue(app.buttons["12:00"].exists || labeled("12:00").exists, "and lasts an hour")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["calendar.newEventDraft"].waitForExistence(timeout: 1), "the placeholder is gone")
    }

    /// Hold, then drag down an hour before letting go: the event starts where the finger ends (12:00).
    func testLongPressThenDragMovesTheNewEvent() {
        showWeek()
        let from = todaySlot(minutesAfterNine: 130)
        let to = from.withOffset(CGVector(dx: 0, dy: 48))
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.navigationBars["New event"].waitForExistence(timeout: 5))
        shot("longpress-drag-editor")
        XCTAssertTrue(app.buttons["12:00"].exists || labeled("12:00").exists, "starts where the finger was let go")
        XCTAssertTrue(app.buttons["13:00"].exists || labeled("13:00").exists)
        app.buttons["Cancel"].tap()
    }

    /// A quick tap on an empty slot does nothing, and a swipe still scrolls the grid (no editor, no placeholder).
    func testTapAndSwipeOnTheGridDoNotMakeAnEvent() {
        showWeek()
        todaySlot(minutesAfterNine: 130).tap()
        app.descendants(matching: .any)["calendar.weekTitle"].swipeUp()   // header doesn't scroll; harmless
        let block = labeled("Product sync")
        let y = block.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        sleep(1)
        XCTAssertEqual(app.navigationBars.count, 0, "no editor")
        XCTAssertFalse(app.descendants(matching: .any)["calendar.newEventDraft"].exists, "no placeholder")
        XCTAssertNotEqual(block.frame.minY, y, "the grid scrolled")
    }
}
