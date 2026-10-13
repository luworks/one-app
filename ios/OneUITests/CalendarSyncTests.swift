import XCTest

/// Calendar claim 10: events saved to the system calendar come back as system events after a fresh start.
final class CalendarSyncTests: XCTestCase {
    func testEventRoundTripsThroughSystemCalendar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Calendar access") { alert in
            for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        // Turn on sync from the sidebar.
        app.buttons["Open sidebar"].tap()
        let toggle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show Apple Calendar'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if !toggle.label.hasSuffix("On") { toggle.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); break }
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show Apple Calendar' AND label ENDSWITH 'On'"))
            .firstMatch.waitForExistence(timeout: 8), "sync is on")

        // Create an event in one.
        let title = "EK check \(Int(Date.now.timeIntervalSince1970) % 10000)"
        app.buttons["Today"].firstMatch.tap()
        sleep(1)
        app.buttons["New"].tap()
        app.buttons["New event"].tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["Done"].tap()

        // Fresh in-memory store: the event can only come from the system calendar now.
        app.terminate()
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        // Earlier runs leave events in the simulator's calendar, so the row may be further down the list.
        var found = row.waitForExistence(timeout: 5)
        for _ in 0..<6 where !found {
            app.swipeUp()
            found = row.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(found, "event read back from the system calendar")
    }
}
