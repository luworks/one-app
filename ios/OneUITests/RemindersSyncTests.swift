import XCTest

/// Apple Reminders sync: a reminder added in Today reaches Apple Reminders. A fresh in-memory store can only
/// get it back by pulling it from the system, so finding it after another relaunch proves the round trip.
/// Slow and tied to the simulator's Reminders permission, so it is its own test case. It avoids typing
/// (simulator keyboard focus is flaky): the reminder is added through the `-uiTestingAddReminder` launch argument.
final class RemindersSyncTests: XCTestCase {
    private func launch(adding title: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (title.map { ["-uiTestingAddReminder", $0] } ?? [])
        app.launch()
        return app
    }

    func testReminderRoundTripsThroughAppleReminders() throws {
        // 1. Turn sync on in Settings and allow access.
        var app = launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.buttons["Open sidebar"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let sync = app.switches["Apple Reminders"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        if (sync.value as? String) != "1" {
            sync.tap()
            for name in ["Allow Full Access", "Allow"] {
                let allow = springboard.buttons[name]
                if allow.waitForExistence(timeout: 5) { allow.tap(); break }
            }
        }
        sleep(2)
        XCTAssertEqual(sync.value as? String, "1", "sync is on")
        app.terminate()

        // 2. Relaunch with a new reminder (created after connecting, so it uploads); give the debounced sync time.
        let title = "RS check \(Int(Date.now.timeIntervalSince1970) % 100000)"
        app = launch(adding: title)
        sleep(10)
        app.terminate()

        // 3. Fresh in-memory store: the reminder can only come back from Apple Reminders.
        app = launch()
        sleep(8)
        app.buttons["Reminders"].firstMatch.tap()
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 8))
        all.tap()
        let row = app.staticTexts[title]
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the reminder came back from Apple Reminders (looked for \(title))")
    }
}
