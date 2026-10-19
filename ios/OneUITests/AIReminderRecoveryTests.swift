import XCTest

/// Real production fallback journeys, including stored mistaken assistant replies.
@MainActor
final class AIReminderRecoveryTests: XCTestCase {
  private var app: XCUIApplication!
  private let title = "做一次 auto turbotax repo"

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = TestData.fixtureArguments("ai-reminder-recovery-ui.json")
      app.launch()
      app.openSidebar()
    }
  }

  func testSuffixReminderHasDateOnlyPreviewAndAddPersistsWithUndo() {
    open("New chat")
    send("做一次 auto turbotax repo 下周四提醒我")
    assertPreview(title)
    assertNoWritesAndReturn("Reminder wrong chat")
    // The stored wrong assistant reply must not prevent an actionable recovery.
    send("就设定 reminder")
    assertPreview(title)
    preview.buttons["Add"].tap()
    let open = app.buttons["capture-open"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["capture-undo"].firstMatch.exists)
    open.tap()
    XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields["task.title"].value as? String, title)
    app.swipeUp()
    XCTAssertEqual(app.switches["Plan a time"].value as? String, "0")
    XCTAssertEqual(app.switches["Deadline"].value as? String, "1")
    // iOS 27 exposes the compact DatePicker as date/time buttons, not a named DatePicker.
    print("Persisted reminder editor hierarchy:\n" + app.debugDescription)
    let dueDate = nextThursday.formatted(.dateTime.month(.abbreviated).day().year())
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(
          format: "label == %@ OR value == %@", dueDate, dueDate)
      ).firstMatch.exists,
      "The persisted reminder retains the exact next-Thursday due date")
    XCTAssertTrue(
      app.buttons.containing(
        NSPredicate(format: "label CONTAINS 'Repeat' AND label CONTAINS 'Never'")
      ).firstMatch.exists)
    app.buttons["Cancel"].tap()
    app.buttons["capture-undo"].firstMatch.tap()
    XCTAssertTrue(app.buttons["capture-undo"].firstMatch.waitForNonExistence(timeout: 5))
  }

  func testChineseFullMistakenConversationRecoversWithoutExtraQuestionsOrWrites() {
    open("Reminder full wrong chat")
    send("够")
    XCTAssertFalse(preview.exists, "A generic acknowledgment does not invent a capture")
    send("你做吧")
    assertPreview(title)
    keepScreenshot("Recovered actionable date-only reminder after full wrong conversation")
    assertNoWritesAndReturn("Reminder wrong chat")
    send("就设定 reminder")
    assertPreview(title)
    send("够")
    assertPreview(title)
    send("你做吧")
    assertPreview(title)
    assertNoWritesAndReturn("Reminder full wrong chat")
  }

  func testEnglishMistakenConversationRecoversAndOrdinaryQuotedChatDoesNotCreate() {
    open("Reminder English wrong chat")
    send("Go ahead.")
    assertPreview("Review auto turbotax repo")
    assertNoWritesAndReturn("New chat")
    send("She said \"Review auto turbotax repo next Thursday, remind me\"")
    XCTAssertFalse(preview.exists)
    send("That's enough")
    XCTAssertFalse(preview.exists)
    send("Go ahead.")
    XCTAssertFalse(preview.exists)
    assertNoWritesAndReturn("Reminder English wrong chat")
  }

  private var preview: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "capture-stack")
      .containing(.button, identifier: "Add").firstMatch
  }
  private var field: XCUIElement { app.textFields["Ask AI or add anything"].firstMatch }
  private func open(_ name: String) {
    let button = app.buttons[name].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
  }
  private func send(_ text: String) {
    field.tap()
    field.typeText(text)
    app.buttons["Send"].tap()
    XCTAssertTrue(app.buttons["Send"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Thinking…"].waitForNonExistence(timeout: 15))
  }
  private func assertPreview(_ expected: String) {
    XCTAssertTrue(
      preview.buttons["Add"].waitForExistence(timeout: 15),
      "An actionable preview must appear, not only a reply/promise")
    XCTAssertTrue(
      preview.buttons["Add"].isEnabled, "Date-only reminders can be added without an alarm time")
    XCTAssertEqual(preview.buttons["capture-title"].firstMatch.label, expected)
    XCTAssertTrue(preview.staticTexts["New reminder"].exists)
    // Chinese 下周 is the next calendar week, independent of the test execution weekday.
    let calendar = Calendar.current
    let target = nextThursday
    let day =
      calendar.isDateInTomorrow(target) ? "Tomorrow" : target.formatted(.dateTime.month().day())
    XCTAssertTrue(
      preview.staticTexts["Due " + day].exists,
      "Exact next-Thursday date with no invented time or recurrence")
    XCTAssertFalse(app.descendants(matching: .any)["capture-added"].exists)
    XCTAssertFalse(app.buttons["capture-undo"].exists)
    XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1)
  }
  private var nextThursday: Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
    return calendar.date(byAdding: .day, value: 7 - mondayOffset + 3, to: today)!
  }
  private func assertNoWritesAndReturn(_ thread: String) {
    app.buttons["Close"].firstMatch.tap()
    app.buttons["Activity"].tap()
    XCTAssertTrue(
      app.staticTexts["No activity yet"].waitForExistence(timeout: 5),
      "No planner changes before Add")
    app.buttons["Done"].firstMatch.tap()
    open(thread)
  }
  private func keepScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
