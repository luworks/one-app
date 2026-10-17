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
