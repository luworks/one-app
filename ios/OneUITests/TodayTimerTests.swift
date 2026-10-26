import XCTest

/// Running timers on the Today tab: a quiet live row at the top of the day (up to 2, then "+N more"), Pause/Resume/Stop
/// by swiping the row, tap to open the Timer tab. The simulator denies AlarmKit, so these launches pass
/// `-uiTestingTimers`, which seeds timers and replaces AlarmKit with a fake (the list changes, nothing rings).
/// The countdown itself is drawn by the system (`Text(timerInterval:)`); ringing is checked on a phone.
@MainActor
final class TodayTimerTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() { continueAfterFailure = false }

  private func launch(timers: String?) {
    app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + (timers.map { ["-uiTestingTimers", $0] } ?? [])
    app.launch()
    XCTAssertTrue(app.staticTexts["weekStrip.month"].waitForExistence(timeout: 5))
  }

  private var rows: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "todayTimerRow")
  }
  private var more: XCUIElement { app.descendants(matching: .any)["todayTimerMore"].firstMatch }

  func testNoTimerNoRow() {
    launch(timers: nil)
    XCTAssertFalse(
      rows.firstMatch.waitForExistence(timeout: 1.5), "nothing runs: Today shows no timer row")
    XCTAssertFalse(more.exists)
  }

  func testTwoRowsThenMore() {
    launch(timers: "600:Pasta,1500:Tea,900,300:Eggs:paused")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 2, "at most two rows")
    XCTAssertTrue(
      rows.element(boundBy: 0).label.hasPrefix("Pasta"),
      "soonest first: \(rows.element(boundBy: 0).label)")
    XCTAssertTrue(
      rows.element(boundBy: 1).label.hasPrefix("Timer"), "an unnamed timer is called Timer")
    XCTAssertTrue(more.exists)
    XCTAssertEqual(more.label, "+2 more")
    // The rows sit at the top of the day, right under the week strip.
    XCTAssertLessThanOrEqual(
      app.weekStripDay(.now).frame.maxY, rows.element(boundBy: 0).frame.minY + 1)
  }

  func testPauseResumeAndStopFromTheRow() {
    launch(timers: "600:Pasta")
    let row = rows.firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertFalse(row.label.contains("paused"))

    row.swipeLeft()
    app.buttons["Pause"].firstMatch.tap()
    XCTAssertTrue(waitFor(label: "paused"), "the row says paused: \(rows.firstMatch.label)")

    rows.firstMatch.swipeLeft()
    app.buttons["Resume"].firstMatch.tap()
    XCTAssertTrue(
      waitFor(label: "left", without: "paused"), "running again: \(rows.firstMatch.label)")

    rows.firstMatch.swipeLeft()
    app.buttons["Stop"].firstMatch.tap()
    XCTAssertFalse(
      rows.firstMatch.waitForExistence(timeout: 2), "Stop removes the timer from Today")
  }

  func testTapOpensTheTimerTab() {
    launch(timers: "600:Pasta")
    let row = rows.firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["timer.picker"].firstMatch.waitForExistence(timeout: 5),
      "the Timer tab opens")
    XCTAssertTrue(
      app.descendants(matching: .any)["timer.card"].firstMatch.exists,
      "the timer is listed there too")
  }

  func testStartingOnTheTimerTabShowsOnToday() {
    launch(timers: "x")  // the fake alarms, with nothing running yet
    app.buttons["Clock"].firstMatch.tap()
    let section = app.buttons["clock.section.timer"].firstMatch
    XCTAssertTrue(section.waitForExistence(timeout: 5))
    section.tap()
    // Nothing is on the wheel yet: play the Focus preset at the top of Recents.
    let play = app.buttons["timer.recent.start"].firstMatch
    app.revealTimerControl(play)
    play.tap()
    app.scrollTimerToTop()
    XCTAssertTrue(
      app.descendants(matching: .any)["timer.remaining"].firstMatch.waitForExistence(timeout: 5),
      "the card counts down")

    app.buttons["Today"].firstMatch.tap()
    XCTAssertTrue(
      rows.firstMatch.waitForExistence(timeout: 5), "the running Focus timer is on Today")
    XCTAssertTrue(rows.firstMatch.label.hasPrefix("Focus"), rows.firstMatch.label)
  }

  func testTimerTabNotesWhatSiriCannotShare() {
    launch(timers: nil)
    app.buttons["Clock"].firstMatch.tap()
    app.buttons["clock.section.timer"].firstMatch.tap()
    let note = app.staticTexts["timer.siriNote"]
    app.revealTimerControl(note)
    XCTAssertTrue(note.label.contains("aren't visible to other apps"), note.label)
    XCTAssertTrue(note.label.contains("Start a timer in Today"), note.label)
  }

  /// Waits for the first timer row's label to contain `label` (and not `without`).
  private func waitFor(label: String, without: String? = nil, timeout: TimeInterval = 3) -> Bool {
    let format =
      without.map { "label CONTAINS '\(label)' AND NOT (label CONTAINS '\($0)')" }
      ?? "label CONTAINS '\(label)'"
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: format), object: rows.firstMatch)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }
}
