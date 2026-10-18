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
        if el.identifier.hasPrefix("smart.") || el.identifier.hasPrefix("pinned.") { app.revealReminderPill(el) }
        el.press(forDuration: 1.0)
        let button = app.buttons[item].firstMatch
        // A press can pick the row up for reordering instead of opening the menu; a person would press again.
        if !button.waitForExistence(timeout: 5) { el.press(forDuration: 1.0) }
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
        app.revealReminderPill(completed)
        XCTAssertTrue(completed.exists)
        XCTAssertLessThan(element("list.Home").frame.minY - completed.frame.maxY, 160, "My Lists follows the pills closely")
    }

    /// The smart lists use the shared pill look (like Week / Month / Year and Alarms / World Clock): one row, never
    /// wrapped, the same 44pt tap height, left-aligned at the page gutter, and the row scrolls when it is too wide.
    func testSmartListPillsAreOneRowAndTappable() {
        let ids = ["smart.today", "smart.scheduled", "smart.all", "smart.flagged", "smart.completed"]
        let pills = ids.map { element($0) }
        XCTAssertTrue(pills[0].waitForExistence(timeout: 5))
        for pill in pills {
            XCTAssertTrue(pill.exists, "\(pill) is in the row")
            XCTAssertEqual(pill.frame.midY, pills[0].frame.midY, accuracy: 3, "all smart lists share one row")
            XCTAssertEqual(pill.frame.height, 44, accuracy: 1, "the shared 44pt tap height")
        }
        XCTAssertEqual(pills[0].frame.minX, 20, accuracy: 2, "left-aligned at the page gutter, like Calendar and Alarms")
        for (a, b) in zip(pills, pills.dropFirst()) {
            XCTAssertEqual(b.frame.minX - a.frame.maxX, 8, accuracy: 2, "the shared 8pt gap")
        }
        // Like the Alarms switcher it sits right under the tab pills, and My Lists follows without a gap.
        XCTAssertLessThan(abs(element("list.Home").frame.minY - pills[0].frame.maxY), 200)

        // Tappable: the first opens its list; the last one is reached by scrolling the row sideways.
        XCTAssertTrue(pills[0].isHittable)
        pills[0].tap()
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "a smart list screen is open")
        back.tap()
        XCTAssertTrue(pills[0].waitForExistence(timeout: 5))
        let completed = pills[4]
        app.revealReminderPill(completed)
        XCTAssertTrue(completed.isHittable, "scrolling the row sideways reaches Completed")
        completed.tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5), "Completed opened")
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
        app.revealReminderPill(element("pinned.Work"))
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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is up")
        let current = field.value as? String ?? ""
        XCTAssertEqual(current, "Work", "Rename starts with the current list name")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        // Native text fields may expose their placeholder as value when empty.
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND (value == '' OR value == placeholderValue)"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: 3), .completed, "the old name is cleared before typing")
        field.typeText("Office")
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Office'"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: 3), .completed, "the new name is fully entered")
        // The alert slides up when the keyboard shows; a tap on Save while it moves misses. A person would tap again.
        let save = alert.buttons["Save"]
        save.tap()
        if !alert.waitForNonExistence(timeout: 2), save.exists { save.tap() }
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Save closes the alert")
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
        app.revealReminderPill(pill)
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
        app.revealReminderPill(flagged)
        XCTAssertTrue(flagged.waitForExistence(timeout: 5))
        menu(flagged, "Hide “Flagged”")
        XCTAssertTrue(flagged.waitForNonExistence(timeout: 5), "Hide removes the pill")

        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["smartToggle.flagged"]
        app.revealSettingsRow(toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Settings lists the smart lists")
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        app.closeSidebar()
        app.revealReminderPill(flagged)
        XCTAssertTrue(flagged.waitForExistence(timeout: 5), "turned back on in Settings, the pill returns")
    }

    /// A smart-list pill moves with its menu (Move Left / Move Right, also the VoiceOver and keyboard way), and the
    /// order is the one Settings uses and is kept after a relaunch. Pills at the ends only offer the move that fits.
    func testMoveSmartListPillsWithTheMenuAndKeepTheOrder() {
        let today = element("smart.today"), scheduled = element("smart.scheduled")
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertLessThan(today.frame.minX, scheduled.frame.minX, "starts with Today before Scheduled")
        today.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Move Right"].firstMatch.waitForExistence(timeout: 5), "the pill's menu has Move Right")
        XCTAssertFalse(app.buttons["Move Left"].exists, "Today is first: nothing to move left")
        app.buttons["Move Right"].firstMatch.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in today.frame.minX > scheduled.frame.minX }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "Today now follows Scheduled")

        // Settings lists the smart lists in the same order.
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let toggles = ["smartToggle.scheduled", "smartToggle.today"].map { app.switches[$0] }
        for toggle in toggles {
            app.revealSettingsRow(toggle)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        }
        // Revealing Today scrolls the lazy Form again: both rows must still be on screen for the order comparison.
        for toggle in toggles {
            guard toggle.isFullyVisible(in: app.settingsRowViewport) else {
                XCTFail("both smart-list toggles must be fully visible before comparing their order")
                return
            }
            XCTAssertTrue(toggle.isHittable)
        }
        XCTAssertLessThan(toggles[0].frame.minY, toggles[1].frame.minY, "Settings shows Scheduled before Today too")
        app.buttons["Done"].firstMatch.tap()
        app.closeSidebar()

        app.terminate()
        app.launchArguments = TestData.launchArguments + ["-uiTestingKeepReminderPills"]
        app.launch()
        app.buttons["Reminders"].firstMatch.tap()
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        XCTAssertLessThan(scheduled.frame.minX, today.frame.minX, "the order is kept after a relaunch")
        XCTAssertEqual(scheduled.frame.midY, today.frame.midY, accuracy: 3, "still one row")
    }

    func testMovePinnedListPillsWithTheMenu() {
        for name in ["Home", "Work"] {
            let row = element("list.\(name)")
            reveal(row)
            menu(row, "Pin")
            app.revealReminderPill(element("pinned.\(name)"))
            XCTAssertTrue(element("pinned.\(name)").waitForExistence(timeout: 5))
            sleep(1)
        }
        let home = element("pinned.Home"), work = element("pinned.Work")
        XCTAssertLessThan(home.frame.minX, work.frame.minX, "pinned lists follow My Lists order")
        menu(work, "Move Left")
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in work.frame.minX < home.frame.minX }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "Work now sits before Home")
    }

    /// Press, hold, drag a smart-list pill onto another (the same gesture as My Lists rows).
    func testLongPressDragReordersSmartListPills() {
        let today = element("smart.today"), scheduled = element("smart.scheduled")
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertLessThan(today.frame.minX, scheduled.frame.minX)
        let start = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = scheduled.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 1.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.0)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in today.frame.minX > scheduled.frame.minX }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "Today now follows Scheduled")
    }

    func testLongPressDragReordersLists() {
        let home = element("list.Home"), work = element("list.Work")
        reveal(work)
        XCTAssertTrue(home.exists)
        XCTAssertLessThan(home.frame.minY, work.frame.minY, "starts with Home above Work")
        XCTAssertTrue(work.isFullyVisible(in: app.frame) && home.isFullyVisible(in: app.frame), "both drag cards are on screen")
        print("Reorder card frames: Home=\(home.frame), Work=\(work.frame), viewport=\(app.frame)")
        // Start lifting before the context menu has expanded over the destination card.
        // Keep the same real drag/drop and final order assertion on every screen size.
        let start = work.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.0)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in work.frame.minY < home.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "Work now sits above Home")
    }
}
