import XCTest

/// Apple Reminders sync: a reminder added in Today reaches Apple Reminders. A fresh in-memory store
/// can only get it back by pulling it from the system, so finding it after a relaunch proves the round trip.
/// Slow and tied to the simulator's Reminders permission, so it is its own test case.
final class RemindersSyncTests: XCTestCase {
    func testReminderRoundTripsThroughAppleReminders() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Turn sync on from the sidebar and allow access if asked.
        app.buttons["Open sidebar"].tap()
        let sync = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync Apple Reminders'")).firstMatch
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        if !sync.label.hasSuffix("On") {
            sync.tap()
            for name in ["Allow Full Access", "Allow"] {
                let allow = springboard.buttons[name]
                if allow.waitForExistence(timeout: 5) { allow.tap(); break }
            }
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync Apple Reminders' AND label ENDSWITH 'On'"))
            .firstMatch.waitForExistence(timeout: 8), "sync is on")
        app.buttons["Today"].firstMatch.tap()      // closes the sidebar
        sleep(1)

        // Add a reminder in Today (+ adds a reminder on Today).
        let title = "RS check \(Int(Date.now.timeIntervalSince1970) % 100000)"
        app.buttons["New"].tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["Done"].tap()
        sleep(8)                                    // sync is debounced; give it time to reach Apple

        // Fresh in-memory store: the reminder can only come back from Apple Reminders.
        app.terminate()
        app.launch()
        sleep(6)
        app.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText(title)
        let found = app.staticTexts[title].waitForExistence(timeout: 10)
        let seen = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
        XCTAssertTrue(found, "the reminder came back from Apple Reminders (looked for \(title); saw: \(seen))")
    }
}
