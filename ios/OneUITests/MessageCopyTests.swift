import XCTest

/// Your messages and AI answers with content have a copy button (it confirms with a check mark); the app's own status
/// sentences ("Here's what I understood…") do not.
final class MessageCopyTests: XCTestCase {
    func testEachMessageHasACopyButtonThatConfirms() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
        let f = app.textFields["Ask AI or add anything"].firstMatch
        let field = f.exists ? f : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("What's on today?\n")

        let copy = app.buttons.matching(identifier: "message.copy")
        let twoMessages = NSPredicate(format: "count >= 2")
        expectation(for: twoMessages, evaluatedWith: copy)
        waitForExpectations(timeout: 60)

        copy.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 3))
    }

    /// The app's own status sentences have no Copy button; your own message does.
    func testStatusSentencesHaveNoCopyButton() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
        let f = app.textFields["Ask AI or add anything"].firstMatch
        let field = f.exists ? f : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Buy milk tomorrow\n")

        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90), "the preview card is up")
        XCTAssertTrue(app.staticTexts["Here's what I understood. Nothing is added until you confirm."].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "message.copy").count, 1, "only your own message has Copy")
    }
}
