import XCTest

/// Every chat message has a copy button under it (user and AI), and the button confirms with a check mark.
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
}
