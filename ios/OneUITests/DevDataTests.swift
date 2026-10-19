import XCTest

/// The test dataset (tests/fixtures/today-dataset.json): the same data every launch, to try every screen in a simulator.
/// It loads with -uiTesting only, so Apple Calendar and Reminders sync stay off and the simulator's own calendar can't change it.
@MainActor
final class DevDataTests: XCTestCase {
    func testDatasetFillsChatsAlarmsAndReminders() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
        app.launch()

        app.openSidebar()
        XCTAssertTrue(app.buttons["Plan my day"].waitForExistence(timeout: 5), "chats from today")
        XCTAssertTrue(app.buttons["Move the dentist to tomorrow"].exists, "chats from yesterday")
        XCTAssertTrue(app.buttons["conversation.archived"].exists, "an archived chat")
        app.closeSidebar()

        app.buttons["Clock"].firstMatch.tap()
        let wake = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Wake up'")).firstMatch
        XCTAssertTrue(wake.waitForExistence(timeout: 5), "alarms")

        app.buttons["Reminders"].firstMatch.tap()
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Completed, 3'")).firstMatch
        app.revealReminderPill(completed)
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "completed reminders")
        let flagged = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Flagged, 3'")).firstMatch
        app.revealReminderPill(flagged)
        XCTAssertTrue(flagged.exists, "flagged reminders")
    }
}
