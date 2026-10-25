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

  /// Close goes back to the sidebar it was opened from; the row reopens the conversation at its end.
  func testExistingLongChatReopensAtItsEndFromSidebar() throws {
    let app = launchHistory()
    let tail = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "History 099:"))
      .firstMatch
    XCTAssertTrue(tail.waitForExistence(timeout: 5), "A saved conversation opens at its end")
    let scroll = try XCTUnwrap(
      app.scrollViews.allElementsBoundByIndex.max {
        $0.frame.height < $1.frame.height
      })
    scroll.swipeDown(velocity: .fast)
    scroll.swipeDown(velocity: .fast)
    retain(app, "Populated history reading before Close")
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.textViews["ask-input"].waitForNonExistence(timeout: 5))
    let row = app.buttons["Quarterly planning history"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "Close returns to the sidebar")
    row.tap()
    XCTAssertTrue(app.textViews["ask-input"].waitForExistence(timeout: 5))
    XCTAssertTrue(tail.waitForExistence(timeout: 5))
    XCTAssertTrue(tail.isHittable, "Reopened at its end")
    retain(app, "Populated history reopened at its end")
  }

  func testMultilineCJKPasteRemainsExactAndIsNotSentOnClose() throws {
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
    XCTAssertNotEqual(field.value as? String, draft, "A new chat does not carry the unsent draft")
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label == %@", draft)).firstMatch.exists)
    XCTAssertFalse(app.buttons["capture-open"].exists)
    XCTAssertFalse(app.buttons["Add"].exists)
    retain(app, "New chat after closing the unsent CJK draft")
  }
}
