import XCTest

/// Today is one timeline: reminders due at a time sit at that time, reminders due today with no time get a
/// suggested free time (saved only on Plan), and overdue reminders stay in the overdue line.
/// The clock is pinned to 09:41 so the suggestions are the same at any time of day (see tests/fixtures/today-dataset.json).
final class TodayTimelineTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5))
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    func testNoSeparateDueTodaySection() {
        XCTAssertFalse(app.staticTexts["Due today"].exists)
    }

    func testTimedReminderSitsAtItsTime() {
        let bank = element("Call the bank"), standup = element("Standup"), lunch = element("Lunch with Priya")
        XCTAssertTrue(bank.waitForExistence(timeout: 5), "a reminder due today at 11:30 is in the timeline")
        XCTAssertTrue(standup.exists && lunch.exists)
        XCTAssertGreaterThan(bank.frame.minY, standup.frame.minY, "11:30 comes after Standup at 09:45")
        XCTAssertLessThan(bank.frame.minY, lunch.frame.minY, "and before lunch at 12:15")
    }

    func testUntimedReminderIsSuggestedAndPlannedOnTap() {
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan Buy milk at '")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5), "a reminder due today with no time gets a suggested time")
        XCTAssertTrue(element("Suggested").exists)
        plan.tap()
        XCTAssertTrue(element("Planned “Buy milk”").waitForExistence(timeout: 3), "Plan shows an Undo toast")
        XCTAssertFalse(plan.exists, "once planned it is a normal row")
        XCTAssertTrue(element("Buy milk").exists)
    }

    func testFreeTimeShowsAfterTheSuggestions() {
        let free = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Free '")).firstMatch
        XCTAssertTrue(free.waitForExistence(timeout: 5), "free time of 30 minutes or more shows as a quiet row")
        let milk = element("Buy milk")
        XCTAssertTrue(milk.exists)
        XCTAssertLessThan(milk.frame.minY, free.frame.minY, "the suggestion takes the first gap; what is left stays free")
    }

    func testOverdueStaysOutOfTheTimeline() {
        let line = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'overdue'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.label, "2 overdue")
        XCTAssertTrue(element("Product sync").exists, "the morning of the timeline is on screen")
        XCTAssertFalse(element("Renew parking permit").exists, "an overdue reminder planned today is not a timeline row")
        line.tap()
        XCTAssertTrue(element("Renew parking permit").waitForExistence(timeout: 3), "it is in the overdue line")
    }
}
