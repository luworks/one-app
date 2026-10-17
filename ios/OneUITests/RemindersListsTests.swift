import XCTest

/// The Reminders tab's home: compact smart-list pills, My Lists and Add List, with no Edit button. Editing works as
/// everywhere else: press and hold a list for Rename / Color & Icon / Pin / Delete, press, hold and drag to reorder,
/// swipe from the right for Delete / Info / Pin. Runs against the test dataset (lists: Reminders, Home, Work).
final class RemindersListsTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
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

    /// Long-press a list and pick an item from its menu.
    private func menu(_ el: XCUIElement, _ item: String) {
        el.press(forDuration: 1.0)
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the long-press menu has \(item)")
        button.tap()
    }

    func testNoEditButtonAndCompactSmartLists() {
        XCTAssertFalse(app.buttons["Edit"].exists, "no Edit button on Reminders")
        XCTAssertFalse(element("reminders.edit").exists)
        let today = element("smart.today"), scheduled = element("smart.scheduled")
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(scheduled.exists)
        // Small pills side by side, right under the app's top bar (no empty band), My Lists close below.
        XCTAssertEqual(today.frame.midY, scheduled.frame.midY, accuracy: 2, "smart lists sit side by side")
        XCTAssertLessThan(today.frame.height, 50, "a pill, not a big card")
        XCTAssertLessThan(today.frame.minY, 170, "no empty band above the smart lists")
        let completed = element("smart.completed")
        XCTAssertTrue(completed.exists)
        XCTAssertLessThan(element("list.Home").frame.minY - completed.frame.maxY, 160, "My Lists follows the pills closely")
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
        work.swipeLeft()
        let pin = app.buttons["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3), "swipe from the right reveals Pin")
        pin.tap()
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(element("pinned.Work").waitForExistence(timeout: 5), "a pinned list joins the pills at the top")
    }

    func testLongPressRenamesAList() {
        let work = element("list.Work")
        reveal(work)
        menu(work, "Rename")
        let alert = app.alerts["Rename List"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "Rename asks for the new name")
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Office")
        alert.buttons["Save"].tap()
        let office = element("list.Office")
        reveal(office)
        XCTAssertTrue(office.exists, "the row shows the new name")
        XCTAssertFalse(element("list.Work").exists, "the old name is gone")
    }

    func testLongPressColorAndIconOpensTheListEditor() {
        let work = element("list.Work")
        reveal(work)
        menu(work, "Color & Icon")
        XCTAssertTrue(app.navigationBars["Name & Appearance"].waitForExistence(timeout: 5), "the list editor opens")
        app.navigationBars["Name & Appearance"].buttons["Cancel"].tap()
    }

    func testLongPressPinsAndUnpins() {
        let work = element("list.Work")
        reveal(work)
        menu(work, "Pin")
        let pill = element("pinned.Work")
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Pin puts the list with the pills at the top")
        sleep(1)   // let the row's menu finish closing before the next long press
        menu(pill, "Unpin")
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5), "Unpin from the pill's own menu removes it")
    }

    func testLongPressDeleteAsksFirst() {
        let home = element("list.Home")
        reveal(home)
        menu(home, "Delete")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "deleting a list asks first")
        XCTAssertTrue(alert.label.contains("Home"), alert.label)
        alert.buttons["Delete List, Keep Reminders"].tap()
        XCTAssertTrue(home.waitForNonExistence(timeout: 5), "Home is gone")
    }

    func testLongPressHidesASmartListAndSettingsBringsItBack() {
        let flagged = element("smart.flagged")
        XCTAssertTrue(flagged.waitForExistence(timeout: 5))
        menu(flagged, "Hide “Flagged”")
        XCTAssertTrue(flagged.waitForNonExistence(timeout: 5), "Hide removes the pill")

        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["smartToggle.flagged"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Settings lists the smart lists")
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        app.closeSidebar()
        XCTAssertTrue(flagged.waitForExistence(timeout: 5), "turned back on in Settings, the pill returns")
    }

    func testLongPressDragReordersLists() {
        let home = element("list.Home"), work = element("list.Work")
        reveal(work)
        XCTAssertTrue(home.exists)
        XCTAssertLessThan(home.frame.minY, work.frame.minY, "starts with Home above Work")
        // Hold until the row's menu is up, then drag without lifting: the menu gives way to the drag, as in Apple
        // Reminders. Drop on the top part of Home so Work lands above it.
        let start = work.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 1.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.0)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in work.frame.minY < home.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "Work now sits above Home")
    }
}
