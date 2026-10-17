import XCTest

/// Deleting an event stays in step with Apple Calendar, both ways. Uses the simulator's own calendar (never a real one).
/// A test store file (-uiTestingStore) lets a second launch see what the first one saved, like a real phone does.
final class CalendarDeleteSyncTests: XCTestCase {
    private let store = "deletesync-\(Int(Date.now.timeIntervalSince1970))"
    private var title = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A new event starts at the next full hour; in the last hour of the day that is tomorrow, not in today's list.
        try XCTSkipIf(Calendar.current.component(.hour, from: .now) >= 23, "the default event time is tomorrow")
        title = "Sync check \(Int(Date.now.timeIntervalSince1970) % 100000)"
    }

    override func tearDown() {
        // Leave nothing behind in the simulator's calendar.
        let app = launch(["-debugDeleteSystemEvent", title])
        _ = app.staticTexts["Schedule"].waitForExistence(timeout: 10)
        sleep(2)
        app.terminate()
        super.tearDown()
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingCalendarSync", "-uiTestingStore", store] + extra
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// The Today list is lazy, and earlier runs leave events in the simulator's calendar: look further down for the row.
    private func isListed(_ app: XCUIApplication) -> Bool {
        var found = row(app).waitForExistence(timeout: 5)
        for _ in 0..<8 where !found {
            app.swipeUp()
            found = row(app).waitForExistence(timeout: 1)
        }
        return found
    }

    private func addEvent(_ app: XCUIApplication) {
        app.buttons["Calendar"].firstMatch.tap()
        sleep(1)
        app.buttons["New"].tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["Done"].tap()
    }

    /// Deleted in Apple Calendar → gone here too. (The event Today created has a copy here and one there.)
    func testEventDeletedInAppleCalendarDisappearsHere() {
        var app = launch()
        enableCalendarSync(app)
        addEvent(app)
        app.terminate()

        // Control: a second launch, nothing deleted. The event is still listed (from the saved store and the system calendar).
        app = launch()
        app.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(isListed(app), "control: the event is listed after a restart")
        app.terminate()

        // Now it is deleted in Apple Calendar (the hook removes the system copy, as the Calendar app would).
        app = launch(["-debugDeleteSystemEvent", title])
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 10), "Today loaded")
        sleep(3)
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(row(app).exists, "the local copy went with the Apple Calendar event")
    }

    /// Deleted here → gone from Apple Calendar too.
    func testEventDeletedHereIsDeletedInAppleCalendar() {
        var app = launch()
        enableCalendarSync(app)
        addEvent(app)
        app.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(isListed(app), "the new event is listed")
        row(app).tap()
        let delete = app.buttons["Delete event"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.terminate()

        // A new store would show the system copy if it were still there: this store has the local copy deleted too.
        app = launch()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 10))
        sleep(3)
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(row(app).exists, "gone from Apple Calendar as well")
    }
}
