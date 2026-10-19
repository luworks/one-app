import XCTest

/// The Health dashboard under `-uiTesting`: global native reorder, persistence, visibility and chart detail.
/// Synthetic history comes from HealthSampleSeries; scenario inputs are versioned in tests/fixtures.
/// Mindful Minutes has no data in the sample (the "—" row) and Body Fat was last measured 12 days ago (a stale date).
@MainActor
final class HealthMetricsTests: XCTestCase {
  private func launch(_ extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + [
        "-uiTestingNow", "09:41", "-today.setting.healthSummary", "YES",
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US_POSIX",
      ]
      + extra
    app.launch()
    return app
  }

  /// Opens the Health sheet from the line at the top of Today.
  @discardableResult
  private func openSheet(_ app: XCUIApplication) -> XCUIElement {
    let line = app.buttons["health.summary"]
    _ = app.wait(for: .runningForeground, timeout: 5)
    for _ in 0..<4 where !(line.exists && line.isHittable) { app.swipeDown() }
    XCTAssertTrue(line.waitForExistence(timeout: 5), "the health line shows on today")
    line.tap()
    let steps = app.buttons["health.row.steps"]
    XCTAssertTrue(steps.waitForExistence(timeout: 5), "the sheet lists the metrics")
    return steps
  }

