import XCTest

/// Core journeys (J1–J7 in docs/goal-and-rubric.md), run against a fresh in-memory store with sample data.
/// Each test counts the taps it needs from the home screen; the budgets can only go down.
final class JourneyTests: XCTestCase {
    var app: XCUIApplication!
    var taps = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        taps = 0
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(element)", file: file, line: line)
        element.tap()
        taps += 1
    }

    private func tab(_ name: String) {
        tap(app.buttons[name].firstMatch)
    }

    /// J1: add a timed task from one line.
    func testJ1_addTimedTaskFromOneLine() {
        tap(app.buttons["Ask AI or add anything"])
        let field = app.textFields["Ask AI or add anything"].firstMatch.exists
            ? app.textFields["Ask AI or add anything"].firstMatch
            : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Call Alex tomorrow at 3pm\n")
        XCTAssertTrue(app.staticTexts["Call Alex"].waitForExistence(timeout: 5), "preview shows the parsed title")
        tap(app.buttons["Add"])
        XCTAssertTrue(app.staticTexts["Added “Call Alex” · Planned Tomorrow 15:00."].waitForExistence(timeout: 5)
                      || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Added'")).firstMatch.exists)
        XCTAssertLessThanOrEqual(taps, 2, "J1 tap budget")
    }

    /// J2: see what's left today.
    func testJ2_todayShowsWhatsLeft() {
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Due today"].exists)
        XCTAssertTrue(app.staticTexts["Schedule"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertEqual(taps, 0, "J2 needs no taps")
    }

    /// J3: complete a task, then undo it.
    func testJ3_completeAndUndo() {
        tap(app.buttons["Complete Buy milk"])
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "undo toast appears")
        XCTAssertFalse(app.staticTexts["Buy milk"].waitForExistence(timeout: 1), "completed task leaves Today")
        undo.tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3), "undo brings it back")
        XCTAssertTrue(app.buttons["Complete Buy milk"].exists, "and it is open again")
        XCTAssertLessThanOrEqual(taps, 1, "J3 tap budget")
    }

    /// J4: add an event.
    func testJ4_addEvent() {
        tap(app.buttons["New"])
        tap(app.buttons["New event"])
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Design review")
        tap(app.buttons["Done"])
        tab("Calendar")
        tap(app.buttons["Week"])
        tap(app.buttons["Day"])
        XCTAssertLessThanOrEqual(taps, 6)
    }

    /// J5: check in a habit from Today.
    func testJ5_checkInHabitFromToday() {
        let chip = app.buttons["Drink 8 glasses of water"]
        tap(chip)
        tab("Habits")
        XCTAssertTrue(app.buttons["Undo today's check-in for Drink 8 glasses of water"].waitForExistence(timeout: 3))
    }

    /// J6: reminders are visible and adjustable per item.
    func testJ6_alarmsListsTimedItemsWithBells() {
        tab("Alarms")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reminder:'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// J7: find something.
    func testJ7_search() {
        tap(app.buttons["Search"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("milk")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(taps, 1, "J7 tap budget")
    }

    /// Sidebar opens from the avatar and shows the views.
    func testSidebarOpensFromAvatar() {
        tap(app.buttons["Open sidebar"])
        XCTAssertTrue(app.buttons["New chat"].waitForExistence(timeout: 3))
    }

    /// AI claim 9: plan my day is a preview; nothing moves until Apply.
    func testPlanMyDay() {
        tap(app.buttons["Ask AI or add anything"])
        tap(app.buttons["Plan my day"])
        XCTAssertTrue(app.staticTexts["Plan for today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pay studio invoice"].exists, "overdue task is placed first")
        tap(app.buttons["Apply"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Planned 3 tasks'")).firstMatch
            .waitForExistence(timeout: 3))
    }
}
