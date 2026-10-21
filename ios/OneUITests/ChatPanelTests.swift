import XCTest

@MainActor
final class ChatPanelTests: XCTestCase {
  /// Three fresh processes distinguish first presentation from retained-editor reopening.
  /// App trace marks measure layout; XCTest's typing interval is reported separately.
  func testPopulatedFirstOpenAndReopenEvidence() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + ["-performanceTrace", "-uiTestingNow", "09:41"]
    for process in 0..<3 {
      app.launch()
      let chat = app.buttons["Ask AI or add anything"]
      XCTAssertTrue(chat.waitForExistence(timeout: 5))
      let start = ProcessInfo.processInfo.systemUptime
      chat.tap()
      let field = app.textViews["ask-input"].firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.tap()
      let draft = "Unsent populated draft \(process)"
      field.typeText(draft)
      XCTAssertEqual(field.value as? String, draft)
      print(
        "CHAT_UI process=\(process) tap_call_to_verified_text_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) includes_XCTest_lookup_idle_tap_and_typing=true"
      )
      app.buttons["Close"].firstMatch.tap()
      XCTAssertTrue(field.waitForNonExistence(timeout: 5))
      XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected)
      chat.tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertEqual(field.value as? String, draft)
      XCTAssertFalse(app.buttons["capture-open"].exists)
      XCTAssertFalse(app.buttons["Add"].exists)
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = "Populated Chat process \(process), retained unsent draft"
      shot.lifetime = .keepAlways
      add(shot)
      app.terminate()
    }
  }

  func testTapToUsableComposerEvidence() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting", "-performanceTrace"]
    app.launch()
    let button = app.buttons["Ask AI or add anything"]
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    let start = ProcessInfo.processInfo.systemUptime
    button.tap()
    let field = app.textViews["ask-input"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("Unsent panel draft")
    XCTAssertEqual(field.value as? String, "Unsent panel draft")
    print(
      "CHAT_UI tap_call_to_verified_text_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) includes_XCTest_lookup_idle_tap_and_typing=true"
    )
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Chat composer with unsent draft"
    shot.lifetime = .keepAlways
    add(shot)
  }

  func testCloseReopenPreservesExactDraftAndConversation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting", "-performanceTrace"]
    app.launch()
    let chat = app.buttons["Ask AI or add anything"]
    chat.tap()
    let field = app.textViews["ask-input"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("Hello\n")
    XCTAssertTrue(app.staticTexts["Hello"].waitForExistence(timeout: 5))
    let reply = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "What's on your mind?")
    )
    .firstMatch
    XCTAssertTrue(reply.waitForExistence(timeout: 8))
    let exact = "Unsent: call Alex at 3pm — 中文草稿"
    field.tap()
    field.typeText(exact)
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    let closed = XCTAttachment(screenshot: app.screenshot())
    closed.name = "Underlying page after Close"
    closed.lifetime = .keepAlways
    add(closed)
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    XCTAssertFalse(field.isHittable)
    chat.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, exact)
    XCTAssertTrue(app.staticTexts["Hello"].exists)
    XCTAssertTrue(reply.exists)
    XCTAssertFalse(app.buttons["capture-open"].exists)
    XCTAssertFalse(app.buttons["Add"].exists)
    let dismissKeyboard = app.buttons["Dismiss keyboard"].firstMatch
    print(
      "CHAT_UI dismiss_keyboard_frame=\(dismissKeyboard.frame) hittable=\(dismissKeyboard.isHittable)"
    )
    XCTAssertTrue(dismissKeyboard.isHittable)
    dismissKeyboard.tap()
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    XCTAssertFalse(app.buttons["Dismiss keyboard"].exists)
    XCTAssertEqual(field.value as? String, exact)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Floating conversation restored with exact draft and keyboard down"
    shot.lifetime = .keepAlways
    add(shot)
  }

  func testLargeTextKeepsInsetComposerAndCloseReachable() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-uiTesting", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    app.buttons["Ask AI or add anything"].tap()
    let input = app.textViews["ask-input"].firstMatch
    let close = app.buttons["Close"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertTrue(input.isHittable)
    XCTAssertTrue(close.isHittable)
    XCTAssertGreaterThan(close.frame.minY, app.frame.minY + 50)
    XCTAssertGreaterThan(input.frame.minX, app.frame.minX)
    XCTAssertLessThan(input.frame.maxX, app.frame.maxX)
    input.tap()
    input.typeText("Large text draft")
    XCTAssertEqual(input.value as? String, "Large text draft")
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Accessibility text floating panel with keyboard"
    shot.lifetime = .keepAlways
    add(shot)
    close.tap()
    XCTAssertTrue(app.buttons["Ask AI or add anything"].isHittable)
  }

}
