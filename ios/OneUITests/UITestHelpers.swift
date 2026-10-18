import XCTest

extension XCUIApplication {
    /// There is no avatar button: the sidebar opens with a swipe from the left edge, like in ChatGPT or Claude.
    func openSidebar() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Smart lists and pinned lists share one horizontal row. Search both ways because its offset survives navigation
    /// and its order can change. Drag within that row so the app's tab swipe gesture is not used.
    func revealReminderPill(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        func visible(_ pill: XCUIElement) -> Bool {
            pill.isFullyVisible(in: frame) && pill.isHittable
        }
        if visible(target) { return }
        let pills = descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'smart.' OR identifier BEGINSWITH 'pinned.'"))
        let startsTowardsEnd = !target.exists || target.frame.minX >= frame.minX
        for towardsEnd in [startsTowardsEnd, !startsTowardsEnd] {
            for _ in 0..<12 {
                if visible(target) { return }
                guard let anchor = pills.allElementsBoundByIndex.first(where: { visible($0) }) else {
                    XCTFail("No visible reminder pill to scroll", file: file, line: line)
                    return
                }
                let y = anchor.frame.midY - frame.minY
                let from = coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width * (towardsEnd ? 0.85 : 0.15), dy: y))
                let to = coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width * (towardsEnd ? 0.15 : 0.85), dy: y))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
        }
        XCTAssertTrue(visible(target), "Reminder pill is on screen and hittable: \(target)", file: file, line: line)
    }

    /// The Form can extend behind its navigation bar and home indicator. Only accept rows inside its usable viewport.
    var settingsRowViewport: CGRect {
        let screen = frame
        let form = collectionViews.allElementsBoundByIndex.last(where: { $0.isFullyVisible(in: screen) })
        var viewport = form?.frame.intersection(screen) ?? screen
        let navigation = navigationBars["Settings"]
        let top = navigation.exists ? max(viewport.minY, navigation.frame.maxY + 8) : viewport.minY
        let bottom = min(viewport.maxY, screen.maxY - 44)
        viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
        return viewport
    }

    /// SwiftUI Form rows are lazy: scroll before requiring an off-screen control to exist or be hittable.
    func revealSettingsRow(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        func visible() -> Bool {
            element.isFullyVisible(in: settingsRowViewport) && element.isHittable
        }
        for _ in 0..<12 {
            if visible() { return }
            let viewport = settingsRowViewport
            let towardsTop = element.exists && element.frame.minY < viewport.minY
            let origin = coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - frame.minX,
                dy: viewport.minY - frame.minY + viewport.height * (towardsTop ? 0.35 : 0.8)))
            let end = origin.withOffset(CGVector(dx: viewport.midX - frame.minX,
                dy: viewport.minY - frame.minY + viewport.height * (towardsTop ? 0.8 : 0.35)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(visible(), "Settings row is fully visible and hittable: \(element)", file: file, line: line)
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
    /// Check geometry before isHittable: XCTest can throw while deriving an off-screen element's activation point.
    func isFullyVisible(in viewport: CGRect) -> Bool {
        guard exists else { return false }
        let bounds = frame
        guard !bounds.isNull, !bounds.isEmpty, !viewport.isNull, !viewport.isEmpty,
              [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY,
               viewport.minX, viewport.minY, viewport.maxX, viewport.maxY].allSatisfy({ $0.isFinite }) else { return false }
        return viewport.contains(bounds)
    }

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
