import XCTest

/// The AI page keeps its context between messages: a follow-up edits the preview or answers the last question,
/// and the options a question offers are real items that work the same way whether tapped or typed.
final class AskMultiTurnTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
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

    private func label(containing s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func testFollowUpChangesTheTimeOnTheSameCard() {
        send("Call Alex tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        send("make it 4pm")
        XCTAssertTrue(label(containing: "16:00").waitForExistence(timeout: 10), "the card now says 16:00")
        XCTAssertTrue(label(containing: "Call Alex").exists, "same item, not a new one called “make it 4pm”")
        XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1, "still one card")
        app.buttons["Add"].tap()
        XCTAssertTrue(label(containing: "Added “Call Alex”").waitForExistence(timeout: 5))
    }

    func testFollowUpMakesItAnAlarm() {
        send("Call Alex tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        send("make it an alarm")
        XCTAssertTrue(label(containing: "Alarm ").waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "New alarm").exists, "the card is an alarm now")
    }

    func testAskingWhichMeetingOffersRealItemsAndTapWorks() {
        send("Move the meeting back an hour")
        let choice = app.buttons["ask-choice"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 90), "the options are items from the calendar")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "ask-choice").count, 2)
        choice.tap()
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 10), "tapping one continues the sentence")
        XCTAssertTrue(label(containing: "Move event").exists)
    }

    func testAskingWhichMeetingAcceptsTypedAnswer() {
        send("Move the meeting back an hour")
        XCTAssertTrue(app.buttons["ask-choice"].firstMatch.waitForExistence(timeout: 90))
        send("the lunch one")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 10), "typing “the lunch one” works like tapping")
        XCTAssertFalse(label(containing: "Here's what I understood").exists, "it was not read as a new item")
    }

    func testMissingTimeIsAskedForThenAnswered() {
        send("Move Dentist")
        XCTAssertTrue(label(containing: "When should I move “Dentist” to?").waitForExistence(timeout: 90))
        send("5pm")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "→ Today 17:00").exists)
    }

    /// The sample data has "Dentist" at 15:00 today. A new request that merely mentions 3pm must not be read as an edit of it,
    /// and a clarification that describes a new thing must not become a ChangeCard either.
    func testNewRequestMentioningAnItemsTimeIsACaptureNotAnEdit() {
        send("请把我可以卖的东西都放到车库去，然后今天下午 3 点的时候提醒我移动一下")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90), "a preview card for a new reminder")
        XCTAssertFalse(app.otherElements["change-card"].exists)
        XCTAssertFalse(label(containing: "Which one").exists, "no question about existing items")
        send("哦，我想卖家里的一些东西，然后去 Marketplace。今天下午 3 点提醒我吧")
        XCTAssertTrue(label(containing: "Marketplace").waitForExistence(timeout: 90), "the card is the new reminder")
        XCTAssertTrue(label(containing: "15:00").exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1)
        XCTAssertFalse(app.otherElements["change-card"].exists, "never a change to an existing item")
        XCTAssertFalse(label(containing: "Here's the change").exists)
    }

    func testItMeansWhatWeTalkedAboutLast() {
        send("Call Alex tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        app.buttons["Add"].tap()
        XCTAssertTrue(label(containing: "Added “Call Alex”").waitForExistence(timeout: 5))
        send("move it to 5pm")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 90), "“it” is Call Alex")
        XCTAssertTrue(label(containing: "Call Alex").exists)
    }
}
