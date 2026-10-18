import XCTest

/// Leaving a tab and coming back finds it where it was: the open list in Reminders, Week / Month / Year in Calendar.
final class TabMemoryTests: XCTestCase {
    func testTabsKeepTheirPlace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()

        // Reminders: open the Home list, go to Today, come back.
        app.buttons["Reminders"].firstMatch.tap()
        let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home, '")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        let originalHomeY = home.frame.minY
        home.tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5), "the Home list is open")
        app.buttons["Today"].firstMatch.tap()
        app.buttons["Reminders"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5), "still in the Home list after switching tabs")
        XCTAssertFalse(home.exists, "not back at the list of lists")

        // The native compact header retains list actions and sidebar access.
        app.buttons["More"].tap()
        app.buttons["Name & Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Name & Appearance"].waitForExistence(timeout: 5))
        app.navigationBars["Name & Appearance"].buttons["Cancel"].tap()
        app.buttons["Open menu"].tap()
        XCTAssertTrue(app.buttons["Close sidebar"].waitForExistence(timeout: 5), "the menu opens the sidebar while a list is pushed")
        app.closeSidebar()
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5), "back returns to My Lists")
        XCTAssertEqual(home.frame.minY, originalHomeY, accuracy: 2, "the parent list keeps its position")
        home.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(home.waitForExistence(timeout: 5), "the native edge swipe still returns to My Lists")

        // Calendar: switch to Month, go to Alarms, come back.
        app.buttons["Calendar"].firstMatch.tap()
        let month = app.segmentedControls.buttons["Month"].exists ? app.segmentedControls.buttons["Month"] : app.buttons["Month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendar.monthTitle"].waitForExistence(timeout: 5))
        app.buttons["Clock"].firstMatch.tap()
        app.buttons["Calendar"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendar.monthTitle"].waitForExistence(timeout: 5),
                      "Calendar comes back in Month, not reset to Week")
    }
}
