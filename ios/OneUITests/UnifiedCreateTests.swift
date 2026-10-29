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
    XCTAssertFalse(search("Cancelled unified draft", in: app).waitForExistence(timeout: 2))
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

  private func search(_ title: String, in app: XCUIApplication) -> XCUIElement {
    app.openSidebar()
    app.buttons["Search"].tap()
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.typeText(title)
    return app.buttons.matching(
      NSPredicate(format: "identifier == 'search.result' AND label BEGINSWITH %@", title)
    ).firstMatch
  }

  private func saveAndFind(_ kind: String, title: String) {
    let app = openComposer()
    app.descendants(matching: .any)["create.title"].typeText(title)
    app.buttons["create.type"].tap()
    app.buttons[kind].tap()
    app.buttons["create.save"].tap()
    XCTAssertTrue(app.buttons["create.save"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(
      search(title, in: app).waitForExistence(timeout: 5),
      "The committed item must be readable outside the composer")
  }

  func testCreatesReminder() { saveAndFind("Reminder", title: "Unified saved reminder") }
  func testCreatesCalendarEvent() { saveAndFind("Calendar", title: "Unified saved event") }
  func testCreatesAlarm() { saveAndFind("Alarm", title: "Unified saved alarm") }

  func testEmptyDraftCannotCreate() {
    let app = openComposer()
    XCTAssertFalse(app.buttons["create.save"].isEnabled)
  }
}
