import XCTest

/// Trace-disabled regression for the simulator's unavailable-model conversation path.
@MainActor
final class LocalConversationResponseTests: XCTestCase {
    func testLocalReplyAndUserMessageSurviveReopeningThread() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"]
        app.launch()
        defer { app.terminate() }
        app.buttons["Ask AI or add anything"].tap()
        let input = app.textFields["Ask AI or add anything"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Hello\n")
        let reply = app.staticTexts["Hello! What's on your mind?"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Add"].exists)
        XCTAssertFalse(app.buttons["capture-add-all"].exists)
        app.buttons["Close"].firstMatch.tap()
        app.openSidebar()
        let thread = app.buttons.matching(NSPredicate(format: "identifier == 'conversation.row' AND label == 'Hello'")).firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 5))
        thread.tap()
        XCTAssertTrue(app.staticTexts["Hello"].waitForExistence(timeout: 5))
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Hello! What's on your mind?")).count, 1)
        XCTAssertFalse(app.buttons["Add"].exists)
        XCTAssertFalse(app.buttons["capture-add-all"].exists)
    }
}
