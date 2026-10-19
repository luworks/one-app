import XCTest

/// The Health sheet as a compact metrics list (sample Health data under `-uiTesting`): the default rows, the detail with
/// its 7 / 30 / 90 day switch, Add Metric, Hide and the order surviving a relaunch. The clock is pinned with `-uiTestingNow`.
/// Mindful Minutes has no data in the sample (the "—" row) and Body Fat was last measured 12 days ago (a stale date).
@MainActor
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
        // The history includes the lookback before the visible 90-day range.
        XCTAssertTrue(app.staticTexts["health.detail.change"].exists, "earlier sample data supports the comparison")

        app.buttons["health.detail.done"].tap()
        XCTAssertTrue(app.buttons["health.row.steps"].waitForExistence(timeout: 3), "back on the list")
    }

    func testMovingAverageAppearsForWeightButNotSteps() {
        let app = launch()
        openSheet(app)
        row(app, "weight").tap()
        let legend = app.descendants(matching: .any)["health.detail.legend"].firstMatch
        let trend = app.descendants(matching: .any)["health.fact.trend"].firstMatch
        XCTAssertTrue(legend.waitForExistence(timeout: 5))
        XCTAssertTrue(legend.label.contains("7-day average"), legend.label)
        XCTAssertTrue(trend.exists, "reading metrics show the latest average and range change")
        XCTAssertTrue(trend.label.contains("over 30 days"), trend.label)
        for days in [7, 90, 30] {
            app.buttons["health.range.\(days)"].tap()
            XCTAssertTrue(legend.label.contains(days == 90 ? "14-day average" : "7-day average"), legend.label)
            XCTAssertTrue(trend.label.contains("over \(days) days"), trend.label)
        }
        app.buttons["health.detail.done"].tap()
        XCTAssertTrue(row(app, "steps").waitForExistence(timeout: 3))
        row(app, "steps").tap()
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 3))
        XCTAssertFalse(legend.exists, "daily totals have no moving-average legend")
        XCTAssertFalse(trend.exists, "daily totals keep their existing range facts")
    }

    // MARK: Add Metric, Hide

    func testMetricTogglesShowCurrentVisibilityAndPersistChanges() {
        var app = launch()
        openSheet(app)
        app.buttons["health.add"].tap()
        let steps = app.switches["health.pick.steps"]
        let energy = app.switches["health.pick.activeEnergy"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        XCTAssertEqual(steps.value as? String, "1", "shown metrics start enabled")
        XCTAssertEqual(energy.value as? String, "0", "hidden metrics start disabled")
        steps.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(steps.value as? String, "0")
        energy.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(energy.value as? String, "1")
        app.buttons["health.pick.add"].tap()
        XCTAssertTrue(row(app, "steps").waitForNonExistence(timeout: 5))
        XCTAssertTrue(row(app, "activeEnergy").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "activeEnergy").label.contains("kcal"))
        app.terminate()

        app = launch(["-uiTestingKeepHealthMetrics"])
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let link = app.buttons["settings.healthMetrics"]
        app.revealSettingsRow(link)
        link.tap()
        XCTAssertTrue(row(app, "activeEnergy").waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "steps").exists)
        app.buttons["health.add"].tap()
        XCTAssertEqual(app.switches["health.pick.steps"].value as? String, "0")
        XCTAssertEqual(app.switches["health.pick.activeEnergy"].value as? String, "1")
        app.buttons["health.pick.add"].tap()
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
        let weightToggle = app.switches["health.pick.weight"]
        for _ in 0..<4 where !weightToggle.isHittable || weightToggle.frame.maxY > app.frame.maxY - 60 { app.swipeUp() }
        XCTAssertTrue(app.switches["health.pick.weight"].waitForExistence(timeout: 5), "hidden, not deleted: it can be added again")
        weightToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(weightToggle.value as? String, "1")
        app.buttons["health.pick.add"].tap()
        XCTAssertTrue(row(app, "weight").waitForExistence(timeout: 5))
    }

    func testHidingSleepMakesTheTodayLineUseTheNextMetric() {
        let app = launch()
        let line = app.buttons["health.summary"]
        let initial = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS 'slept'"), object: line)
        XCTAssertEqual(XCTWaiter().wait(for: [initial], timeout: 5), .completed,
                       "the initial Today summary includes sleep")
        openSheet(app)
        row(app, "sleep").press(forDuration: 1.0)
        // The native menu item is a PopUpButton on some OS snapshots.
        let hide = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Hide'")).firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 3), "the long-press menu has Hide")
        hide.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(row(app, "sleep").waitForNonExistence(timeout: 3))
        app.buttons["Done"].tap()

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
        app.revealSettingsRow(link)
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
        XCTAssertTrue(app.switches["health.pick.daylight"].waitForExistence(timeout: 5))
        app.switches["health.pick.daylight"].tap()
        shot(app, "add-metric")
    }
}
