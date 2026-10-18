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
        home.tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5), "the Home list is open")
        app.buttons["Today"].firstMatch.tap()
        app.buttons["Reminders"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5), "still in the Home list after switching tabs")
        XCTAssertFalse(home.exists, "not back at the list of lists")

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
