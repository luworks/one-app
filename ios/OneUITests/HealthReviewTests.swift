import XCTest

/// The health line at the top of Today (sample Health data under `-uiTesting`), its detail sheet and its setting,
/// with the clock pinned using `-uiTestingNow`.
/// Today's reminders come from tests/fixtures/today-dataset.json: "Reply to Sam" planned 17:00, "Buy milk" due today,
/// "Take out the trash" 21:00, and three reminders completed when the dataset loads.
@MainActor
final class HealthReviewTests: XCTestCase {
  /// Settings survive between launches, so every test but the settings one pins "Health summary" on (argument domain).
  private func launch(at time: String, healthOn: Bool = true) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + ["-uiTestingNow", time]
      + (healthOn ? ["-today.setting.healthSummary", "YES"] : [])
    app.launch()
    return app
  }

  /// Today scrolls to the Now line; the health line sits above everything, so scroll back to the top for it.
  private func healthLine(_ app: XCUIApplication) -> XCUIElement {
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    let line = app.buttons["health.summary"]
    for _ in 0..<4 where !(line.exists && line.isHittable) { app.swipeDown() }
    return line
  }

  // MARK: Health line

  func testHealthLineOpensTheHealthSheet() {
    let app = launch(at: "09:41")
    let line = healthLine(app)
    XCTAssertTrue(line.waitForExistence(timeout: 5), "the health line shows on today")
    XCTAssertTrue(line.label.contains("steps"), "steps today: \(line.label)")
    XCTAssertTrue(line.label.contains("slept"), "last night's sleep: \(line.label)")
    line.tap()

    XCTAssertTrue(
      app.buttons["health.row.steps"].waitForExistence(timeout: 5), "the sheet lists the steps row")
    XCTAssertTrue(app.buttons["health.row.weight"].exists, "and the weight row")
    app.buttons["Done"].tap()
    XCTAssertTrue(line.waitForExistence(timeout: 3))
  }

  func testHealthLineOnlyOnToday() {
    let app = launch(at: "09:41")
    XCTAssertTrue(healthLine(app).waitForExistence(timeout: 5))
    app.buttons["Calendar"].firstMatch.tap()
    app.buttons["calendar.mode.week"].tap()
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
    let day = app.buttons[tomorrow.formatted(date: .complete, time: .omitted)].firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    day.tap()
    XCTAssertTrue(app.buttons["Back to today"].waitForExistence(timeout: 5))
    for _ in 0..<3 { app.swipeDown() }
    XCTAssertFalse(app.buttons["health.summary"].exists, "another day has no health line")
  }

  func testSettingTurnsTheLineOff() {
    let app = launch(at: "09:41", healthOn: false)
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    func openSetting() -> XCUIElement {
      app.openSidebar()
      let settings = app.buttons["Settings"].firstMatch
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      settings.tap()
      let toggle = app.switches["Health summary"]
      app.revealSettingsRow(toggle)
      sleep(1)  // let the sheet and the scroll come to rest, so the knob tap lands
      return toggle
    }
    func closeSettings() {
      sleep(1)  // the stored setting is written before the sheet goes away
      app.buttons["Done"].tap()
      app.closeSidebar()
      for _ in 0..<3 { app.swipeDown() }
    }
    // On (the default, or put back if an earlier run left it off): the line shows.
    var toggle = openSetting()
    if (toggle.value as? String) != "1" { toggle.toggleSwitch() }
    closeSettings()
    XCTAssertTrue(app.buttons["health.summary"].waitForExistence(timeout: 5))

    toggle = openSetting()
    toggle.toggleSwitch()
    closeSettings()
    XCTAssertFalse(
      app.buttons["health.summary"].waitForExistence(timeout: 2),
      "the line is gone when the setting is off")

    // Leave it on for the next run.
    toggle = openSetting()
    toggle.toggleSwitch()
    closeSettings()
    XCTAssertTrue(
      app.buttons["health.summary"].waitForExistence(timeout: 5), "and back when it is on")
  }

  // MARK: Screenshots (docs/qa/health-review), only with TEST_RUNNER_HEALTH_SHOTS=1

  func testScreenshots() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["HEALTH_SHOTS"] == "1", "screenshots only on request")
    let mode = ProcessInfo.processInfo.environment["HEALTH_SHOTS_MODE"] ?? "light"
    func shot(_ app: XCUIApplication, _ name: String) {
      sleep(1)
      let a = XCTAttachment(screenshot: app.screenshot())
      a.name = "\(name)-\(mode)"
      a.lifetime = .keepAlways
      add(a)
    }
    // Morning: the line at the top of Today, then its sheet.
    let app = launch(at: "08:30")
    XCTAssertTrue(healthLine(app).waitForExistence(timeout: 5))
    shot(app, "today-health-line")
    app.buttons["health.summary"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    shot(app, "health-sheet")
    app.swipeUp()
    app.swipeUp()
    shot(app, "health-sheet-sleep")
    app.terminate()
  }
}
