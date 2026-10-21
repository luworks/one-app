import XCTest

/// Today is one timeline: reminders due at a time sit at that time, reminders due today with no time are listed under
/// Anytime, and overdue reminders stay in the overdue line.
/// The clock is pinned to 09:41 so the timeline is the same at any time of day (see tests/fixtures/today-dataset.json).
@MainActor
final class TodayTimelineTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"]
      app.launch()
      XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    }
  }

  private func element(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }

  func testTodayNamesItsDayAndHasNoScheduleLabel() {
    let expected = Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    XCTAssertEqual(app.staticTexts["todayDate"].label, expected)
    XCTAssertFalse(app.staticTexts["Schedule"].exists, "the timeline needs no label of its own")
  }

  func testRowSubtitlesKeepTwoFactsAtMost() {
    // Buy milk: Home only; "Due Today" is implied by the timeline and the #errands tag stays in the detail sheet.
    XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS 'Due Today' OR label CONTAINS '#'")
      ).firstMatch.exists)
  }

  func testNoSeparateDueTodaySection() {
    XCTAssertFalse(app.staticTexts["Due today"].exists)
  }

  func testTimedReminderSitsAtItsTime() {
    let bank = element("Call the bank")
    let standup = element("Standup")
    let lunch = element("Lunch with Priya")
    XCTAssertTrue(
      bank.waitForExistence(timeout: 5), "a reminder due today at 11:30 is in the timeline")
    XCTAssertTrue(standup.exists && lunch.exists)
    XCTAssertGreaterThan(bank.frame.minY, standup.frame.minY, "11:30 comes after Standup at 09:45")
    XCTAssertLessThan(bank.frame.minY, lunch.frame.minY, "and before lunch at 12:15")
  }

  func testUntimedReminderStaysUnderAnytime() {
    XCTAssertTrue(
      element("Buy milk").waitForExistence(timeout: 5),
      "a reminder due today with no time is listed")
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan Buy milk'")).firstMatch
        .exists, "there is no suggested time or Plan button")
  }

  func testOverdueStaysOutOfTheTimeline() {
    let line = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'overdue'")).firstMatch
    XCTAssertTrue(line.waitForExistence(timeout: 5))
    XCTAssertEqual(line.label, "2 overdue")
    XCTAssertTrue(element("Product sync").exists, "the morning of the timeline is on screen")
    XCTAssertFalse(
      element("Renew parking permit").exists,
      "an overdue reminder is not a timeline row")
    line.tap()
    XCTAssertTrue(
      element("Renew parking permit").waitForExistence(timeout: 3), "it is in the overdue line")
  }
}
