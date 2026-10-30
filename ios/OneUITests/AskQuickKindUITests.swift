import XCTest

/// Reminder / Event / Alarm above the Ask composer only select a kind; the draft stays empty and the chat shows
/// only what was typed, while the kind's skill still routes the message.
@MainActor
final class AskQuickKindUITests: XCTestCase {
  func testKindHighlightsWithoutTouchingTheDraftAndRoutesTheMessage() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = TestData.launchArguments
    app.launch()
    app.openSidebar()
    let newChat = app.buttons["New chat"]
    XCTAssertTrue(newChat.waitForExistence(timeout: 5))
    newChat.tap()

    let alarm = app.buttons["ask-kind-alarm"]
    XCTAssertTrue(alarm.waitForExistence(timeout: 5))
    alarm.tap()
    XCTAssertTrue(alarm.isSelected, "the kind is highlighted")
    let field = app.textViews.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual((field.value as? String) ?? "", "", "nothing is written into the draft")
    alarm.tap()
    XCTAssertFalse(alarm.isSelected, "a second tap deselects")
    alarm.tap()

    field.typeText("7am")
    XCTAssertTrue(alarm.isSelected, "the kind stays highlighted while typing")
    app.buttons["ask-send"].tap()
    XCTAssertTrue(
      app.staticTexts["7am"].waitForExistence(timeout: 5), "the chat shows what was typed")
    XCTAssertFalse(app.staticTexts["Set an alarm for 7am"].exists, "the skill prompt is not shown")
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-stack"].firstMatch.waitForExistence(timeout: 15),
      "the alarm skill routed the message to an alarm preview")
    XCTAssertFalse(alarm.exists && alarm.isSelected, "the kind applies to one message")
  }
}
