import XCTest

/// Settings → Activity data (what is recorded, pause, export, clear) and the Activity screen's paging on the Activity store.
final class ActivityDataTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"] + extra
        app.launch()
    }

    private func openActivityData() {
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let row = app.buttons["settings.activityData"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Activity data"].waitForExistence(timeout: 5))
    }

    private func openActivityFromSidebar() {
        let row = app.buttons["Activity"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the sidebar has an Activity row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
    }

    /// Lists build rows lazily: swipe (fast) until the element is on screen.
    private func scrollTo(_ element: XCUIElement, swipes: Int = 40) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp(velocity: .fast) }
    }

    /// The page says where the data lives, pausing shows on the Activity screen, and Clear empties it.
    func testPageExplainsPausesAndClears() {
        launch(["-uiTestingActivityRows", "5"])
        openActivityData()
        XCTAssertEqual(app.switches["activity.pause"].value as? String, "0")
        XCTAssertTrue(app.switches["activity.tier.1"].exists, "one switch per category")
        let keep = app.switches["activity.keepChatText"]
        scrollTo(keep, swipes: 6)
        XCTAssertEqual(keep.value as? String, "0", "chat text is not kept unless asked")
        XCTAssertTrue(app.switches["activity.tier.4"].exists)
        let where_ = app.staticTexts["On this iPhone"]
        scrollTo(where_, swipes: 6)
        XCTAssertTrue(where_.exists, "says where it lives")
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }

        // Pause shows on the Activity screen, with the one-line note about where the data lives.
        app.switches["activity.pause"].toggleSwitch()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        openActivityFromSidebar()
        let note = app.staticTexts["activity.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.label.contains("Recording is paused"), note.label)
        XCTAssertTrue(note.label.contains("only on this iPhone"), note.label)
        XCTAssertTrue(app.staticTexts["Completed “Synthetic 0”"].exists, "recorded changes are still listed")
        app.buttons["Done"].tap()

        // Clear: confirmation names the count; afterwards Activity is empty.
        app.buttons["Settings"].firstMatch.tap()
        let row = app.buttons["settings.activityData"]
        scrollTo(row)
        row.tap()
        let clear = app.buttons["activity.clear"]
        scrollTo(clear)
        clear.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Clear ' AND label ENDSWITH ' Events'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "the confirmation names how many events go")
        confirm.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        openActivityFromSidebar()
        XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 3))
    }

    /// 400 changes: 150 per page, "Show more" until the end; nothing loads all at once.
    func testActivityPagesWithShowMore() {
        launch(["-uiTestingActivityRows", "400"])
        app.openSidebar()
        openActivityFromSidebar()
        XCTAssertTrue(app.staticTexts["Completed “Synthetic 0”"].waitForExistence(timeout: 5), "newest first")
        XCTAssertFalse(app.staticTexts["Completed “Synthetic 399”"].exists, "the oldest is not loaded yet")
        let more = app.buttons["Show more"]
        for page in 1...3 {
            scrollTo(more)
            XCTAssertTrue(more.exists, "page \(page) ends with Show more")
            more.tap()
        }
        XCTAssertTrue(more.waitForNonExistence(timeout: 3), "400 rows = 150 + 150 + 100: no more after the third tap")
        for _ in 0..<12 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Completed “Synthetic 399”"].waitForExistence(timeout: 3), "the oldest row is there")
    }

    /// While recording is paused nothing applies by itself under a grant (no Activity entry or Undo would exist), and the
    /// plan card still waits for a tap.
    func testPausedRecordingStopsAutomaticChanges() {
        launch(["-uiTestingGrant", "-uiTestingActivityPaused"])
        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Planned ' AND label ENDSWITH ' into free time'")).firstMatch
        XCTAssertTrue(app.staticTexts["Buy milk"].firstMatch.waitForExistence(timeout: 10), "Today is up")
        XCTAssertFalse(toast.waitForExistence(timeout: 4), "no automatic change while paused")
        app.openSidebar()
        openActivityFromSidebar()
        XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 3), "and nothing is recorded")
    }

    /// Export opens the system share sheet with a file.
    func testExportOpensTheShareSheet() {
        launch(["-uiTestingActivityRows", "3"])
        openActivityData()
        let jsonl = app.buttons["activity.export.jsonl"]
        scrollTo(jsonl)
        XCTAssertTrue(jsonl.isEnabled, "there is something to export")
        jsonl.tap()
        let sheet = app.otherElements["ActivityListView"]
        let copy = app.buttons["Copy"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8) || copy.waitForExistence(timeout: 2), "the share sheet appears")
    }
}
