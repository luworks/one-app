import XCTest

/// The left sidebar is the history of conversations with the AI (like ChatGPT / Claude), not a second tab bar.
/// Each test runs against a fresh in-memory store, so there are no conversations to start with.
final class SidebarTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// Talks to the AI once and returns to the main page. A question gets a local answer, so no model or preview is involved.
    private func haveAConversation(_ text: String = "Anything left today?") {
        let bar = app.buttons["Ask AI or add anything"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let field = app.textFields["Ask AI or add anything"].firstMatch.exists
            ? app.textFields["Ask AI or add anything"].firstMatch
            : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "the AI answers")
        app.buttons["Close"].tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "back on the main page")
    }

    private var reply: XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Today:'")).firstMatch
    }

    func testConversationAppearsInSidebarAndReopens() {
        haveAConversation("Anything left today?")
        app.openSidebar()
        let row = app.buttons["Anything left today?"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the conversation is listed, titled by the first message")
        row.tap()
        XCTAssertTrue(app.staticTexts["Anything left today?"].waitForExistence(timeout: 5), "the user's message is back")
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "and the AI's answer")
        XCTAssertFalse(app.staticTexts["What do you want to plan?"].exists, "it is the old conversation, not a new one")
    }

    func testNewChatStartsEmpty() {
        haveAConversation()
        app.openSidebar()
        app.buttons["New chat"].tap()
        XCTAssertTrue(app.staticTexts["What do you want to plan?"].waitForExistence(timeout: 5))
        XCTAssertFalse(reply.exists)
    }

    func testSwipeRightDeletesAConversationAndUndoBringsItBack() {
        haveAConversation()
        app.openSidebar()
        let row = app.buttons["Anything left today?"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "swiping left to right reveals Delete")
        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the conversation is gone")
        XCTAssertTrue(app.staticTexts["Your conversations with AI will appear here."].waitForExistence(timeout: 3))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "there is an Undo")
        undo.tap()
        XCTAssertTrue(app.buttons["Anything left today?"].waitForExistence(timeout: 5), "Undo puts it back")
    }

    func testSwipeLeftArchivesAConversationIntoTheArchivedSection() {
        haveAConversation()
        app.openSidebar()
        let row = app.buttons["Anything left today?"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let archive = app.buttons["Archive"]
        // A full swipe archives straight away; a shorter one reveals the Archive button first.
        if archive.waitForExistence(timeout: 2) { archive.tap() }
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the conversation leaves the main list")
        let archived = app.buttons["conversation.archived"]
        XCTAssertTrue(archived.waitForExistence(timeout: 3), "an Archived section appears")
        archived.tap()
        XCTAssertTrue(app.buttons["Anything left today?"].waitForExistence(timeout: 5), "it is still reachable under Archived")
    }

    func testLongPressOffersRenameArchiveAndDelete() {
        haveAConversation()
        app.openSidebar()
        let row = app.buttons["Anything left today?"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)
        for name in ["Rename", "Archive", "Delete"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), "the menu has \(name)")
        }
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Rename asks for a new title")
        field.tap()
        // The field starts with the current title; clear it before typing the new one.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "Renamed chat")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Renamed chat"].waitForExistence(timeout: 5), "the new title shows in the list")
    }

    func testSidebarHasNoTabRowsAndShowsTheEmptyState() {
        app.openSidebar()
        XCTAssertTrue(app.buttons["New chat"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.staticTexts["Your conversations with AI will appear here."].exists)
        // The pill bar on the page behind owns these; the sidebar must not repeat them.
        for name in ["Today", "Calendar", "Reminders", "Alarms"] {
            XCTAssertFalse(app.buttons[name].exists, "no \(name) row in the sidebar")
        }
    }

    func testCloseButtonClosesTheSidebar() {
        app.openSidebar()
        let close = app.buttons["Close sidebar"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.buttons["Calendar"].firstMatch.waitForExistence(timeout: 8), "the page is back")
        // The closed sidebar stays built (so opening is instant) but sits behind the page: it can't be touched.
        let newChat = app.buttons["New chat"]
        let covered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: newChat)
        XCTAssertEqual(XCTWaiter().wait(for: [covered], timeout: 8), .completed, "the sidebar is out of reach once closed")
    }
}
