import XCTest

/// The Ask page's suggestion chips are guesses made from the day's real data, not a fixed list: two or three chips, different
/// at different times, and a tap sends the chip's text like typed text. Runs on the test dataset with the clock pinned
/// (`-uiTestingNow`), and without a model (the simulator has none), so these are the rule-based chips.
final class AskSuggestionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(at time: String) {
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", time]
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
    }

    private var chips: XCUIElementQuery { app.buttons.matching(identifier: "ask-suggestion") }

    private func chipLabels() -> [String] {
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 10), "the suggestions show")
        return (0..<chips.count).map { chips.element(boundBy: $0).label }
    }

    func testTwoOrThreeChipsAndTappingOneSendsIt() {
        launch(at: "09:41")
        let labels = chipLabels()
        XCTAssertTrue((2...3).contains(labels.count), "2 or 3 suggestions, got \(labels)")
        XCTAssertFalse(labels.contains("Call Alex tomorrow at 3pm"), "no longer a fixed list")
        XCTAssertTrue(labels.contains("Plan my day"), "morning with free time and unplanned reminders: \(labels)")
        XCTAssertTrue(labels.contains("Tidy 2 overdue"), "the dataset has two overdue reminders: \(labels)")

        chips.matching(NSPredicate(format: "label == %@", "Tidy 2 overdue")).firstMatch.tap()
        // Sent as a message, and it routes like typed text: the tidy card for the two overdue reminders.
        XCTAssertTrue(app.staticTexts["Tidy 2 overdue"].waitForExistence(timeout: 5), "the chip's text is now the user's message")
        XCTAssertTrue(app.buttons["tidy.apply"].waitForExistence(timeout: 5), "and it opens the tidy preview")
        XCTAssertFalse(chips.firstMatch.exists, "the chips leave once the chat starts")
    }

    func testChipsDifferByTimeOfDay() {
        launch(at: "09:41")
        let morning = chipLabels()
        app.terminate()
        launch(at: "21:30")
        let night = chipLabels()
        XCTAssertNotEqual(morning, night, "morning \(morning) vs night \(night)")
        XCTAssertTrue(night.contains("Review today"), "after 18:00 the day can be reviewed: \(night)")
        XCTAssertFalse(night.contains("Plan my day"), "too late to plan: \(night)")
    }

    func testReviewTodayAnswersWithWhatGotDone() {
        launch(at: "21:30")
        _ = chipLabels()
        chips.matching(NSPredicate(format: "label == %@", "Review today")).firstMatch.tap()
        let reply = app.staticTexts.containing(NSPredicate(format: "label MATCHES %@", #"(?s).* of .* done\..*"#)).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "an answer, not a new reminder called “Review today”")
        XCTAssertFalse(app.buttons["Add"].exists, "nothing to add")
    }
}
