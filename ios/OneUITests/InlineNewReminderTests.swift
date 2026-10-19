import XCTest

/// The inline "New Reminder" row in a list, like Apple Reminders: type a title, set a date and a flag
/// with the round buttons under it, press Return, and the reminder is added with them.
/// Runs against the test dataset (tests/fixtures/today-dataset.json), which has a "Home" list.
@MainActor
final class InlineNewReminderTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = TestData.launchArguments
      app.launch()
      app.buttons["Reminders"].firstMatch.tap()
    }
  }

  private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

  /// Scrolls until the element exists, is hittable and clear of the bottom bar.
  private func reveal(_ el: XCUIElement) {
    for _ in 0..<5 where !el.exists || !el.isHittable || el.frame.maxY > app.frame.height - 140 {
      app.swipeUp()
    }
    XCTAssertTrue(el.waitForExistence(timeout: 5), "missing \(el)")
  }

  func testNewRowAddsAReminderWithDateAndFlag() {
    let home = element("list.Home")
    reveal(home)
    home.tap()

    let field = app.textFields["newReminderField"]
    reveal(field)
    field.tap()
    let title = "Fix the gate"
    field.typeText(title)

    let date = element("newRow.date")
    XCTAssertTrue(
      date.waitForExistence(timeout: 5), "the date button shows while the new row is edited")
    // The buttons sit under the field and can end up behind the keyboard; an upward swipe keeps focus.
    let keyboard = app.keyboards.element
    if keyboard.exists, date.frame.maxY > keyboard.frame.minY { app.swipeUp() }
    date.tap()
    let tomorrow = app.buttons["Tomorrow"]
    XCTAssertTrue(tomorrow.waitForExistence(timeout: 5), "the date menu offers Tomorrow")
    tomorrow.tap()
    XCTAssertTrue(
      element("newRow.dateChip").waitForExistence(timeout: 5), "the chosen date shows as a chip")

    let flag = element("newRow.flag")
    XCTAssertTrue(flag.waitForExistence(timeout: 5))
    flag.tap()
    XCTAssertEqual(flag.value as? String, "On", "the flag is on")

    if !app.keyboards.element.exists { field.tap() }
    app.typeText("\n")

    XCTAssertTrue(
      app.staticTexts[title].waitForExistence(timeout: 5), "the new reminder shows in the list")
    let due = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Due Tomorrow'"))
      .firstMatch
    XCTAssertTrue(due.waitForExistence(timeout: 5), "the new reminder is due tomorrow")
  }
}
