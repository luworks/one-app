import XCTest

/// The Reminders tab's My Lists: Add List is visible and tappable, a swipe pins a list, a long press lifts a row
/// and dropping it on another row reorders. Run against the in-memory sample data (lists: Home, Work, ...).
final class RemindersListsTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.buttons["Reminders"].firstMatch.tap()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// Scrolls until the element exists, is hittable and clear of the bottom bar.
    private func reveal(_ el: XCUIElement) {
        for _ in 0..<5 where !el.exists || !el.isHittable || el.frame.maxY > app.frame.height - 140 {
            app.swipeUp()
        }
        XCTAssertTrue(el.waitForExistence(timeout: 5), "missing \(el)")
    }

    func testAddListIsVisibleAndCreatesAList() {
        let add = app.buttons["addList"]
        reveal(add)
        XCTAssertTrue(add.isHittable, "Add List is not covered by the bottom bar")
        add.tap()
        let name = app.textFields["List Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the New List sheet opens")
        name.typeText("Errands")
        app.navigationBars["New List"].buttons["Done"].tap()
        let created = element("list.Errands")
        reveal(created)   // My Lists is lazy: the new row is only built once it scrolls into view
        XCTAssertTrue(created.exists, "the new list shows in My Lists")
    }

    func testSwipePinsAListToTheTop() {
        let work = element("list.Work")
        reveal(work)
        work.swipeLeft()   // every row action comes from the trailing edge (RowActions)
        let pin = app.buttons["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3), "swipe left reveals Pin")
        pin.tap()
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(element("pinned.Work").waitForExistence(timeout: 5), "a pinned list becomes a card at the top")
    }

    func testLongPressDragReordersLists() {
        let home = element("list.Home"), work = element("list.Work")
        reveal(work)
        XCTAssertTrue(home.exists)
        XCTAssertLessThan(home.frame.minY, work.frame.minY, "starts with Home above Work")
        // Hold on the target a moment so the drop lands on Home, as a finger would.
        work.press(forDuration: 1.0, thenDragTo: home, withVelocity: .slow, thenHoldForDuration: 1.0)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in work.frame.minY < home.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "Work now sits above Home")
    }
}
