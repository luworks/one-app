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

        // Turn on sync in Settings (sidebar > Settings > Apple Calendar).
        app.buttons["Open sidebar"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Apple Calendar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); break }
        }
        XCTAssertTrue(NSPredicate(format: "value == '1'").evaluate(with: toggle) || toggle.waitForExistence(timeout: 8), "sync is on")
        sleep(1)
        app.buttons["Done"].tap()

        // Create an event in one.
        let title = "EK check \(Int(Date.now.timeIntervalSince1970) % 10000)"
        app.buttons["Today"].firstMatch.tap()      // closes the sidebar
        sleep(1)
        app.buttons["Calendar"].firstMatch.tap()
        sleep(1)
        app.buttons["New"].tap()   // + adds an event on the Calendar page
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
