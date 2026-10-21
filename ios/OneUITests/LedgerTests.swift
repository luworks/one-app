import XCTest

/// The Activity ledger: what the user did is listed, filterable and undoable. Runs on the test dataset with the clock
/// pinned at 09:41.
@MainActor
final class LedgerTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
    }
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

  /// Activity lists a delete the user made, and Undo there brings the reminder back.
  func testActivityListsAUserDeleteWithUndo() {
    launch()
    let row = app.staticTexts["Call the bank"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.swipeLeft()
    let delete = app.buttons["Delete"]
    if delete.waitForExistence(timeout: 1) { delete.tap() }
    XCTAssertTrue(row.waitForNonExistence(timeout: 5), "swipe deletes the reminder")

    openActivity()
    let deleted = text("label == %@", "Deleted “Call the bank”")
    XCTAssertTrue(deleted.waitForExistence(timeout: 5), "the user's delete is listed")

    // Filters: AI hides the user's delete; You shows it again.
    app.buttons["activity.filter.AI"].tap()
    XCTAssertTrue(deleted.waitForNonExistence(timeout: 3))
    app.buttons["activity.filter.You"].tap()
    XCTAssertTrue(deleted.waitForExistence(timeout: 3))

    let undo = app.buttons["Undo Deleted “Call the bank”"]
    XCTAssertTrue(undo.waitForExistence(timeout: 3), "the delete can be undone from Activity")
    undo.tap()
    XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 3))
    XCTAssertTrue(
      text("label == %@", "Undid “Call the bank”").waitForExistence(timeout: 3),
      "the undo is recorded too")
    app.buttons["Done"].tap()
    app.closeSidebar()
    XCTAssertTrue(
      app.staticTexts["Call the bank"].firstMatch.waitForExistence(timeout: 5),
      "the reminder is back on Today")
  }
}
