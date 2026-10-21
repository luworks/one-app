import UIKit
import XCTest

@MainActor
final class PopulatedHistoryTests: XCTestCase {
  private func launchHistory() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments("populated-history.json") + [
        "-performanceTrace", "-uiTestingNow", "09:41",
      ]
    app.launch()
    app.openSidebar()
    app.buttons["Quarterly planning history"].firstMatch.tap()
    XCTAssertTrue(app.textViews["ask-input"].waitForExistence(timeout: 5))
    return app
  }

  private func retain(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
    let tree = XCTAttachment(string: app.debugDescription)
    tree.name = name + " accessibility"
    tree.lifetime = .keepAlways
    add(tree)
  }

  func testExistingLongChatKeepsReadingPositionAfterClose() throws {
    let app = launchHistory()
    let dismiss = app.buttons["Dismiss keyboard"].firstMatch
    if dismiss.exists { dismiss.tap() }
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "Compare reading positions with the keyboard hidden")
    let scroll = try XCTUnwrap(
      app.scrollViews.allElementsBoundByIndex.max {
        $0.frame.height < $1.frame.height
      })
    XCTAssertGreaterThan(scroll.frame.height, 200)
    scroll.swipeDown(velocity: .fast)
    scroll.swipeDown(velocity: .fast)
    let earlier = try XCTUnwrap(
      scroll.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "History ")
      ).allElementsBoundByIndex.first { $0.isHittable && scroll.frame.contains($0.frame) })
    XCTAssertFalse(earlier.label.hasPrefix("History 099:"), "Read an earlier message, not the tail")
    let label = earlier.label
    let before = earlier.frame.minY
    retain(app, "Populated history reading before Close")
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.textViews["ask-input"].waitForNonExistence(timeout: 5))
    app.buttons["Close sidebar"].tap()
    app.buttons["Ask AI or add anything"].tap()
    XCTAssertTrue(app.textViews["ask-input"].waitForExistence(timeout: 5))
    if dismiss.exists { dismiss.tap() }
    XCTAssertFalse(
      app.keyboards.firstMatch.exists, "Compare reading positions with the keyboard hidden")
    let restored = app.staticTexts[label].firstMatch
    XCTAssertTrue(restored.isHittable)
    XCTAssertEqual(
      restored.frame.minY, before, accuracy: 35,
      "Closing and reopening must preserve the message being read")
    retain(app, "Populated history reading restored")
  }

  func testMultilineCJKPasteRemainsExactAndUnsentAfterClose() throws {
    let app = launchHistory()
    let field = app.textViews["ask-input"].firstMatch
    let draft = try String(
      contentsOfFile: TestData.fixturePath("populated-unsent-draft.txt"),
      encoding: .utf8)
    // Use the native Paste action: keyboard Return deliberately submits in this composer.
    UIPasteboard.general.string = draft
    defer { UIPasteboard.general.items = [] }
    field.tap()
    field.press(forDuration: 1)
    let paste = app.menuItems["Paste"].firstMatch
    XCTAssertTrue(paste.waitForExistence(timeout: 5))
    paste.tap()
    XCTAssertEqual(field.value as? String, draft)
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).firstMatch.exists,
      "Paste must not submit a user message")
    XCTAssertFalse(app.buttons["capture-open"].exists)
    retain(app, "Populated multiline CJK unsent draft")
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    app.buttons["Close sidebar"].tap()
    app.buttons["Ask AI or add anything"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, draft)
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).firstMatch.exists)
    XCTAssertFalse(app.buttons["capture-open"].exists)
    XCTAssertFalse(app.buttons["Add"].exists)
    retain(app, "Populated multiline CJK draft restored")
  }
}
