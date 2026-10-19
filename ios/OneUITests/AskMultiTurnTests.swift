import XCTest

/// The AI page keeps its context between messages: a follow-up edits the preview or answers the last question,
/// and the options a question offers are real items that work the same way whether tapped or typed.
@MainActor
final class AskMultiTurnTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-uiTesting"]
            app.launch()
            app.buttons["Ask AI or add anything"].tap()
        }
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
        XCTAssertTrue(app.descendants(matching: .any)["capture-added"].waitForExistence(timeout: 5), "the card stays, now Added")
        XCTAssertTrue(label(containing: "Call Alex").exists && label(containing: "16:00").exists, "with the edited time")
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

    func testNewReminderInterruptsAnExistingEventsTimePrompt() {
        send("Move Dentist")
        XCTAssertTrue(label(containing: "When should I move “Dentist” to?").waitForExistence(timeout: 20))
        send("Remind me to call Mom tomorrow at 5pm")
        let card = app.descendants(matching: .any)["capture-stack"].firstMatch
        XCTAssertTrue(card.buttons["Add"].waitForExistence(timeout: 20), "the new request gets its own preview")
        XCTAssertTrue(card.staticTexts["call Mom"].exists)
        XCTAssertTrue(card.staticTexts.containing(NSPredicate(format: "label CONTAINS '17:00'")).firstMatch.exists)
        XCTAssertFalse(app.otherElements["change-card"].exists, "no proposed move of Dentist")
        card.buttons["Add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-added"].waitForExistence(timeout: 5))

        // Adding the unrelated reminder has not moved the existing event.
        send("Move Dentist")
        send("5pm")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "Today 15:00 → Today 17:00").exists)
        XCTAssertTrue(app.buttons["Apply"].exists, "the event still needs explicit approval")
        XCTAssertFalse(label(containing: "Moved “Dentist”").exists)
    }

    func testEnglishQuestionTimeAnswerPreservesConversationAndRequiresApply() {
        assertQuestionTimeAnswer("How about 5pm?", conversation: "Did I set an alarm for 7am?")
    }

    func testChineseQuestionTimeAnswerPreservesConversationAndRequiresApply() {
        assertQuestionTimeAnswer("下午5点，可以吗？", conversation: "我是不是设了7点的闹钟？")
    }

    func testReminderQuestionPreservesTimeFollowupAndChangeUntilApply() {
        assertQuestionTimeAnswer("How about 5pm?", conversation: "Did I add a reminder for 7am?")
    }

    func testPoliteStoryQuestionPreservesTimeFollowupAndChangeUntilApply() {
        assertQuestionTimeAnswer("How about 5pm?", conversation: "Can you write a story?")
    }

    func testChineseExistingReminderQuestionPreservesTimeFollowupAndChangeUntilApply() {
        assertQuestionTimeAnswer("下午5点，可以吗？", conversation: "有没有人提醒我明天的会议？")
    }

    func testChineseAddedReminderQuestionPreservesTimeFollowupAndChangeUntilApply() {
        assertQuestionTimeAnswer("How about 5pm?", conversation: "有人添加了一个提醒吗？")
    }

    private func assertQuestionTimeAnswer(_ answer: String, conversation: String) {
        send("Move Dentist")
        XCTAssertTrue(label(containing: "When should I move “Dentist” to?").waitForExistence(timeout: 90))
        send(conversation)
        let expectedReply = conversation.range(of: #"\p{Han}"#, options: .regularExpression) != nil
            ? "我们可以直接聊聊" : "We can just chat"
        XCTAssertTrue(label(containing: expectedReply).waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["change-card"].exists)
        XCTAssertFalse(app.buttons["Add"].exists)
        send(answer)
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "Today 15:00 → Today 17:00").exists)
        XCTAssertTrue(app.buttons["Apply"].exists)
        XCTAssertFalse(label(containing: "Moved “Dentist”").exists)
        // A later question with another time must leave the proposed move intact.
        send(conversation)
        XCTAssertTrue(label(containing: "Today 15:00 → Today 17:00").exists)
        XCTAssertTrue(app.buttons["Apply"].exists)
        tapStableApplyAboveComposer()
        XCTAssertTrue(label(containing: "Moved “Dentist”").waitForExistence(timeout: 5))
    }

    /// Sending another turn scrolls the existing card while the keyboard and composer settle.
    /// Matching the reply text again would accept the identical reply from the previous turn.
    private func tapStableApplyAboveComposer() {
        var previousFrame: CGRect?
        let ready = NSPredicate { [self] _, _ in
            let apply = app.buttons["Apply"].firstMatch
            let composer = field
            guard apply.exists, apply.isHittable, composer.exists else {
                previousFrame = nil
                return false
            }
            let frame = apply.frame
            var visible = app.frame
            visible.size.height = max(0, composer.frame.minY - visible.minY)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                visible.size.height = min(visible.height, keyboard.frame.minY - visible.minY)
            }
            guard frame.width > 0, frame.height > 0, visible.contains(frame) else {
                previousFrame = nil
                return false
            }
            defer { previousFrame = frame }
            guard let previousFrame else { return false }
            return abs(frame.minX - previousFrame.minX) < 1
                && abs(frame.minY - previousFrame.minY) < 1
                && abs(frame.width - previousFrame.width) < 1
                && abs(frame.height - previousFrame.height) < 1
        }
        let settled = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10)
        XCTAssertEqual(settled, .completed, "Apply is fully visible above the composer with a stable frame")
        guard settled == .completed else { return }
        // Reacquire after the wait; element.tap() can reuse a pre-scroll activation point.
        let frame = app.buttons["Apply"].firstMatch.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY)).tap()
    }

    /// The sample data has "Dentist" at 15:00 today. A new request that merely mentions 3pm must not be read as an edit of it,
    /// and a clarification that describes a new thing must not become a ChangeCard either.
    func testNewRequestMentioningAnItemsTimeIsACaptureNotAnEdit() {
        send("请把我可以卖的东西都放到车库去，然后今天下午 3 点的时候提醒我移动一下")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90), "a preview card for a new reminder")
        XCTAssertFalse(app.otherElements["change-card"].exists)
        XCTAssertFalse(label(containing: "Which one").exists, "no question about existing items")
        send("哦，我想卖家里的一些东西，然后去 Marketplace。今天下午 3 点提醒我吧")
        let card = app.descendants(matching: .any)["capture-stack"]
        let newTitle = card.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Marketplace")).firstMatch
        XCTAssertTrue(newTitle.waitForExistence(timeout: 90), "wait for the new preview, not the echoed user message")
        XCTAssertTrue(label(containing: "15:00").exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Add").count, 1)
        XCTAssertFalse(app.otherElements["change-card"].exists, "never a change to an existing item")
        XCTAssertFalse(label(containing: "Here's the change").exists)
    }

    func testItMeansWhatWeTalkedAboutLast() {
        send("Call Alex tomorrow at 3pm")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90))
        app.buttons["Add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-added"].waitForExistence(timeout: 5))
        send("move it to 5pm")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 90), "“it” is Call Alex")
        XCTAssertTrue(label(containing: "Call Alex").exists)
    }
}
