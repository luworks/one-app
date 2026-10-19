import XCTest

/// Production Focus interactions over synthetic local models; no Apple service or model-output injection.
@MainActor
final class TodayFocusTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  private func launch(store: String? = nil, seed: Bool = true) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments(seed ? "today-focus.json" : "empty-relaunch.json")
      + [
        "-uiTestingNow", "09:00", "-uiTestingPrefs", "showTomorrow=0,suggestTimes=1,showFreeTime=1",
      ]
    if let store { app.launchArguments += ["-uiTestingStore", store] }
    app.launch()
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 8))
    return app
  }

  private func section(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons["focus.\(name)"].firstMatch
  }

  private func assertCounts(
    _ app: XCUIApplication, active: Int, snoozed: Int, settled: Int,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for (id, title, count) in [
      ("active", "Active", active), ("snoozed", "Snoozed", snoozed),
      ("settled", "Settled", settled),
    ] {
      let header = section(id, in: app)
      reveal(header, in: app)
      let updated = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "label == %@", "\(title) (\(count))"), object: header)
      XCTAssertEqual(
        XCTWaiter.wait(for: [updated], timeout: 4), .completed,
        "\(id) count: \(header.label)", file: file, line: line)
    }
  }

  /// Keep drags inside the native List and above the composer; lazy rows need bounded discovery.
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 4))
    for up in [true, false] {
      for _ in 0..<7 {
        let composer = app.buttons["Ask AI or add anything"].firstMatch
        var viewport = list.frame.intersection(app.frame).insetBy(dx: 8, dy: 8)
        if composer.exists {
          viewport.size.height = max(0, min(viewport.maxY, composer.frame.minY) - viewport.minY)
        }
        if element.isFullyVisible(in: viewport), element.isHittable { return }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = viewport.midX - app.frame.minX
        let from = origin.withOffset(
          CGVector(dx: x, dy: viewport.minY - app.frame.minY + viewport.height * (up ? 0.8 : 0.25)))
        let to = origin.withOffset(
          CGVector(dx: x, dy: viewport.minY - app.frame.minY + viewport.height * (up ? 0.25 : 0.8)))
        from.press(forDuration: 0.05, thenDragTo: to)
      }
    }
    XCTFail("Control is not visible in the List: \(element)")
  }

  private func act(_ action: String, on title: String, in app: XCUIApplication) {
    let row = app.staticTexts[title].firstMatch
    reveal(row, in: app)
    // A partial leading swipe reveals both choices without triggering a full-swipe default.
    let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
    let end = start.withOffset(CGVector(dx: min(180, app.frame.width * 0.45), dy: 0))
    start.press(forDuration: 0.05, thenDragTo: end)
    let button = app.buttons[action].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription)
    button.tap()
  }

  private func restore(_ title: String, section name: String, in app: XCUIApplication) {
    let header = section(name, in: app)
    reveal(header, in: app)
    header.tap()
    let restore = app.buttons["Restore \(title)"].firstMatch
    reveal(restore, in: app)
    restore.tap()
  }

  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func openReminderSource(_ title: String, in app: XCUIApplication) {
    app.buttons["Reminders"].firstMatch.tap()
    let all = app.buttons["smart.all"].firstMatch
    app.revealReminderPill(all)
    all.tap()
    let row = app.staticTexts[title].firstMatch
    reveal(row, in: app)
    XCTAssertTrue(
      app.buttons["Complete \(title)"].exists, "Focus must keep the reminder incomplete")
    row.tap()
    XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 3))
  }

  private func deadlineSnapshot(in app: XCUIApplication) -> [String] {
    let deadline = app.switches["Deadline"]
    reveal(deadline, in: app)
    XCTAssertEqual(deadline.value as? String, "1")
    XCTAssertEqual(app.switches["Plan a time"].value as? String, "0")
    let due = app.datePickers.firstMatch
    XCTAssertTrue(due.exists)
    let values = due.descendants(matching: .button).allElementsBoundByIndex.map { $0.label }
    XCTAssertFalse(values.isEmpty, "The real Due picker exposes its unchanged date and time")
    return values
  }

  private func closeReminder(in app: XCUIApplication) {
    app.navigationBars["Reminder"].buttons["Cancel"].tap()
    app.buttons["Today"].firstMatch.tap()
  }

  func testSettleAndRestoreChangeFocusCountsWithoutCompletingReminder() {
    let app = launch()
    assertCounts(app, active: 4, snoozed: 0, settled: 0)
    let title = app.staticTexts["Focus invoice"].firstMatch
    reveal(title, in: app)
    screenshot("before.png")
    act("Settle", on: "Focus invoice", in: app)
    screenshot("after.png")
    assertCounts(app, active: 3, snoozed: 0, settled: 1)
    XCTAssertFalse(title.exists, "Collapsed Settled hides the active row")
    openReminderSource("Focus invoice", in: app)
    XCTAssertEqual(app.textFields["task.title"].value as? String, "Focus invoice")
    closeReminder(in: app)
    restore("Focus invoice", section: "settled", in: app)
    assertCounts(app, active: 4, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
  }

  func testSnoozeKeepsDeadlineAndSourceAndUndoRestoresActiveRow() {
    let app = launch()
    openReminderSource("Focus invoice", in: app)
    let originalDue = deadlineSnapshot(in: app)
    closeReminder(in: app)
    act("Snooze", on: "Focus invoice", in: app)
    XCTAssertTrue(app.navigationBars["Snooze"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Tomorrow morning"].exists)
    XCTAssertTrue(app.buttons["Choose date and time"].exists)
    app.buttons["In 1 hour"].tap()
    assertCounts(app, active: 3, snoozed: 1, settled: 0)
    XCTAssertFalse(app.staticTexts["Focus invoice"].exists)
    openReminderSource("Focus invoice", in: app)
    XCTAssertEqual(deadlineSnapshot(in: app), originalDue, "Snooze changes Focus visibility only")
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS 'Focus work'")).firstMatch.exists,
      "The original reminder list remains selected")
    closeReminder(in: app)
    restore("Focus invoice", section: "snoozed", in: app)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["In 1 hour"].tap()
    let undo = app.buttons["Undo"].firstMatch
    XCTAssertTrue(undo.waitForExistence(timeout: 3))
    undo.tap()
    assertCounts(app, active: 4, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
  }

  func testFocusChoicesPersistAcrossRelaunchWithoutReseedingSourceModels() {
    let store = "today-focus-\(UUID().uuidString)"
    var app = launch(store: store)
    act("Settle", on: "Busy meeting", in: app)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["Tomorrow morning"].tap()
    assertCounts(app, active: 2, snoozed: 1, settled: 1)
    app.terminate()
    app = launch(store: store, seed: false)
    assertCounts(app, active: 2, snoozed: 1, settled: 1)
    XCTAssertFalse(app.staticTexts["Busy meeting"].exists)
    XCTAssertFalse(app.staticTexts["Focus invoice"].exists)
    restore("Busy meeting", section: "settled", in: app)
    restore("Focus invoice", section: "snoozed", in: app)
    assertCounts(app, active: 4, snoozed: 0, settled: 0)
  }

  func testHiddenMeetingStillBlocksSuggestionsAndOverdueRequiresExplicitSettle() {
    let app = launch()
    let suggestion = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Plan Focus flexible at '")
    ).firstMatch
    reveal(suggestion, in: app)
    let originalSuggestion = suggestion.label
    let free = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Free '"))
    let originalFree = free.allElementsBoundByIndex.map { $0.label }
    XCTAssertFalse(originalFree.isEmpty)
    act("Settle", on: "Busy meeting", in: app)
    reveal(suggestion, in: app)
    XCTAssertEqual(
      suggestion.label, originalSuggestion, "Hidden meetings still reserve their actual time")
    XCTAssertEqual(free.allElementsBoundByIndex.map { $0.label }, originalFree)
    app.buttons["Calendar"].firstMatch.tap()
    app.buttons["calendar.mode.month"].tap()
    XCTAssertTrue(
      app.staticTexts["Busy meeting"].firstMatch.waitForExistence(timeout: 4),
      "Settling in Today preserves the Calendar source event")
    app.buttons["Today"].firstMatch.tap()
    let overdue = app.buttons["1 overdue"].firstMatch
    reveal(overdue, in: app)
    overdue.tap()
    let overdueTitle = app.staticTexts["Focus overdue"].firstMatch
    reveal(overdueTitle, in: app)
    XCTAssertTrue(
      app.buttons["Complete Focus overdue"].exists,
      "Overdue stays visible and incomplete until an explicit action")
    act("Settle", on: "Focus overdue", in: app)
    assertCounts(app, active: 2, snoozed: 0, settled: 2)
    restore("Focus overdue", section: "settled", in: app)
    assertCounts(app, active: 3, snoozed: 0, settled: 1)
    reveal(app.buttons["1 overdue"].firstMatch, in: app)
  }
}
