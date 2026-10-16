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
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ENDSWITH 'overdue'")).firstMatch.waitForExistence(timeout: 5))
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
        tab("Calendar")
        tap(app.buttons["New"])   // + adds an event on the Calendar page
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Design review")
        tap(app.buttons["Done"])
        tap(app.buttons["Month"])
        XCTAssertLessThanOrEqual(taps, 6)
    }

    /// J6: add a real alarm, see it on the Alarms page and in Today's schedule.
    func testJ6_addAlarmAndSeeItInToday() {
        tab("Alarms")
        tap(app.buttons["New"])   // + adds an alarm on the Alarms page
        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Wake up")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Wake up'")).firstMatch.waitForExistence(timeout: 5))
        tab("Today")
        // The list is lazy: scroll until the row has been created.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Alarm Wake up'")).firstMatch
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 3), "a one-time alarm shows in the day it rings")
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
    func testPlanMyDay() throws {
        // The planner only fills free time until 9 PM, so late in the evening there is nothing to place.
        try XCTSkipIf(Calendar.current.component(.hour, from: .now) >= 18, "needs free time before 9 PM")
        tap(app.buttons["Ask AI or add anything"])
        tap(app.buttons["Plan my day"])
        XCTAssertTrue(app.staticTexts["Plan for today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pay studio invoice"].exists, "overdue task is placed first")
        tap(app.buttons["Apply"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Planned 3 tasks'")).firstMatch
            .waitForExistence(timeout: 3))
    }

    /// Interaction claim 8: long-press and drag a task in the week grid to reschedule it.
    func testDragTaskInWeekGrid() {
        tab("Calendar")
        tap(app.buttons["Week"])
        let block = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Prepare the demo, planned'")).firstMatch
        let anyBlock = block.exists ? block
            : app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Prepare the demo, planned'")).firstMatch
        XCTAssertTrue(anyBlock.waitForExistence(timeout: 5))
        let before = anyBlock.label
        let start = anyBlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        // One hour down = 48 pt in the grid.
        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 48)))
        let moved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Prepare the demo, planned' AND label != %@", before)).firstMatch
        XCTAssertTrue(moved.waitForExistence(timeout: 3), "planned time changed after drag (was: \(before))")
    }
}
