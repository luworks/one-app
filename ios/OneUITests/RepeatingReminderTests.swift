import XCTest

/// Completing a repeating reminder from Today: it leaves today's timeline for good (not just its done state), shows on its
/// next day and in Scheduled with the new date, and Undo brings back the very same row at the same time.
/// Own tiny dataset (one daily reminder due 07:00, planned 09:00 today), so the shared fixture stays as it is.
/// The Apple Reminders side (Apple rolls the reminder, the app drops the finished occurrence's plan) is covered by
/// `RepeatAdvanceTests` in the logic package; Apple Reminders sync is off in these runs.
@MainActor
final class RepeatingReminderTests: XCTestCase {
    private var app: XCUIApplication!
    private let title = "Clean the drain filter"
    private let dueLine = "Due 07:00 · ↻"

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = TestData.fixtureArguments("repeating-reminder-daily-home.json")
                + ["-uiTestingNow", "09:41"]
            app.launch()
            XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        }
    }

    private var circle: XCUIElement { app.buttons["Complete \(title)"] }

    /// How many rows of the reminder sit above the Tomorrow header, i.e. in today's own timeline.
    private func rowsOnToday() -> Int {
        let header = app.buttons["tomorrowHeader"]
        let circles = app.buttons.matching(NSPredicate(format: "label == %@", "Complete \(title)")).allElementsBoundByIndex
        return circles.filter { !header.exists || $0.frame.minY < header.frame.minY }.count
    }

    func testCompletingARepeatingReminderMovesItToItsNextDay() {
        XCTAssertTrue(circle.waitForExistence(timeout: 5), "the reminder is on today's timeline")
        XCTAssertEqual(rowsOnToday(), 1)

        circle.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Completed “\(title)”")).firstMatch
            .waitForExistence(timeout: 3), "the toast says it is done")
        // Only the Tomorrow preview below today's timeline may still list it.
        let header = app.buttons["tomorrowHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 3), "tomorrow now has it")
        XCTAssertEqual(rowsOnToday(), 0, "it leaves today's timeline")

        // Its next occurrence is tomorrow's own day.
        header.tap()
        XCTAssertTrue(app.buttons["Back to today"].waitForExistence(timeout: 5), "tomorrow opens as a day of its own")
        XCTAssertTrue(circle.waitForExistence(timeout: 3), "the next occurrence is on tomorrow")
        app.buttons["Back to today"].tap()
        XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
        XCTAssertEqual(rowsOnToday(), 0, "and still not on today")

        // Scheduled lists it once, with the new date.
        app.buttons["Reminders"].firstMatch.tap()
        let scheduled = app.descendants(matching: .any)["smart.scheduled"]
        app.revealReminderPill(scheduled)
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        scheduled.tap()
        let rows = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "it is in Scheduled")
        XCTAssertEqual(rows.count, 1, "once: the finished occurrence is not listed")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tomorrow'")).firstMatch.exists,
                      "with tomorrow as its date")
    }

    func testUndoBringsBackTheSameRowAtTheSameTime() {
        XCTAssertTrue(circle.waitForExistence(timeout: 5))
        let before = circle.frame.minY
        XCTAssertTrue(app.staticTexts[dueLine].exists)
        XCTAssertEqual(rowsOnToday(), 1)

        circle.tap()
        XCTAssertTrue(app.buttons["tomorrowHeader"].waitForExistence(timeout: 3))
        XCTAssertEqual(rowsOnToday(), 0, "completed, it left today")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()

        XCTAssertTrue(circle.waitForExistence(timeout: 3))
        XCTAssertEqual(rowsOnToday(), 1, "Undo brings the reminder back")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Complete \(title)")).count, 1,
                       "and the next occurrence Undo took away is not left on tomorrow")
        XCTAssertEqual(circle.frame.minY, before, accuracy: 1, "at the same place on the timeline, so at the same time")
        XCTAssertTrue(app.staticTexts["09:00"].exists, "planned at 09:00 as before")
        XCTAssertTrue(app.staticTexts[dueLine].exists, "with its deadline untouched")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", title)).count, 1, "one row, not two")
    }
}
