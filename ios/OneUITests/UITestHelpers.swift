import XCTest

extension XCUIApplication {
    /// There is no avatar button: the sidebar opens with a swipe from the left edge, like in ChatGPT or Claude.
    func openSidebar() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// The sidebar is a full screen with no Today row, and Settings opens over it, so after Settings the sidebar is still open.
    func closeSidebar() {
        let close = buttons["Close sidebar"]
        if close.waitForExistence(timeout: 3) { close.tap() }
    }
}

/// The test dataset in the repo: tests/fixtures/today-dataset.json (chats, reminders, events, alarms around today).
enum TestData {
    static let path = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "tests/fixtures/today-dataset.json").path

    /// Launch arguments for a fresh in-memory store filled from the dataset.
    static var launchArguments: [String] { ["-uiTesting", "-dataset", path] }
}

extension XCTestCase {
    /// Turns on Apple Calendar in Settings (sidebar > Settings), answering the access prompt the first time. Does nothing
    /// when it is already on. Leaves the sidebar closed.
    func enableCalendarSync(_ app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "Calendar access") { alert in
            for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Apple Calendar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow Full Access", "Allow"] {
                let b = springboard.buttons[label]
                if b.waitForExistence(timeout: 3) { b.tap(); break }
            }
        }
        sleep(1)
        app.buttons["Done"].tap()
        app.closeSidebar()
    }

    /// The Month grid's identifier for a day cell.
    func calendarDayID(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "day.%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
