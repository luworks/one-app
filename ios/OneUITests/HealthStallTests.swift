import XCTest

/// Add Metric must never leave the Health sheet on a spinner, even when Apple Health stalls. The mock source can hang on
/// purpose: `-uiTestingHealthStall <ids>` (those metrics' queries never answer), `-uiTestingHealthAuthStall <ids>`
/// (asking for access to them never answers: Apple's permission sheet that cannot show). Each call is cut off after 8 s.
final class HealthStallTests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41", "-today.setting.healthSummary", "YES"] + extra
        app.launch()
        return app
    }

    private func openSheet(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        let line = app.buttons["health.summary"]
        for _ in 0..<4 where !(line.exists && line.isHittable) { app.swipeDown() }
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()
        XCTAssertTrue(app.buttons["health.row.steps"].waitForExistence(timeout: 5))
    }

    private func add(_ app: XCUIApplication, _ id: String) {
        app.buttons["health.add"].tap()
        XCTAssertTrue(app.buttons["health.pick.\(id)"].waitForExistence(timeout: 3), "the picker appears")
        XCTAssertFalse(app.activityIndicators.firstMatch.exists && !app.buttons["health.pick.\(id)"].exists, "no sheet-wide spinner")
        app.buttons["health.pick.\(id)"].tap()
        app.buttons["health.pick.add"].tap()
    }

    func testStalledQueryGivesAFallbackRowAndOthersKeepData() {
        let app = launch(["-uiTestingHealthStall", "restingHeartRate"])
        openSheet(app)
        add(app, "restingHeartRate")
        add(app, "activeEnergy")

        // The new rows are on screen at once; the list never turns into a spinner.
        XCTAssertTrue(app.buttons["health.row.restingHeartRate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["health.row.steps"].exists, "the list stays")
        // Within ~10 s the stalled row falls back, and the other metric shows its data.
        let note = app.staticTexts["health.note.restingHeartRate"]
        XCTAssertTrue(note.waitForExistence(timeout: 12), "fallback line on the stalled row")
        XCTAssertEqual(note.label, "Can't read this yet. Check Health access.")
        XCTAssertTrue(app.buttons["health.action.restingHeartRate"].exists, "an action to try again")
        XCTAssertTrue(app.buttons["health.row.activeEnergy"].label.contains("kcal"), app.buttons["health.row.activeEnergy"].label)
        XCTAssertTrue(app.buttons["health.row.steps"].label.contains("steps"), "other rows still show data")
    }

    func testAccessThatNeverAnswersStillAddsTheRow() {
        let app = launch(["-uiTestingHealthAuthStall", "bodyFat"])
        openSheet(app)
        add(app, "bodyFat")
        XCTAssertTrue(app.buttons["health.row.bodyFat"].waitForExistence(timeout: 5), "the row is added at once")
        XCTAssertTrue(app.buttons["health.row.steps"].exists)
        // The mock has data for body fat, so after the timeout it shows it; nothing is stuck on a spinner.
        let loaded = NSPredicate(format: "label CONTAINS '%'")
        let done = XCTNSPredicateExpectation(predicate: loaded, object: app.buttons["health.row.bodyFat"])
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 12), .completed, app.buttons["health.row.bodyFat"].label)
        XCTAssertFalse(app.progressIndicators["health.row.loading.bodyFat"].exists)
    }
}
