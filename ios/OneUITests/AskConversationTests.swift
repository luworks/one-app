import XCTest

@MainActor
final class AskConversationTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = ["-uiTesting", "-uiTestingMultiCapture"]
      app.launch()
      app.buttons["Ask AI or add anything"].tap()
    }
  }

  private func send(_ text: String) {
    let input = app.textFields["Ask AI or add anything"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    input.tap()
    input.typeText(text + "\n")
  }

  private func reply(_ text: String) -> XCUIElement {
    app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  func testReportedActivityMessageIsConversation() {
    send("我进行一个测试，然后看看我的 Activity 中是不是会选择显示")
    XCTAssertTrue(reply("才会留下对应的变更记录").waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Add"].exists)
    XCTAssertFalse(app.buttons["capture-add-all"].exists)
    XCTAssertFalse(reply("Here's what I understood").exists)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Activity conversation without capture"
    shot.lifetime = .keepAlways
    add(shot)
    app.buttons["Close"].firstMatch.tap()
    app.openSidebar()
    app.buttons["Activity"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 5))
  }

  func testChatThenExplicitRequestAndChatPreservesPreview() {
    send("Hello")
    XCTAssertTrue(reply("What's on your mind?").waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Add"].exists)
    send("Call Alex tomorrow at 3pm")
    XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 20))
    send("Thanks for explaining the alarm")
    XCTAssertTrue(reply("You're welcome").waitForExistence(timeout: 10))
    XCTAssertTrue(reply("New reminder").exists)
    XCTAssertFalse(reply("New alarm").exists)
    send("make it 4pm")
    XCTAssertTrue(reply("16:00").waitForExistence(timeout: 10))
    app.buttons["Add"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["capture-undo"].exists)
    XCTAssertTrue(app.buttons["capture-open"].exists)
  }

  func testExistingAlarmQuestionPreservesPendingReminder() {
    send("Call Alex tomorrow at 3pm")
    XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 20))
    send("Did I set an alarm for 7am?")
    XCTAssertTrue(reply("We can just chat").waitForExistence(timeout: 10))
    XCTAssertTrue(reply("New reminder").exists)
    XCTAssertFalse(reply("New alarm").exists)
    XCTAssertTrue(reply("15:00").exists)
    XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1)
    send("How about 5pm?")
    XCTAssertTrue(reply("17:00").waitForExistence(timeout: 10))
    XCTAssertTrue(reply("New reminder").exists)
    XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1)
    app.buttons["Add"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["capture-undo"].exists)
    XCTAssertTrue(app.buttons["capture-open"].exists)
  }

  func testExplicitEventAndAlarmRequestsStillShowPreviews() {
    send("Set an alarm for 7am")
    XCTAssertTrue(reply("New alarm").waitForExistence(timeout: 20))
    app.buttons["Cancel"].firstMatch.tap()
    send("Dentist tomorrow at 3pm")
    XCTAssertTrue(reply("New event").waitForExistence(timeout: 20))
    XCTAssertTrue(app.buttons["Add"].exists)
  }

  func testChineseExistingActionQuestionsInFreshChatDoNotProposeItems() {
    for (index, question) in ["有没有人提醒我明天的会议？", "有人添加了一个提醒吗？"].enumerated() {
      send(question)
      let replies = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "我们可以直接聊聊"))
      let answered = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "count == %d", index + 1), object: replies)
      XCTAssertEqual(XCTWaiter().wait(for: [answered], timeout: 10), .completed)
      XCTAssertFalse(app.buttons["Add"].exists)
      XCTAssertFalse(app.buttons["capture-add-all"].exists)
      XCTAssertFalse(app.otherElements["change-card"].exists)
    }
  }

  func testQuestionAndUnknownStatementDoNotCreateCards() {
    send("How are you?")
    XCTAssertTrue(reply("We can just chat").waitForExistence(timeout: 10))
    XCTAssertFalse(reply("Today:").exists)
    XCTAssertFalse(app.buttons["Add"].exists)
    send("some thoughts; perhaps a new hobby")
    let replies = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "We can just chat"))
    let answered = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "count == 2"), object: replies)
    XCTAssertEqual(XCTWaiter().wait(for: [answered], timeout: 10), .completed)
    XCTAssertFalse(app.buttons["capture-add-all"].exists)
  }
}
