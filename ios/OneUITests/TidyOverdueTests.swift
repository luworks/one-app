import XCTest

/// "Tidy overdue" on the AI page: a new date per overdue reminder, changeable per row, written only on Apply, with Undo.
/// The dataset has one overdue reminder, "Pay studio invoice" (yesterday 17:00).
final class TidyOverdueTests: XCTestCase {
    func testTidyOverdueMovesTheDateOnlyOnApplyAndUndoBringsItBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()
        let overdueRow = app.buttons.containing(NSPredicate(format: "label CONTAINS '1 overdue'")).firstMatch
        XCTAssertTrue(overdueRow.waitForExistence(timeout: 10), "Today starts with one overdue reminder")

        app.buttons["Ask AI or add anything"].tap()
        let chip = app.buttons.matching(identifier: "ask-suggestion").matching(NSPredicate(format: "label == %@", "Tidy overdue")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()

        let choice = app.buttons["tidy.choice.Pay studio invoice"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the card lists the overdue reminder")
        XCTAssertEqual(choice.value as? String, "Today", "the most recent overdue one is suggested for today")
        choice.tap()
        app.buttons["Tomorrow"].firstMatch.tap()
        XCTAssertEqual(choice.value as? String, "Tomorrow", "the row takes the user's choice")

        // Nothing has changed yet: the card is only a preview.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(overdueRow.waitForExistence(timeout: 5), "still overdue before Apply")

        // Apply, then Undo on the same page: the old date is back.
        openTidy(app)
        app.buttons["tidy.apply"].tap()
        XCTAssertTrue(app.staticTexts["Moved 1 reminder."].firstMatch.waitForExistence(timeout: 5))
        app.buttons["ask-undo"].tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(overdueRow.waitForExistence(timeout: 5), "Undo puts the old date back")

        // Apply and keep it.
        openTidy(app)
        app.buttons["tidy.apply"].tap()
        XCTAssertTrue(app.staticTexts["Moved 1 reminder."].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(overdueRow.waitForNonExistence(timeout: 5), "no longer overdue after Apply")
        openTidy(app, expectCard: false)
        XCTAssertTrue(app.staticTexts["Nothing is overdue."].firstMatch.waitForExistence(timeout: 5))
    }

    private func openTidy(_ app: XCUIApplication, expectCard: Bool = true) {
        app.buttons["Ask AI or add anything"].tap()
        let chip = app.buttons.matching(identifier: "ask-suggestion").matching(NSPredicate(format: "label == %@", "Tidy overdue")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        if expectCard { XCTAssertTrue(app.buttons["tidy.apply"].waitForExistence(timeout: 5)) }
    }
}
