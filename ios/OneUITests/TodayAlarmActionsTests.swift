import XCTest

/// Native row gestures and the real model persistence path with injected AlarmKit boundaries.
@MainActor
final class TodayAlarmActionsTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws { continueAfterFailure = false }

  private func launch(extra: [String] = [], dataset: String = "today-alarm-actions.json") {
    app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments(dataset) + [
        "-uiTestingNow", "12:00",
        "-today.setting.jumpToNow", "NO", "-today.setting.healthSummary", "NO",
      ] + extra
    app.launch()
    XCTAssertTrue(app.staticTexts["Keep reminder deadline"].waitForExistence(timeout: 8))
  }

  private func row(_ title: String = "Timeline alarm") -> XCUIElement {
    app.buttons.matching(identifier: "today.alarm.row")
      .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testTapOpensExistingEditorAndCancelKeepsAlarm() {
    launch()
    XCTAssertTrue(row().waitForExistence(timeout: 5))
    shot("alarm-after-row")
    row().tap()
    XCTAssertTrue(app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5))
    let field = app.textFields["alarm.label"]
    XCTAssertEqual(field.value as? String, "Timeline alarm")
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    field.typeText(" draft")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(row().waitForExistence(timeout: 5))
    XCTAssertFalse(row("Timeline alarm draft").exists)
    XCTAssertTrue(row("Keep this alarm").exists)
  }

  func testLongPressEditSavesAndReopensSameAlarm() {
    launch()
    row().press(forDuration: 1)
    XCTAssertTrue(app.buttons["Edit Alarm"].waitForExistence(timeout: 5))
    shot("alarm-after-menu")
    app.buttons["Edit Alarm"].tap()
    let field = app.textFields["alarm.label"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    field.typeText(" edited")
    app.buttons["alarm.save"].tap()
    XCTAssertTrue(row("Timeline alarm edited").waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "today.alarm.row").count, 2)
    row("Timeline alarm edited").tap()
    XCTAssertEqual(app.textFields["alarm.label"].value as? String, "Timeline alarm edited")
    shot("alarm-after-editor")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.staticTexts["Keep reminder deadline"].exists)
  }

  func testSwipeDeletePersistsAcrossRelaunchWithoutDeletingOtherItems() {
    let store = "alarm-row-\(UUID().uuidString)"
    launch(extra: ["-uiTestingStore", store])
    row().swipeLeft()
    let delete = app.buttons["Delete"].firstMatch
    if delete.waitForExistence(timeout: 1) {
      shot("alarm-after-swipe")
      delete.tap()
    }
    XCTAssertTrue(row().waitForNonExistence(timeout: 5))
    XCTAssertTrue(row("Keep this alarm").exists)
    shot("alarm-after-delete")
    app.terminate()
    launch(extra: ["-uiTestingStore", store], dataset: "empty-relaunch.json")
    XCTAssertFalse(row().exists)
    XCTAssertTrue(row("Keep this alarm").exists)
    XCTAssertEqual(app.buttons.matching(identifier: "today.alarm.row").count, 1)
    row("Keep this alarm").tap()
    XCTAssertTrue(app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5))
  }

  func testWriteFailuresKeepRowAndEditorDraft() {
    launch(extra: ["-uiTestingAlarmCancelError", "-uiTestingAlarmScheduleError"])
    row().swipeLeft()
    let delete = app.buttons["Delete"].firstMatch
    if delete.waitForExistence(timeout: 1) { delete.tap() }
    XCTAssertTrue(row().waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alarm access is unavailable'"))
        .firstMatch.waitForExistence(timeout: 5))
    row().tap()
    let field = app.textFields["alarm.label"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    field.typeText(" retry")
    app.buttons["alarm.save"].tap()
    XCTAssertTrue(app.alerts["Couldn’t Update Alarm"].waitForExistence(timeout: 5))
    shot("alarm-after-error")
    app.alerts.buttons["OK"].tap()
    XCTAssertEqual(field.value as? String, "Timeline alarm retry")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(row().waitForExistence(timeout: 5))
    XCTAssertFalse(row("Timeline alarm retry").exists)
  }
}