  private func row(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.buttons["health.row.\(id)"]
  }

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
    XCTAssertTrue(
      row(app, "steps").label.hasSuffix("Today"), "a quiet date label: \(row(app, "steps").label)")
    XCTAssertTrue(app.staticTexts["health.sample"].exists, "sample data says so")
    // Dense: the three defaults and Add Metric fit one screen, rows about 60 pt.
    let steps = row(app, "steps").frame
    let weight = row(app, "weight").frame
    XCTAssertLessThan(steps.height, 72, "a compact row, not a card")
    XCTAssertLessThan(
      weight.maxY - steps.minY, 360, "three metrics with their group headers in about 340 pt")
  }

  // MARK: Detail

  func testTapOpensDetailWithRangeSwitch() {
    let app = launch()
    openSheet(app)
    row(app, "steps").tap()
    let value = app.otherElements["health.detail.value"].firstMatch
    XCTAssertTrue(
      value.waitForExistence(timeout: 5) || app.staticTexts["health.detail.value"].exists,
      "big latest value")
    XCTAssertTrue(app.navigationBars["Steps"].exists)
    for days in [7, 30, 90] {
      XCTAssertTrue(app.buttons["health.range.\(days)"].exists, "\(days) days")
    }
    XCTAssertTrue(app.otherElements["health.detail.chart"].firstMatch.exists, "a chart")
    XCTAssertTrue(
      app.otherElements["health.fact.average"].firstMatch.exists
        || app.staticTexts["Average"].exists, "average")
    XCTAssertTrue(app.staticTexts["Low"].exists && app.staticTexts["High"].exists, "low and high")

    app.buttons["health.range.7"].tap()
    XCTAssertTrue(app.buttons["health.range.7"].isSelected, "7 days is selected")
    let change = app.staticTexts["health.detail.change"]
    XCTAssertTrue(change.waitForExistence(timeout: 3), "change against the 7 days before")
    XCTAssertTrue(change.label.hasSuffix("vs previous 7 days"), change.label)
    app.buttons["health.range.90"].tap()
    XCTAssertTrue(app.buttons["health.range.90"].isSelected)
    // The history includes the lookback before the visible 90-day range.
    XCTAssertTrue(
      app.staticTexts["health.detail.change"].exists, "earlier sample data supports the comparison")

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
      XCTAssertTrue(
        legend.label.contains(days == 90 ? "14-day average" : "7-day average"), legend.label)
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
    for _ in 0..<4 where !weightToggle.isHittable || weightToggle.frame.maxY > app.frame.maxY - 60 {
      app.swipeUp()
    }
    XCTAssertTrue(
      app.switches["health.pick.weight"].waitForExistence(timeout: 5),
      "hidden, not deleted: it can be added again")
    weightToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    XCTAssertEqual(weightToggle.value as? String, "1")
    app.buttons["health.pick.add"].tap()
    XCTAssertTrue(row(app, "weight").waitForExistence(timeout: 5))
  }

  func testHidingSleepMakesTheTodayLineUseTheNextMetric() {
    let app = launch()
    let line = app.buttons["health.summary"]
    let initial = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND label CONTAINS 'slept'"), object: line)
    XCTAssertEqual(
      XCTWaiter().wait(for: [initial], timeout: 5), .completed,
      "the initial Today summary includes sleep")
    openSheet(app)
    row(app, "sleep").press(forDuration: 1.0)
    // The native menu item is a PopUpButton on some OS snapshots.
    let hide = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Hide'"))
      .firstMatch
    XCTAssertTrue(hide.waitForExistence(timeout: 3), "the long-press menu has Hide")
    hide.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(row(app, "sleep").waitForNonExistence(timeout: 3))
    app.buttons["Done"].tap()

    let updated = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS 'steps' AND NOT (label CONTAINS 'slept')"),
      object: line)
    XCTAssertEqual(
      XCTWaiter().wait(for: [updated], timeout: 5), .completed,
      "no sleep in the line: \(line.label)")
    XCTAssertTrue(
      line.label.contains("kg") || line.label.contains("lb"),
      "steps plus the next shown metric (weight): \(line.label)")
  }

  // MARK: Order

  /// Drags the native List reorder handle, retaining geometry and hierarchy for diagnosis.
  /// There is no preference injection or accessibility action standing in for the gesture.
  private func dragMetric(
    _ app: XCUIApplication, source: XCUIElement, above target: XCUIElement, name: String
  ) {
    XCTAssertTrue(source.exists && target.exists)
    let sourceCell = app.cells.containing(.any, identifier: source.identifier).firstMatch
    let sourceFrame = sourceCell.exists ? sourceCell.frame : source.frame
    let targetCell = app.cells.containing(.any, identifier: target.identifier).firstMatch
    let targetFrame = targetCell.exists ? targetCell.frame : target.frame
    XCTAssertGreaterThan(sourceFrame.height, 0)
    XCTAssertGreaterThan(targetFrame.height, 0)
    let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Reorder'"))
      .allElementsBoundByIndex
    let nativeHandle = handles.first {
      $0.frame.midY >= sourceFrame.minY && $0.frame.midY <= sourceFrame.maxY
    }
    let handleDescription = handles.map { "\($0.label): \($0.frame)" }.joined(separator: "\n")
    let evidence = XCTAttachment(
      string:
        "source=\(sourceFrame), target=\(targetFrame)\nNative handles:\n\(handleDescription)\n\(app.debugDescription)"
    )
    evidence.name = "\(name)-before-hierarchy"
    evidence.lifetime = .keepAlways
    add(evidence)
    capture(app, "\(name)-before")
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let handle: XCUICoordinate
    if let nativeHandle {
      handle = nativeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    } else {
      // Some runtimes omit the system handle from AX. Its fallback belongs to the List cell,
      // whose trailing edge includes the handle; the content button's edge does not.
      XCTAssertTrue(sourceCell.exists, "native handle fallback requires the containing List cell")
      handle = origin.withOffset(
        CGVector(dx: sourceCell.frame.maxX - 22, dy: sourceCell.frame.midY))
    }
    let destination = origin.withOffset(
      CGVector(dx: handle.screenPoint.x, dy: targetFrame.minY + 2))
    // Recorded events showed touch-up at the exact arrival timestamp, before UIKit's gap settled.
    handle.press(
      forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.5)
    capture(app, "\(name)-after")
    XCTAssertFalse(app.buttons["health.detail.done"].exists, "drag must not navigate to detail")
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func assertAbove(_ upper: XCUIElement, _ lower: XCUIElement, _ message: String) {
    let moved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        upper.exists && lower.exists && upper.frame.minY < lower.frame.minY
      }, object: nil)
    XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, message)
  }

  private func dashboardArguments(_ scenario: String) throws -> [String] {
    let data = try Data(
      contentsOf: URL(fileURLWithPath: TestData.fixturePath("health-dashboard-ui.json")))
    let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let scenarios = try XCTUnwrap(document["scenarios"] as? [String: [String: Any]])
    let input = try XCTUnwrap(scenarios[scenario])
    return try XCTUnwrap(input["launchArguments"] as? [String])
  }

  func testOrderSurvivesARelaunch() throws {
    var app = launch(try dashboardArguments("crossGroupOrder"))
    openSheet(app)
    assertAbove(row(app, "steps"), row(app, "weight"), "Steps initially precedes Weight")
    app.buttons["health.customize"].tap()
    XCTAssertEqual(app.buttons["health.customize"].label, "Done Customizing")
    dragMetric(
      app, source: row(app, "weight"), above: row(app, "steps"), name: "weight-above-steps")
    app.buttons["health.customize"].tap()
    assertAbove(
      row(app, "weight"), row(app, "steps"), "Weight crosses former Body / Activity boundaries")
    app.buttons["Done"].tap()
    openSheet(app)
    assertAbove(row(app, "weight"), row(app, "steps"), "dismissal preserves global order")
    app.terminate()

    app = launch(["-uiTestingKeepHealthMetrics"])
    openSheet(app)
    assertAbove(row(app, "weight"), row(app, "steps"), "relaunch preserves global order")
    row(app, "weight").tap()
    XCTAssertTrue(app.buttons["health.range.90"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Weight"].exists, "reordered row retains its detail")
  }

  func testManageMetricsReordersAndSearchesHiddenMetrics() throws {
    let app = launch(try dashboardArguments("crossGroupOrder"))
    openSheet(app)
    app.buttons["health.add"].tap()
    let weight = app.descendants(matching: .any)["health.pick.row.weight"].firstMatch
    let steps = app.descendants(matching: .any)["health.pick.row.steps"].firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    app.buttons["health.pick.customize"].tap()
    dragMetric(app, source: weight, above: steps, name: "manage-weight-above-steps")
    app.buttons["health.pick.customize"].tap()
    assertAbove(weight, steps, "Manage Metrics uses the same global order")
    let search = app.searchFields["Search Metrics"]
    XCTAssertTrue(search.exists)
    search.tap()
    search.typeText("Mindful")
    let mindful = app.switches["health.pick.mindfulMinutes"]
    XCTAssertTrue(mindful.waitForExistence(timeout: 5), "hidden metrics are discoverable by search")
    XCTAssertEqual(mindful.value as? String, "0")
    mindful.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    XCTAssertEqual(mindful.value as? String, "1")
    let closeSearch = app.buttons["close"]
    XCTAssertTrue(
      closeSearch.waitForExistence(timeout: 3), "native search exposes its close control")
    closeSearch.tap()
    XCTAssertTrue(app.buttons["health.pick.add"].waitForExistence(timeout: 3))
    app.buttons["health.pick.add"].tap()
    XCTAssertTrue(row(app, "mindfulMinutes").waitForExistence(timeout: 5))
    assertAbove(row(app, "weight"), row(app, "steps"), "picker order is committed to the dashboard")
    app.buttons["health.add"].tap()
    XCTAssertEqual(app.switches["health.pick.mindfulMinutes"].value as? String, "1")
    app.buttons["health.pick.add"].tap()
  }

  func testNoReadableMetricKeepsOtherDataAndExplainsEmptyDetail() throws {
    let app = launch(try dashboardArguments("noReadableMetric"))
    openSheet(app)
    let mindful = row(app, "mindfulMinutes")
    XCTAssertTrue(mindful.waitForExistence(timeout: 5))
    XCTAssertTrue(mindful.label.contains("No data"), mindful.label)
    XCTAssertFalse(mindful.label.localizedCaseInsensitiveContains("denied"))
    XCTAssertTrue(
      row(app, "steps").label.contains("steps"), "one empty metric does not hide readable data")
    mindful.tap()
    XCTAssertTrue(app.staticTexts["No data in the last 30 days."].waitForExistence(timeout: 5))
    app.buttons["health.range.90"].tap()
    XCTAssertTrue(app.staticTexts["No data in the last 90 days."].waitForExistence(timeout: 5))
    app.buttons["health.detail.done"].tap()
    XCTAssertTrue(row(app, "steps").waitForExistence(timeout: 5))
  }

  func testLargeTypeKeepsCustomizationAndDetailReachable() throws {
    let app = launch(try dashboardArguments("largeType"))
    openSheet(app)
    let customize = app.buttons["health.customize"]
    XCTAssertTrue(customize.isHittable)
    customize.tap()
    XCTAssertEqual(customize.label, "Done Customizing")
    XCTAssertGreaterThanOrEqual(row(app, "steps").frame.height, 44)
    row(app, "steps").tap()
    XCTAssertFalse(
      app.buttons["health.detail.done"].exists, "tapping while customizing cannot open detail")
    XCTAssertEqual(customize.label, "Done Customizing")
    capture(app, "health-large-type-customizing")
    customize.tap()
    row(app, "steps").tap()
    XCTAssertTrue(app.buttons["health.range.90"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["health.detail.done"].isHittable)
  }

  func testHealthEventRecordsReadOnlyAfterUserAction() throws {
    let data = try Data(
      contentsOf: URL(fileURLWithPath: TestData.fixturePath("health-records.json")))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let families = try XCTUnwrap(fixture["families"] as? [String: [String: Any]])
    let categories = try XCTUnwrap(families["categories"])
    let expectedLabels = try XCTUnwrap(categories["expectedLabels"] as? [String])
    let app = launch()
    openSheet(app)
    let records = app.buttons["health.records"]
    for _ in 0..<3 where !records.isHittable { app.swipeUp() }
    XCTAssertTrue(records.waitForExistence(timeout: 5))
    records.tap()
    let events = app.buttons["health.records.categories"]
    XCTAssertTrue(events.waitForExistence(timeout: 5))
    events.tap()
    let read = app.buttons["health.records.read"]
    XCTAssertTrue(read.waitForExistence(timeout: 5))
    XCTAssertEqual(read.label, "Read Health Events")
    XCTAssertFalse(
      app.staticTexts["Handwashing"].exists, "opening a family does not read its records")
    read.tap()
    XCTAssertTrue(app.staticTexts["Stand Hour"].waitForExistence(timeout: 5))
    XCTAssertEqual(read.label, "Refresh")
    for title in expectedLabels {
      let record = app.staticTexts[title]
      for _ in 0..<3 where !record.isHittable { app.swipeUp() }
      XCTAssertTrue(record.exists, "typed category record: \(title)")
    }
    XCTAssertFalse(app.staticTexts["health.records.error"].exists)
    capture(app, "health-events-synthetic-records")
  }

  func testStaleReadingShowsItsDateNotToday() {
    let app = launch(["-uiTestingHealthMetrics", "steps,bodyFat"])
    openSheet(app)
    let body = row(app, "bodyFat")
    XCTAssertTrue(body.waitForExistence(timeout: 5))
    XCTAssertTrue(body.label.contains("%"), body.label)
    XCTAssertFalse(
      body.label.hasSuffix("Today") || body.label.hasSuffix("Yesterday"),
      "measured 12 days ago: \(body.label)")
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
    XCTAssertTrue(
      row(app, "steps").waitForExistence(timeout: 5),
      "Settings → Health metrics shows the same list")
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
      try? screenshot.pngRepresentation.write(
        to: URL(fileURLWithPath: dir).appending(path: "\(name)-\(mode).png"))
      let a = XCTAttachment(screenshot: screenshot)
      a.name = "\(name)-\(mode)"
      a.lifetime = .keepAlways
      add(a)
    }
    let app = launch([
      "-uiTestingHealthMetrics",
      "steps,sleep,weight,restingHeartRate,activeEnergy,bodyFat,mindfulMinutes",
    ])
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
