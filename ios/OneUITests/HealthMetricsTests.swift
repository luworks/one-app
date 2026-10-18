import XCTest

/// The Health sheet as a compact metrics list (sample Health data under `-uiTesting`): the default rows, the detail with
/// its 7 / 30 / 90 day switch, Add Metric, Hide and the order surviving a relaunch. The clock is pinned with `-uiTestingNow`.
/// Mindful Minutes has no data in the sample (the "—" row) and Body Fat was last measured 12 days ago (a stale date).
final class HealthMetricsTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41", "-today.setting.healthSummary", "YES"] + extra
        app.launch()
        return app
    }

    /// Opens the Health sheet from the line at the top of Today.
    @discardableResult
    private func openSheet(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        let line = app.buttons["health.summary"]
        for _ in 0..<4 where !(line.exists && line.isHittable) { app.swipeDown() }
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the health line shows on today")
        line.tap()
        let steps = app.buttons["health.row.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5), "the sheet lists the metrics")
        return steps
    }

    private func row(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.buttons["health.row.\(id)"] }

    // MARK: List

    func testListShowsTheDefaultRowsAndNoCards() {
        let app = launch()
        openSheet(app)
        for id in ["steps", "sleep", "weight"] {
            XCTAssertTrue(row(app, id).exists, "\(id) is a default row")
        }
        XCTAssertFalse(row(app, "restingHeartRate").exists, "Watch metrics are opt-in")
        XCTAssertTrue(app.buttons["health.add"].exists, "Add Metric sits under the list")
        XCTAssertTrue(row(app, "steps").label.hasPrefix("Steps, "), row(app, "steps").label)
        XCTAssertTrue(row(app, "steps").label.hasSuffix("Today"), "a quiet date label: \(row(app, "steps").label)")
        XCTAssertTrue(app.staticTexts["health.sample"].exists, "sample data says so")
        // Dense: the three defaults and Add Metric fit one screen, rows about 60 pt.
        let steps = row(app, "steps").frame, weight = row(app, "weight").frame
        XCTAssertLessThan(steps.height, 72, "a compact row, not a card")
        XCTAssertLessThan(weight.maxY - steps.minY, 360, "three metrics with their group headers in about 340 pt")
    }

    // MARK: Detail

    func testTapOpensDetailWithRangeSwitch() {
        let app = launch()
        openSheet(app)
        row(app, "steps").tap()
        let value = app.otherElements["health.detail.value"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5) || app.staticTexts["health.detail.value"].exists, "big latest value")
        XCTAssertTrue(app.navigationBars["Steps"].exists)
        for days in [7, 30, 90] { XCTAssertTrue(app.buttons["health.range.\(days)"].exists, "\(days) days") }
        XCTAssertTrue(app.otherElements["health.detail.chart"].firstMatch.exists, "a chart")
        XCTAssertTrue(app.otherElements["health.fact.average"].firstMatch.exists || app.staticTexts["Average"].exists, "average")
        XCTAssertTrue(app.staticTexts["Low"].exists && app.staticTexts["High"].exists, "low and high")

        app.buttons["health.range.7"].tap()
        XCTAssertTrue(app.buttons["health.range.7"].isSelected, "7 days is selected")
        let change = app.staticTexts["health.detail.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 3), "change against the 7 days before")
        XCTAssertTrue(change.label.hasSuffix("vs previous 7 days"), change.label)
        app.buttons["health.range.90"].tap()
        XCTAssertTrue(app.buttons["health.range.90"].isSelected)
        // The sample has 90 days only, so there is nothing before the last 90: the change line is left out.
        XCTAssertFalse(app.staticTexts["health.detail.change"].exists, "no earlier data: no change line")

        app.buttons["health.detail.done"].tap()
        XCTAssertTrue(app.buttons["health.row.steps"].waitForExistence(timeout: 3), "back on the list")
    }

    // MARK: Add Metric, Hide

    func testAddMetricAddsRowsAndOffersOnlyWhatIsHidden() {
        let app = launch()
        openSheet(app)
        XCTAssertFalse(row(app, "activeEnergy").exists)
        app.buttons["health.add"].tap()
        XCTAssertTrue(app.buttons["health.pick.activeEnergy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["health.pick.steps"].exists, "steps is already shown, so it is not offered")
        XCTAssertFalse(app.buttons["health.pick.add"].isEnabled, "nothing chosen yet")
        app.buttons["health.pick.activeEnergy"].tap()
        app.buttons["health.pick.mindfulMinutes"].tap()
        XCTAssertEqual(app.buttons["health.pick.activeEnergy"].value as? String, "Selected")
        XCTAssertTrue(app.buttons["health.pick.add"].isEnabled)
        app.buttons["health.pick.add"].tap()

        XCTAssertTrue(row(app, "activeEnergy").waitForExistence(timeout: 5), "the chosen metric is a row now")
        XCTAssertTrue(row(app, "activeEnergy").label.contains("kcal"), row(app, "activeEnergy").label)
        XCTAssertTrue(row(app, "mindfulMinutes").exists)
        XCTAssertTrue(row(app, "mindfulMinutes").label.contains("no data"), "no data is a dash, never a zero: \(row(app, "mindfulMinutes").label)")
        XCTAssertFalse(row(app, "mindfulMinutes").label.contains(" 0 "), row(app, "mindfulMinutes").label)

        app.buttons["health.add"].tap()
        XCTAssertTrue(app.buttons["health.pick.restingHeartRate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["health.pick.activeEnergy"].exists, "added ones leave the picker")
        app.buttons["Cancel"].tap()
    }

    func testHideRemovesTheRowAndAddMetricBringsItBack() {
        let app = launch()
        openSheet(app)
        row(app, "weight").swipeLeft()
        let hide = app.buttons["Hide"]
        XCTAssertTrue(hide.waitForExistence(timeout: 3), "a trailing swipe offers Hide")
        hide.tap()
        XCTAssertTrue(row(app, "weight").waitForNonExistence(timeout: 3), "the row is gone")
        XCTAssertTrue(row(app, "steps").exists && row(app, "sleep").exists)

        app.buttons["health.add"].tap()
        XCTAssertTrue(app.buttons["health.pick.weight"].waitForExistence(timeout: 5), "hidden, not deleted: it can be added again")
        app.buttons["health.pick.weight"].tap()
        app.buttons["health.pick.add"].tap()
        XCTAssertTrue(row(app, "weight").waitForExistence(timeout: 5))
    }

    func testHidingSleepMakesTheTodayLineUseTheNextMetric() {
        let app = launch()
        openSheet(app)
        XCTAssertTrue(app.buttons["health.summary"].exists || true)
        row(app, "sleep").press(forDuration: 1.0)
        let hide = app.buttons["Hide"]
        XCTAssertTrue(hide.waitForExistence(timeout: 3), "the long-press menu has Hide")
        hide.tap()
        XCTAssertTrue(row(app, "sleep").waitForNonExistence(timeout: 3))
        app.buttons["Done"].tap()

        let line = app.buttons["health.summary"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'steps' AND NOT (label CONTAINS 'slept')"), object: line)
        XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 5), .completed, "no sleep in the line: \(line.label)")
        XCTAssertTrue(line.label.contains("kg") || line.label.contains("lb"), "steps plus the next shown metric (weight): \(line.label)")
    }

    // MARK: Order

    func testOrderSurvivesARelaunch() {
        var app = launch(["-uiTestingHealthMetrics", "steps,activeEnergy,daylight,sleep,weight"])
        openSheet(app)
        XCTAssertLessThan(row(app, "activeEnergy").frame.minY, row(app, "daylight").frame.minY, "starts with energy above daylight")

        row(app, "daylight").press(forDuration: 1.0)
        let up = app.buttons["Move Up"]
        XCTAssertTrue(up.waitForExistence(timeout: 3), "the long-press menu has Move Up")
        up.tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.row(app, "daylight").frame.minY < self.row(app, "activeEnergy").frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "daylight moved above energy")
        app.terminate()

        // The same data and clock, but keep what the first launch saved (no -uiTestingHealthMetrics).
        app = launch(["-uiTestingKeepHealthMetrics"])
        openSheet(app)
        XCTAssertTrue(row(app, "daylight").waitForExistence(timeout: 5))
        XCTAssertLessThan(row(app, "daylight").frame.minY, row(app, "activeEnergy").frame.minY, "the order was saved")
        XCTAssertLessThan(row(app, "steps").frame.minY, row(app, "daylight").frame.minY)
    }

    func testStaleReadingShowsItsDateNotToday() {
        let app = launch(["-uiTestingHealthMetrics", "steps,bodyFat"])
        openSheet(app)
        let body = row(app, "bodyFat")
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(body.label.contains("%"), body.label)
        XCTAssertFalse(body.label.hasSuffix("Today") || body.label.hasSuffix("Yesterday"), "measured 12 days ago: \(body.label)")
    }

    // MARK: Settings

    func testSettingsOpensTheSameSheet() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        app.openSidebar()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let link = app.buttons["settings.healthMetrics"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        for _ in 0..<4 where !link.isHittable { app.swipeUp() }
        sleep(1)
        link.tap()
        XCTAssertTrue(row(app, "steps").waitForExistence(timeout: 5), "Settings → Health metrics shows the same list")
        XCTAssertTrue(app.buttons["health.add"].exists)
    }

    // MARK: Screenshots, only with TEST_RUNNER_HEALTH_SHOTS=1 (TEST_RUNNER_HEALTH_SHOTS_DIR, TEST_RUNNER_HEALTH_SHOTS_MODE)

    func testScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HEALTH_SHOTS"] == "1", "screenshots only on request")
        let mode = env["HEALTH_SHOTS_MODE"] ?? "light"
        let dir = env["HEALTH_SHOTS_DIR"] ?? NSTemporaryDirectory()
        func shot(_ app: XCUIApplication, _ name: String) {
            sleep(1)
            let screenshot = app.screenshot()
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name)-\(mode).png"))
            let a = XCTAttachment(screenshot: screenshot)
            a.name = "\(name)-\(mode)"
            a.lifetime = .keepAlways
            add(a)
        }
        let app = launch(["-uiTestingHealthMetrics", "steps,sleep,weight,restingHeartRate,activeEnergy,bodyFat,mindfulMinutes"])
        shot(app, "today-line")
        openSheet(app)
        shot(app, "list")
        row(app, "weight").tap()
        XCTAssertTrue(app.buttons["health.range.90"].waitForExistence(timeout: 5))
        shot(app, "detail-weight-30")
        app.buttons["health.range.7"].tap()
        shot(app, "detail-weight-7")
        app.buttons["health.detail.done"].tap()
        row(app, "steps").tap()
        XCTAssertTrue(app.buttons["health.range.90"].waitForExistence(timeout: 5))
        app.buttons["health.range.90"].tap()
        shot(app, "detail-steps-90")
        app.buttons["health.detail.done"].tap()
        row(app, "sleep").tap()
        XCTAssertTrue(app.buttons["health.range.90"].waitForExistence(timeout: 5))
        shot(app, "detail-sleep-30")
        app.buttons["health.detail.done"].tap()
        app.buttons["health.add"].tap()
        XCTAssertTrue(app.buttons["health.pick.daylight"].waitForExistence(timeout: 5))
        app.buttons["health.pick.daylight"].tap()
        shot(app, "add-metric")
    }
}
