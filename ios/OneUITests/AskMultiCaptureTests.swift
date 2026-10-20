import XCTest

/// Several items from one line on the AI page: all shown at once, each with its own Add / Skip plus "Add all", an added
/// item turns into a check and then leaves, and a task is filed into the list it clearly belongs to.
/// The simulator has no on-device model, so `-uiTestingMultiCapture` splits a line on ";" with the rule parser.
@MainActor
final class AskMultiCaptureTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = ["-uiTesting", "-uiTestingMultiCapture"]
      app.launch()
      app.buttons["Ask AI or add anything"].tap()
    }
  }

  private var field: XCUIElement {
    let f = app.textViews["Ask AI or add anything"].firstMatch
    return f.exists ? f : app.textViews.firstMatch
  }

  private func send(_ text: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(text + "\n")
  }

  private func text(_ s: String) -> XCUIElement {
    app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
  }

  func testEveryItemShowsAtOnceAndAddAllFilesThem() {
    send("Buy milk; Call Alex tomorrow at 3pm; Pay studio invoice")
    let addAll = app.buttons["capture-add-all"]
    XCTAssertTrue(addAll.waitForExistence(timeout: 15), "several items share one card with Add all")
    XCTAssertEqual(
      app.buttons.matching(identifier: "capture-row-add").count, 3,
      "one Add per item, all visible together")
    XCTAssertTrue(
      text("Buy milk").exists && text("Call Alex").exists && text("Pay studio invoice").exists)
    // "Buy milk" already lives in Home, so it is filed there rather than in the default list.
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS 'List: Home'")).firstMatch.exists,
      "a task is filed into the list it belongs to")
    XCTAssertTrue(addAll.isHittable)
    addAll.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5),
      "added items turn into a check")
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: addAll)
    XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    // The card stays in the chat: every row says Added, each with its own Undo.
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-stack"].exists,
      "the card stays once everything is added")
    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "capture-added").count, 3)
    XCTAssertEqual(app.buttons.matching(identifier: "capture-undo").count, 3)
    XCTAssertTrue(text("Buy milk").exists && text("Call Alex").exists, "the rows keep their text")
  }

  func testAddOneAndSkipAnother() {
    send("Buy milk; Call Alex tomorrow at 3pm; Pay studio invoice")
    XCTAssertTrue(app.buttons["capture-add-all"].waitForExistence(timeout: 15))
    app.buttons.matching(identifier: "capture-row-add").firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5),
      "the added row shows a check")
    app.buttons["Skip"].firstMatch.tap()
    XCTAssertEqual(
      app.buttons.matching(identifier: "capture-row-add").count, 1, "one item is left to add")
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-dropped"].waitForExistence(timeout: 5),
      "the skipped row stays, Dropped")
  }

  /// Undo on one row takes back only that item; the row offers Add again.
  func testUndoOneRowAndAddItAgain() {
    send("Buy milk; Call Alex tomorrow at 3pm")
    XCTAssertTrue(app.buttons["capture-add-all"].waitForExistence(timeout: 15))
    app.buttons["capture-add-all"].tap()
    XCTAssertTrue(app.buttons["capture-undo"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["capture-undo"].firstMatch.tap()
    XCTAssertTrue(app.descendants(matching: .any)["capture-undone"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.descendants(matching: .any).matching(identifier: "capture-added").count, 1,
      "the other row is still Added")
    app.buttons["capture-add-again"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["capture-undone"].waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "capture-added").count, 2)
  }
}
