import XCTest

@MainActor
final class UnifiedCreateTests: XCTestCase {
  private func openComposer() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = TestData.launchArguments
    app.launch()
    app.buttons["New"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["create.title"].waitForExistence(timeout: 5))
    return app
  }

  func testPlusOpensComposerAndCancelWritesNothing() {
    let app = openComposer()
    app.descendants(matching: .any)["create.title"].tap()
    app.descendants(matching: .any)["create.title"].typeText("Cancelled unified draft")
    app.buttons["Close"].tap()
    XCTAssertFalse(app.staticTexts["Cancelled unified draft"].exists)
  }

  func testSwitchTypesPreservesTitle() {
    let app = openComposer()
    app.descendants(matching: .any)["create.title"].typeText("Shared native draft")
    app.buttons["create.type"].tap()
    app.buttons["Calendar"].tap()
    XCTAssertEqual(
      app.descendants(matching: .any)["create.title"].value as? String, "Shared native draft")
    app.buttons["create.type"].tap()
    app.buttons["Alarm"].tap()
    XCTAssertEqual(
      app.descendants(matching: .any)["create.title"].value as? String, "Shared native draft")
  }

  func testEmptyDraftCannotCreate() {
    let app = openComposer()
    XCTAssertFalse(app.buttons["create.save"].isEnabled)
  }
}
