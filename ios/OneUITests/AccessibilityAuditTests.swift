import XCTest

/// Real system audits plus semantic/action assertions; no issue filter or violation suppression.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  private func audit(_ app: XCUIApplication) throws {
    try app.performAccessibilityAudit(for: .all) { issue in
      let details =
        "\(issue.compactDescription)\n\(issue.detailedDescription)\n"
        + (issue.element?.debugDescription ?? "No element supplied by the system audit")
      let attachment = XCTAttachment(string: details + "\nApplication:\n" + app.debugDescription)
      attachment.name = "Accessibility issue and element geometry"
      attachment.lifetime = .keepAlways
      self.add(attachment)
      print("AX_AUDIT_ISSUE \(details)")
      return false
    }
  }

  private func launch(largeType: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + [
        "-uiTestingNow", "09:41", "-appearance", "light",
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US_POSIX",
        "-today.setting.healthSummary", "YES",
        "-UIPreferredContentSizeCategoryName",
        largeType ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
      ]
    app.launch()
    addTeardownBlock { app.terminate() }
    XCTAssertTrue(app.staticTexts["weekStrip.month"].waitForExistence(timeout: 10))
    return app
  }

  func testCoreTabsAudit() throws {
    let app = launch()
    // The production tab pills use their accessible titles, not separate tab identifiers.
    for title in ["Today", "Calendar", "Reminders", "Clock"] {
      let tab = app.buttons[title].firstMatch
      XCTAssertTrue(tab.waitForExistence(timeout: 5), title)
      XCTAssertTrue(tab.isHittable, title)
      XCTAssertEqual(tab.label, title)
      tab.tap()
      XCTAssertTrue(tab.isSelected, "The current tab must announce selection: \(title)")
      try audit(app)
    }
  }

  func testHealthDetailRangeAndDismissAudit() throws {
    let app = launch()
    let summary = app.buttons["health.summary"]
    for _ in 0..<4 where !(summary.exists && summary.isHittable) { app.swipeDown() }
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    XCTAssertTrue(summary.isHittable)
    summary.tap()
    let steps = app.buttons["health.row.steps"]
    XCTAssertTrue(steps.waitForExistence(timeout: 5))
    XCTAssertTrue(steps.label.hasPrefix("Steps, "), steps.label)
    steps.tap()
    XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 5))
    for days in [7, 30, 90] {
      let range = app.buttons["health.range.\(days)"]
      XCTAssertEqual(range.label, "\(days) Days")
      XCTAssertTrue(range.isHittable)
    }
    app.buttons["health.range.7"].tap()
    XCTAssertTrue(app.buttons["health.range.7"].isSelected)
    try audit(app)
    let done = app.buttons["health.detail.done"]
    XCTAssertEqual(done.label, "Done")
    done.tap()
    XCTAssertTrue(steps.waitForExistence(timeout: 5))
  }

  func testStopwatchLargeTypeActionsAudit() throws {
    let app = launch(largeType: true)
    app.buttons["Clock"].firstMatch.tap()
    let section = app.buttons["clock.section.stopwatch"]
    XCTAssertTrue(section.waitForExistence(timeout: 5))
    section.tap()
    let startStop = app.buttons["stopwatch.startStop"]
    let lapReset = app.buttons["stopwatch.lapReset"]
    XCTAssertTrue(startStop.waitForExistence(timeout: 5))
    XCTAssertEqual(startStop.label, "Start")
    XCTAssertEqual(lapReset.label, "Lap")
    XCTAssertFalse(lapReset.isEnabled)
    XCTAssertEqual(app.staticTexts["stopwatch.time"].label, "Stopwatch, 0 seconds")
    try audit(app)
    startStop.tap()
    XCTAssertEqual(startStop.label, "Stop")
    XCTAssertTrue(lapReset.isEnabled)
    startStop.tap()
    XCTAssertEqual(lapReset.label, "Reset")
    lapReset.tap()
    XCTAssertEqual(app.staticTexts["stopwatch.time"].label, "Stopwatch, 0 seconds")
  }
}
