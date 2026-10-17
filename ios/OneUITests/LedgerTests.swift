import XCTest

/// The Activity ledger and automatic changes under a grant. Runs on the test dataset with the clock pinned at 09:41,
/// so "Buy milk" and "Water the plants" (due today, no time) have free time to go into.
/// Set TEST_RUNNER_LEDGER_SHOTS=<folder> (and TEST_RUNNER_LEDGER_SHOTS_SUFFIX=light / dark) for `testScreenshots`.
final class LedgerTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"] + extra
        app.launch()
    }

    private func text(_ predicate: String, _ args: CVarArg...) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: predicate, argumentArray: args)).firstMatch
    }

    private func openActivity() {
        app.openSidebar()
        let row = app.buttons["Activity"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the sidebar has an Activity row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
    }

    /// Settings is a long form: scroll down until the row is on screen.
    private func settingsRow(_ id: String) -> XCUIElement {
        let el = app.buttons[id]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp() }
        return el
    }

    private func planMyDay() {
        app.buttons["Ask AI or add anything"].tap()
        let chip = app.buttons.matching(identifier: "ask-suggestion").matching(NSPredicate(format: "label == %@", "Plan my day")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
    }

    /// Activity lists an AI change the user applied and a delete the user made, and Undo there brings the reminder back.
    func testActivityListsAnAIApplyAndAUserDeleteWithUndo() {
        launch()
        let row = app.staticTexts["Call the bank"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 1) { delete.tap() }
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "swipe deletes the reminder")

        planMyDay()
        XCTAssertTrue(app.buttons["plan.always"].waitForExistence(timeout: 5), "a Today-only card offers Always for 7 days")
        app.buttons["plan.apply"].tap()
        XCTAssertTrue(text("label BEGINSWITH 'Planned ' AND label ENDSWITH 'for today.'").waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        openActivity()
        let deleted = text("label == %@", "Deleted “Call the bank”")
        XCTAssertTrue(deleted.waitForExistence(timeout: 5), "the user's delete is listed")
        XCTAssertTrue(text("label == %@", "Planned “Buy milk”").exists, "the AI plan the user applied is listed")
        XCTAssertTrue(text("label CONTAINS 'Today AI · Approved'").exists, "marked as Today AI, approved by the user")
        XCTAssertTrue(text("label CONTAINS 'Not planned → '").exists, "with before → after")

        // Filters: AI hides the user's delete; You shows it again.
        app.buttons["activity.filter.AI"].tap()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 3))
        app.buttons["activity.filter.You"].tap()
        XCTAssertTrue(deleted.waitForExistence(timeout: 3))

        let undo = app.buttons["Undo Deleted “Call the bank”"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "the delete can be undone from Activity")
        undo.tap()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("label == %@", "Undid “Call the bank”").waitForExistence(timeout: 3), "the undo is recorded too")
        app.buttons["Done"].tap()
        app.closeSidebar()
        XCTAssertTrue(app.staticTexts["Call the bank"].firstMatch.waitForExistence(timeout: 5), "the reminder is back on Today")
    }

    /// Under a grant, reminders due today without a time go into free time by themselves, with a toast, Undo and Activity entries.
    func testGrantAutoAppliesWithToastAndCanBeRevoked() {
        launch(["-uiTestingGrant"])
        let toast = text("label BEGINSWITH 'Planned ' AND label ENDSWITH ' into free time'")
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "the automatic change shows a toast")
        XCTAssertTrue(app.buttons["Undo"].exists, "with Undo")

        openActivity()
        app.buttons["activity.filter.AI"].tap()
        XCTAssertTrue(text("label == %@", "Planned “Buy milk”").waitForExistence(timeout: 5))
        XCTAssertTrue(text("label CONTAINS 'Today AI · Automatic'").exists, "marked automatic")
        XCTAssertFalse(text("label == %@", "Planned “Pay studio invoice”").exists, "overdue reminders are never moved by themselves")
        XCTAssertTrue(app.buttons["activity.undo"].firstMatch.exists, "and each can be undone")
        app.buttons["Done"].tap()

        app.buttons["Settings"].firstMatch.tap()
        let automatic = settingsRow("settings.automaticChanges")
        XCTAssertTrue(automatic.exists)
        automatic.tap()
        XCTAssertTrue(app.staticTexts["Plan reminders into free time"].waitForExistence(timeout: 5), "the grant is listed")
        XCTAssertTrue(text("label BEGINSWITH 'Until '").exists, "with its end date")
        app.buttons["grant.revoke"].tap()
        XCTAssertTrue(app.staticTexts["None. AI changes wait for your tap."].waitForExistence(timeout: 3), "Revoke ends it")
    }

    /// "Always for 7 days" on the plan card applies it now and gives the grant.
    func testAlwaysForSevenDaysAppliesAndGrants() {
        launch()
        planMyDay()
        let always = app.buttons["plan.always"]
        XCTAssertTrue(always.waitForExistence(timeout: 5))
        always.tap()
        XCTAssertTrue(text("label BEGINSWITH 'For the next 7 days'").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ask-undo"].exists, "the applied plan can be undone")
        app.buttons["Close"].firstMatch.tap()
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let automatic = settingsRow("settings.automaticChanges")
        XCTAssertTrue(automatic.label.contains("1 on"), "one grant is on: \(automatic.label)")
    }

    /// Light and dark screenshots for design review (run once per appearance).
    func testScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["LEDGER_SHOTS"] else { throw XCTSkip("set TEST_RUNNER_LEDGER_SHOTS") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let suffix = ProcessInfo.processInfo.environment["LEDGER_SHOTS_SUFFIX"] ?? "light"
        func shot(_ name: String) {
            usleep(500_000)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(suffix).png"))
        }
        launch(["-uiTestingGrant"])
        XCTAssertTrue(text("label ENDSWITH ' into free time'").waitForExistence(timeout: 10))
        shot("1-auto-toast")
        let row = app.staticTexts["Call the bank"].firstMatch
        row.swipeLeft()
        if app.buttons["Delete"].waitForExistence(timeout: 1) { app.buttons["Delete"].tap() }
        _ = row.waitForNonExistence(timeout: 5)
        openActivity()
        shot("2-activity")
        app.buttons["Done"].tap()
        app.buttons["Settings"].firstMatch.tap()
        settingsRow("settings.automaticChanges").tap()
        XCTAssertTrue(app.staticTexts["Plan reminders into free time"].waitForExistence(timeout: 5))
        shot("3-automatic-changes")
        app.buttons["grant.revoke"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.closeSidebar()
        planMyDay()
        XCTAssertTrue(app.buttons["plan.always"].waitForExistence(timeout: 5))
        shot("4-plan-card")
    }
}
