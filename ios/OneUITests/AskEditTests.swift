import XCTest

/// AI page flows on the sample data: capture sentences become preview cards, edit sentences become ChangeCards
/// (Apply / Undo) or a question. Uses the on-device model when the simulator has one (slow on the first call).
/// Screenshots are attached to the result bundle.
final class AskEditTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
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

    // MARK: Capture

    func testCapture_fiveSentences() {
        let cases: [(input: String, expect: [String], notExpect: [String])] = [
            ("Call Alex tomorrow at 3pm", ["Call Alex", "Planned Tomorrow"], []),
            ("周五晚上7点和朋友聚餐", ["和朋友聚餐", "19:00"], []),
            ("明早7点叫我起床", ["Alarm Tomorrow 07:00"], []),
            ("提醒我下周一交报销单", ["交报销单"], ["Alarm "]),
            ("30分钟后关烤箱", ["关烤箱", "Planned"], []),
        ]
        for (i, c) in cases.enumerated() {
            send(c.input)
            XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 90), "card for \(c.input)")
            for e in c.expect { XCTAssertTrue(label(containing: e).exists, "'\(e)' on the card for \(c.input)") }
            for n in c.notExpect { XCTAssertFalse(label(containing: n).exists, "no '\(n)' for \(c.input)") }
            shot("capture-\(i + 1)")
            if i == 0 { app.buttons["Add"].tap(); XCTAssertTrue(label(containing: "Added").waitForExistence(timeout: 5)) }
            else { app.buttons["Cancel"].tap() }
        }
    }

    // MARK: Edit

    func testEdit_moveEventApplyUndo() {
        send("Dentist 推迟一小时")
        let card = app.otherElements["change-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 90), "ChangeCard for the Dentist move")
        XCTAssertTrue(label(containing: "Move event").exists)
        XCTAssertTrue(label(containing: "Today 15:00 → Today 16:00").exists, "old → new time on the card")
        XCTAssertTrue(label(containing: "Only on your calendar").exists, "who is affected")
        shot("edit-1-event-card")
        app.buttons["Apply"].tap()
        XCTAssertTrue(label(containing: "Moved “Dentist”").waitForExistence(timeout: 5))
        shot("edit-1-applied")
        XCTAssertFalse(label(containing: "Attendee updates").exists, "no attendee note for a local event")
        app.buttons["ask-undo"].tap()
        XCTAssertFalse(app.buttons["ask-undo"].exists)
        // Undone: asking again starts from 15:00 again.
        send("Dentist 推迟一小时")
        XCTAssertTrue(label(containing: "Today 15:00 → Today 16:00").waitForExistence(timeout: 60), "the event is back at 15:00")
        shot("edit-1-undone")
    }

    func testEdit_moveTaskKeepsDeadline() {
        send("Prepare the demo 推迟两小时")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 90))
        XCTAssertTrue(label(containing: "Move task").exists)
        XCTAssertTrue(label(containing: "deadline stays").exists, "due is not moved")
        shot("edit-2-task-card")
        app.buttons["Apply"].tap()
        XCTAssertTrue(label(containing: "Moved “Prepare the demo”").waitForExistence(timeout: 5))
        shot("edit-2-applied")
    }

    func testEdit_moveEventToTomorrow() {
        send("Lunch with Priya 改到明天中午")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 90))
        XCTAssertTrue(label(containing: "Tomorrow 12:00").exists)
        shot("edit-3-card")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.otherElements["change-card"].exists, "Cancel writes nothing")
    }

    func testEdit_deleteTaskAndUndo() {
        send("取消 Buy milk")
        XCTAssertTrue(app.otherElements["change-card"].waitForExistence(timeout: 90))
        XCTAssertTrue(label(containing: "Delete task").exists)
        shot("edit-4-delete-card")
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["ask-undo"].waitForExistence(timeout: 5))
        shot("edit-4-deleted")
        app.buttons["ask-undo"].tap()
        XCTAssertFalse(app.buttons["ask-undo"].exists)
    }

    func testEdit_clarifyAsksInsteadOfCard() {
        send("把会议推迟一小时")
        XCTAssertTrue(label(containing: "Which one").waitForExistence(timeout: 90), "a question, not a card")
        XCTAssertFalse(app.otherElements["change-card"].exists)
        shot("edit-5-clarify-meeting")
        send("Move it to 5pm")
        XCTAssertTrue(label(containing: "Which item do you mean").waitForExistence(timeout: 90))
        shot("edit-5-clarify-it")
    }
}
