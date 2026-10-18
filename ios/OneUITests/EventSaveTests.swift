import XCTest

/// Save is a completion action even when an existing event has no edits.
final class EventSaveTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func calendar(_ app: XCUIApplication) {
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar.mode.month"].tap()
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'agenda.row' AND label BEGINSWITH %@", title)).firstMatch
    }

    func testExistingNativeEventUnchangedSaveCloses() {
        nativeSave(changed: false)
    }

    func testExistingNativeEventChangedSaveClosesAndPersists() {
        nativeSave(changed: true)
    }

    func testExistingNativeEventSaveFailureKeepsEditor() {
        nativeSave(changed: true, failing: true)
    }

    private func nativeSave(changed: Bool, failing: Bool = false) {
        let title = "Save check \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        let base = TestData.fixtureArguments("event-save.json") + ["-uiTestingCalendarSync", "-uiTestingCalendarSaveMetadata", "-appearance", "dark"]
            + (failing ? ["-uiTestingEventSaveFailure"] : [])
        app.launchArguments = base
        app.launch()
        enableCalendarSync(app)
        app.terminate()
        app.launchArguments = base + ["-debugCreateSystemEvent", title]
        app.launch()
        calendar(app)
        let event = row(app, title)
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        event.tap()
        let editor = app.staticTexts["Edit Event"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let savedTitle = changed ? title + " updated" : title
        if changed {
            let field = app.textFields["title-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.tap()
            field.typeText(" updated")
        }
        app.buttons["Done"].tap()
        if failing {
            let error = app.staticTexts["event.save.error"]
            XCTAssertTrue(error.waitForExistence(timeout: 3))
            XCTAssertTrue(error.label.contains("Calendar is temporarily unavailable"))
            XCTAssertTrue(editor.exists, "a failed save keeps the editor and draft open")
            XCTAssertEqual(app.textFields["title-field"].value as? String, savedTitle)
            app.buttons["Cancel"].tap()
            app.terminate()
            app.launchArguments = base + ["-debugDeleteSystemEvent", title]
            app.launch()
            return
        }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "successful checkmark save returns to Calendar")
        XCTAssertTrue(app.buttons["calendar.mode.month"].isHittable)
        app.terminate()
        app.launchArguments = base
        app.launch()
        calendar(app)
        XCTAssertTrue(row(app, savedTitle).waitForExistence(timeout: 10), "saved event survives a fresh local store")
        row(app, savedTitle).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["https://example.com/calendar-save"].exists, "unedited URL survives saving")
        XCTAssertTrue(app.staticTexts["2 alerts"].exists, "all original alerts survive saving")
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value == %@", "Preserve event notes")).firstMatch.exists
                      || app.textFields.matching(NSPredicate(format: "value == %@", "Preserve event notes")).firstMatch.exists,
                      "unedited notes survive saving")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = base + ["-debugDeleteSystemEvent", savedTitle]
        app.launch()
        XCTAssertTrue(app.buttons["Calendar"].firstMatch.waitForExistence(timeout: 5))
    }

    func testExistingLocalEventUnchangedSaveCloses() {
        let app = XCUIApplication()
        app.launchArguments = TestData.fixtureArguments("event-save.json")
        app.launch()
        calendar(app)
        let event = row(app, "Local save fixture")
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()
        XCTAssertTrue(app.textFields["event.title"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textFields["event.title"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar.mode.month"].isHittable)
        event.tap()
        XCTAssertEqual(app.textFields["event.title"].value as? String, "Local save fixture")
    }
}
