import XCTest

extension XCUIApplication {
    /// There is no avatar button: the sidebar opens with a swipe from the left edge, like in ChatGPT or Claude.
    func openSidebar() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
