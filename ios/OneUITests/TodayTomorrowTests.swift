import XCTest

/// Today ends with a short look at tomorrow: its first few items by day, all of it from 18:00.
/// The clock is pinned with `-uiTestingNow`, so the tests behave the same at any time of day.
/// Tomorrow's items come from tests/fixtures/today-dataset.json (Weekly review 10:00, Weekly sync 11:00,
/// Design review 14:00, plus Standup and alarms on weekdays).
final class TodayTomorrowTests: XCTestCase {
    private func launch(at time: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", time]
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// The Tomorrow section sits at the end of the list; scroll until its header is on screen.
    private func scrollToTomorrow(_ app: XCUIApplication) -> XCUIElement {
        let header = app.buttons["tomorrowHeader"]
        for _ in 0..<8 where !(header.exists && header.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Today ends with a Tomorrow section")
        // Bring the rows under the header into view too.
        app.swipeUp()
        return header
    }

    func testMorningShowsTheStartOfTomorrow() {
        let app = launch(at: "09:41")
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        _ = scrollToTomorrow(app)
        XCTAssertTrue(text(app, "Weekly review").waitForExistence(timeout: 3), "tomorrow's first event shows")

        let more = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' more'")).firstMatch
        // How many items tomorrow has depends on the weekday (Standup and alarms), so "more" may not be needed.
        if more.exists {
            XCTAssertFalse(app.buttons["Show less"].exists, "only the first few items show by day")
            more.tap()
            XCTAssertTrue(app.buttons["Show less"].waitForExistence(timeout: 3), "more shows the rest of tomorrow")
            XCTAssertFalse(more.exists)
        }
        XCTAssertTrue(text(app, "Design review").waitForExistence(timeout: 3))
    }

    func testEveningShowsAllOfTomorrow() {
        let app = launch(at: "19:30")
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        _ = scrollToTomorrow(app)
        XCTAssertTrue(text(app, "Weekly review").waitForExistence(timeout: 3))
        XCTAssertTrue(text(app, "Design review").waitForExistence(timeout: 3), "from 18:00 all of tomorrow shows")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label ENDSWITH ' more'")).firstMatch.exists)
    }

    func testHeaderOpensTomorrowAsItsOwnDay() {
        let app = launch(at: "09:41")
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        scrollToTomorrow(app).tap()
        XCTAssertTrue(app.buttons["Back to today"].waitForExistence(timeout: 5), "tomorrow opens as a day of its own")
        XCTAssertFalse(app.buttons["tomorrowHeader"].exists, "only today shows a Tomorrow section")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(app.staticTexts["todayDate"].label, tomorrow.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                       "the open day's date shows on top")
        XCTAssertFalse(app.staticTexts["Due today"].exists)
        app.buttons["Back to today"].tap()
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    }
}
