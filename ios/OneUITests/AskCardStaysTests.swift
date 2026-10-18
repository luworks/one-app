import XCTest

/// The preview card stays in the conversation after Add and Cancel: Added (Undo, Open), Undone (Add again) and Dropped,
/// and the final state is there when the chat is reopened from the sidebar. Runs on the test dataset; the simulator has no
/// on-device model, so the rule parser reads the sentence.
final class AskCardStaysTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
    }

    private var field: XCUIElement {
        let f = app.textFields["Ask AI or add anything"].firstMatch
        return f.exists ? f : app.textViews.firstMatch
    }

    private func send(_ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text + "\n")
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["TEST_RUNNER_CARD_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: name + ".png"))
        }
    }

    /// Closes the chat, opens the sidebar and taps the newest conversation.
    private func reopenFromSidebar(containing word: String) {
        app.buttons["Close"].tap()
        let menu = app.buttons["Open menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'conversation.row' AND label CONTAINS %@", word)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "the conversation is in the sidebar")
        row.tap()
    }

    func testAddedCardStaysThenUndoAndAddAgain() {
        send("Order printer paper tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists)
        app.buttons["Add"].tap()

        // The card is still there, now confirmed; there is no separate "Added …" text line.
        XCTAssertTrue(any("capture-added").waitForExistence(timeout: 5), "the card shows Added")
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists, "same card: the title is still there")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'alerts you'")).firstMatch.exists, "and the time line")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Added “'")).firstMatch.exists,
                       "the old text confirmation is gone")
        XCTAssertFalse(app.buttons["Add"].exists || app.buttons["Cancel"].exists, "Add and Cancel are replaced")
        XCTAssertFalse(app.buttons["capture.kind.task"].exists, "and so is the Reminder / Event / Alarm switcher")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Added: Order printer paper'")).firstMatch.exists,
                      "the card's accessibility label carries the confirmation")
        shot("card-added")

        // Open shows the created reminder.
        app.buttons["capture-open"].tap()
        XCTAssertTrue(app.navigationBars["Reminder"].waitForExistence(timeout: 5), "Open shows the reminder")
        XCTAssertEqual(app.textFields["task.title"].value as? String, "Order printer paper")
        app.navigationBars["Reminder"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Reminder"].waitForNonExistence(timeout: 5))

        // Undo takes back exactly that; the card says Undone and offers Add again.
        app.buttons["capture-undo"].tap()
        XCTAssertTrue(any("capture-undone").waitForExistence(timeout: 5))
        XCTAssertFalse(any("capture-added").exists)
        XCTAssertTrue(app.buttons["capture-add-again"].exists)
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists, "the card stays")

        app.buttons["capture-add-again"].tap()
        XCTAssertTrue(any("capture-added").waitForExistence(timeout: 5), "Add again writes it again")
        app.buttons["capture-undo"].tap()
        XCTAssertTrue(any("capture-undone").waitForExistence(timeout: 5))

        // Reopened from the sidebar, the card is there in its final state.
        reopenFromSidebar(containing: "printer")
        XCTAssertTrue(any("capture-undone").waitForExistence(timeout: 5), "the saved chat shows Undone")
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists)
        XCTAssertFalse(any("capture-stack").buttons["Add"].exists, "a decided card is not an open card")

        // And the reminder is not anywhere: Search does not find it.
        app.buttons["Close"].tap()
        app.buttons["Search"].tap()
        let search = app.textFields["search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("printer")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No Results'")).firstMatch.waitForExistence(timeout: 5),
                      "Undo removed the reminder")
    }

    func testAddedStateSurvivesReopening() {
        send("Order printer paper tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        app.buttons["Add"].tap()
        XCTAssertTrue(any("capture-added").waitForExistence(timeout: 5))
        reopenFromSidebar(containing: "printer")
        XCTAssertTrue(any("capture-added").waitForExistence(timeout: 5), "the saved chat shows Added")
        XCTAssertTrue(app.buttons["capture-undo"].exists)
        // Undo still works from the reopened chat.
        app.buttons["capture-undo"].tap()
        XCTAssertTrue(any("capture-undone").waitForExistence(timeout: 5))
    }

    func testCancelLeavesADimmedDroppedCard() {
        send("Order printer paper tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 90))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(any("capture-dropped").waitForExistence(timeout: 5), "the card stays, Dropped")
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists)
        XCTAssertFalse(app.buttons["Add"].exists || app.buttons["Cancel"].exists || app.buttons["capture-undo"].exists, "no actions")
        shot("card-dropped")

        reopenFromSidebar(containing: "printer")
        XCTAssertTrue(any("capture-dropped").waitForExistence(timeout: 5), "the saved chat shows Dropped")
        XCTAssertTrue(app.staticTexts["Order printer paper"].exists)
    }

    func testNewLineAfterAnOpenCardDropsIt() {
        send("Order printer paper tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        send("Water the office plants friday at 9am")
        XCTAssertTrue(any("capture-dropped").waitForExistence(timeout: 90), "the earlier card is Dropped")
        XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1, "one open card")
    }
}
