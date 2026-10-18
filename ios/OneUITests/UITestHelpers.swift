import XCTest

extension XCUIApplication {
    /// There is no avatar button: the sidebar opens with a swipe from the left edge, like in ChatGPT or Claude.
    func openSidebar() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// SwiftUI Form rows are lazy: scroll before requiring an off-screen control to exist.
    func revealSettingsRow(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Settings row is visible: \(element)", file: file, line: line)
    }

    /// The sidebar is a full screen with no Today row, and Settings opens over it, so after Settings the sidebar is still open.
    func closeSidebar() {
        let close = buttons["Close sidebar"]
        // A tap while the sidebar is still sliding open can be lost: tap again if it is still open.
        for _ in 0..<2 where close.waitForExistence(timeout: 3) {
            close.tap()
            if close.waitForNonExistence(timeout: 2) { break }
        }
        // The page slides back for a moment after the tap; a tap on it meanwhile is lost. Wait until it is back in place
        // (its menu button at the left edge again).
        let menu = buttons["Open menu"]
        let deadline = Date().addingTimeInterval(3)
        while menu.exists, menu.frame.minX > 30, Date() < deadline { usleep(100_000) }
    }
}

extension XCUIElement {
    /// Flips a switch by tapping its knob (a tap on the middle of a labeled switch can land on the label and do nothing)
    /// and waits for the new value, so the next line sees it.
    func toggleSwitch(file: StaticString = #filePath, line: UInt = #line) {
        let before = value as? String
        coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 3), .completed, "the switch flipped", file: file, line: line)
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
