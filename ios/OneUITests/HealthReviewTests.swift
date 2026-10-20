import XCTest

/// The health line at the top of Today (sample Health data under `-uiTesting`), its detail sheet and its setting,
/// and the evening "Review today" from the Tomorrow section. The clock is pinned with `-uiTestingNow`.
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

  private func scrollToReview(
    _ app: XCUIApplication, expectingReview: Bool = false
  ) -> XCUIElement {
    let header = app.buttons["tomorrowHeader"]
    let viewport = app.collectionViews.firstMatch.frame
    for _ in 0..<8 where !(header.exists && header.isFullyVisible(in: viewport)) {
      app.swipeUp()
    }
    XCTAssertTrue(header.waitForExistence(timeout: 5), "Today ends with a Tomorrow section")
    if header.value as? String == "Collapsed" { header.tap() }
    let target = expectingReview ? app.buttons["reviewToday"] : header
    for _ in 0..<4 where !(target.exists && target.isFullyVisible(in: viewport)) { app.swipeUp() }
    return app.buttons["reviewToday"]
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

  // MARK: Review today

  func testNoReviewBeforeTheEvening() {
    let app = launch(at: "09:41")
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    XCTAssertFalse(scrollToReview(app).exists, "Review today shows from 18:00")
  }

  func testEveningReviewMovesAndDropsWithOneUndo() {
    let app = launch(at: "19:30")
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    let review = scrollToReview(app, expectingReview: true)
    XCTAssertTrue(
      review.waitForExistence(timeout: 3), "the Tomorrow section offers Review today in the evening"
    )
    review.tap()

    let headline = app.staticTexts["review.headline"]
    XCTAssertTrue(headline.waitForExistence(timeout: 5))
    XCTAssertTrue(headline.label.hasSuffix("done"), headline.label)
    XCTAssertTrue(app.staticTexts["Send invoice"].exists, "what got done today is listed")
    let apply = app.buttons["review.apply"]
    XCTAssertFalse(apply.isEnabled, "nothing to apply until a choice changes")

    choose(app, row: "Reply to Sam", "Tomorrow")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tomorrow '")).firstMatch
        .waitForExistence(timeout: 3),
      "the preview says when it moves to")
    choose(app, row: "Buy milk", "Drop")
    XCTAssertTrue(apply.isEnabled)
    let firstTomorrow = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS 'Weekly review'")
    ).firstMatch
    for _ in 0..<3 where !(firstTomorrow.exists && firstTomorrow.isHittable) { app.swipeUp() }
    XCTAssertTrue(firstTomorrow.exists, "tomorrow's first item shows at the end")
    apply.tap()

    let toast = app.staticTexts["Moved 1, dropped 1"]
    XCTAssertTrue(toast.waitForExistence(timeout: 5), "one toast for the whole review")
    XCTAssertFalse(app.staticTexts["review.headline"].exists, "the sheet closes after Apply")
    app.buttons["Undo"].tap()
    XCTAssertTrue(toast.waitForNonExistence(timeout: 3))

    // Undo put both back: open the review again and find them still left today.
    let again = scrollToReview(app, expectingReview: true)
    XCTAssertTrue(again.waitForExistence(timeout: 3))
    again.tap()
    XCTAssertTrue(app.buttons["review.choice.Reply to Sam"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["review.choice.Buy milk"].exists)
    app.buttons["Close"].tap()
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
    var app = launch(at: "08:30")
    XCTAssertTrue(healthLine(app).waitForExistence(timeout: 5))
    shot(app, "today-health-line")
    app.buttons["health.summary"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    shot(app, "health-sheet")
    app.swipeUp()
    app.swipeUp()
    shot(app, "health-sheet-sleep")
    app.terminate()

    // Evening: Review today in the Tomorrow section, then the review with two choices made.
    app = launch(at: "19:30")
    let review = scrollToReview(app, expectingReview: true)
    XCTAssertTrue(review.waitForExistence(timeout: 3))
    let bottom = app.windows.firstMatch.frame.maxY - 200
    for _ in 0..<6 where review.frame.maxY > bottom { app.swipeUp() }
    shot(app, "tomorrow-review-entry")
    review.tap()
    XCTAssertTrue(app.staticTexts["review.headline"].waitForExistence(timeout: 5))
    shot(app, "review-sheet")
    choose(app, row: "Reply to Sam", "Tomorrow")
    choose(app, row: "Buy milk", "Drop")
    app.swipeUp()
    shot(app, "review-choices")
  }

  /// Opens a row's menu and picks a choice in it.
  private func choose(_ app: XCUIApplication, row: String, _ choice: String) {
    let menu = app.buttons["review.choice.\(row)"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5), "row \(row)")
    for _ in 0..<3 where !menu.isHittable { app.swipeUp() }
    menu.tap()
    let item = app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != 'tomorrowHeader'", choice)
    ).firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 3), "menu offers \(choice)")
    item.tap()
    let picked = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", choice), object: menu)
    XCTAssertEqual(
      XCTWaiter().wait(for: [picked], timeout: 3), .completed, "\(row) shows \(choice)")
  }
}
