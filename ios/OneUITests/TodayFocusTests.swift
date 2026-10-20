import XCTest

/// Production Focus interactions over synthetic local models; no Apple service or model-output injection.
@MainActor
final class TodayFocusTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  private func launch(store: String? = nil, seed: Bool = true, time: String = "09:00")
    -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments(seed ? "today-focus.json" : "empty-relaunch.json")
      + [
        "-uiTestingNow", time, "-uiTestingPrefs",
        "showTomorrow=0,showSnooze=1,suggestTimes=1,showFreeTime=1",
      ]
    if let store { app.launchArguments += ["-uiTestingStore", store] }
    app.launch()
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 8))
    return app
  }

  private func section(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons["focus.\(name)"].firstMatch
  }

  private func assertFocusSections(
    _ app: XCUIApplication, snoozed: Int, settled: Int,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertFalse(section("active", in: app).exists, "Active items have no collapse control")
    for (id, title, count) in [
      ("snoozed", "Snoozed", snoozed),
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
        var viewport = list.frame.intersection(app.frame).insetBy(dx: 0, dy: 8)
        if composer.exists {
          viewport.size.height = max(0, min(viewport.maxY, composer.frame.minY) - viewport.minY)
        }
        if element.exists {
          print(
            "Focus visibility: element=\(element.frame) viewport=\(viewport) hittable=\(element.isHittable)"
          )
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
    let text = app.staticTexts[title].firstMatch
    let row =
      text.exists
      ? text
      : app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", title + ",")
      ).firstMatch
    reveal(row, in: app)
    // A trailing swipe reveals the commands without a full-swipe default.
    let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    let end = start.withOffset(CGVector(dx: -min(270, app.frame.width * 0.7), dy: 0))
    start.press(forDuration: 0.05, thenDragTo: end)
    let button = app.buttons[action].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription)
    if action == "Settle" { screenshot("today-trailing-attention-actions") }
    button.tap()
  }

  private func restore(_ title: String, section name: String, in app: XCUIApplication) {
    let header = section(name, in: app)
    reveal(header, in: app)
    header.tap()
    let action = name == "settled" ? "Unsettle" : "Restore"
    let restore = app.buttons["\(action) \(title)"].firstMatch
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
    let row = app.staticTexts[title].firstMatch
    // Tab navigation retains the previously opened All list on the second source inspection.
    if !row.exists {
      let all = app.descendants(matching: .any)["smart.all"].firstMatch
      app.revealReminderPill(all)
      all.tap()
    }
    reveal(row, in: app)
    XCTAssertTrue(
      app.buttons["Complete \(title)"].exists, "Focus must keep the reminder incomplete")
    row.tap()
    XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 3))
  }

  private func deadlineSnapshot(in app: XCUIApplication) -> [String] {
    if app.buttons["task.more"].exists { app.buttons["task.more"].tap() }
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
    if app.buttons["task.more"].exists { app.buttons["task.more"].tap() }
    app.navigationBars["Reminder"].buttons["Cancel"].tap()
    app.buttons["Today"].firstMatch.tap()
  }

  private func setVisibility(settle: Bool, snooze: Bool, in app: XCUIApplication) {
    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    for (label, enabled) in [("Show Settle", settle), ("Show Snooze", snooze)] {
      let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", label))
        .firstMatch
      for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
      XCTAssertTrue(toggle.isHittable)
      if (toggle.value as? String == "1") != enabled { toggle.toggleSwitch() }
      XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }
    screenshot("focus-visibility-settings")
    app.buttons["Done"].tap()
    app.closeSidebar()
  }

  func testVisibilitySettingsKeepExistingChoicesAcrossRelaunchAndReenable() {
    let store = "focus-visibility-\(UUID().uuidString)"
    let app = launch(store: store)
    act("Settle", on: "Busy meeting", in: app)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["Tomorrow morning"].tap()
    setVisibility(settle: false, snooze: false, in: app)
    XCTAssertFalse(section("settled", in: app).exists)
    XCTAssertFalse(section("snoozed", in: app).exists)
    app.terminate()
    app.launchArguments =
      TestData.fixtureArguments("empty-relaunch.json") + [
        "-uiTestingStore", store, "-uiTestingNow", "09:00", "-uiTestingKeepPreferences",
      ]
    app.launch()
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 8))
    XCTAssertFalse(section("settled", in: app).exists)
    XCTAssertFalse(section("snoozed", in: app).exists)
    let row = app.staticTexts["Focus flexible"].firstMatch
    reveal(row, in: app)
    row.press(forDuration: 1)
    XCTAssertFalse(app.buttons["Settle"].exists)
    XCTAssertFalse(app.buttons["Snooze"].exists)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    setVisibility(settle: true, snooze: false, in: app)
    reveal(section("settled", in: app), in: app)
    XCTAssertEqual(section("settled", in: app).label, "Settled (1)")
    XCTAssertFalse(section("snoozed", in: app).exists)
    setVisibility(settle: true, snooze: true, in: app)
    assertFocusSections(app, snoozed: 1, settled: 1)
    restore("Busy meeting", section: "settled", in: app)
    restore("Focus invoice", section: "snoozed", in: app)
    assertFocusSections(app, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
  }

  func testUnsetPreferencesShowSettleAndHideSnooze() {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments("today-focus.json") + ["-uiTestingNow", "09:00"]
    app.launch()
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 8))
    let title = app.staticTexts["Focus invoice"].firstMatch
    reveal(title, in: app)
    title.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Settle"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Snooze"].exists)
    screenshot("focus-default-context-menu")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    act("Settle", on: "Focus invoice", in: app)
    reveal(section("settled", in: app), in: app)
    XCTAssertEqual(section("settled", in: app).label, "Settled (1)")
    XCTAssertFalse(section("snoozed", in: app).exists)
  }

  func testSettleToastUndoRestoresVisibleIncompleteReminder() {
    let app = launch()
    act("Settle", on: "Focus invoice", in: app)
    let undo = app.buttons["Undo"].firstMatch
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(
      app.staticTexts["undoToast.message"].label, "Hidden in Today only: “Focus invoice”")
    XCTAssertGreaterThanOrEqual(undo.frame.width, 44)
    XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
    XCTAssertTrue(undo.isHittable)
    screenshot("settle-toast-local-only-undo")
    undo.tap()
    XCTAssertTrue(app.buttons["Complete Focus invoice"].firstMatch.waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["undoToast.message"].exists)
    XCTAssertTrue(app.buttons["Ask AI or add anything"].isHittable)
  }

  func testSettleAndRestoreChangeFocusCountsWithoutCompletingReminder() {
    let app = launch()
    assertFocusSections(app, snoozed: 0, settled: 0)
    let title = app.staticTexts["Focus invoice"].firstMatch
    reveal(title, in: app)
    screenshot("before.png")
    title.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Settle"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Snooze"].exists)
    screenshot("today-native-attention-context-menu")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    act("Settle", on: "Focus invoice", in: app)
    assertFocusSections(app, snoozed: 0, settled: 1)
    XCTAssertTrue(title.waitForNonExistence(timeout: 3), "Collapsed Settled hides the active row")
    screenshot("after.png")
    openReminderSource("Focus invoice", in: app)
    XCTAssertEqual(app.textFields["task.title"].value as? String, "Focus invoice")
    closeReminder(in: app)
    restore("Focus invoice", section: "settled", in: app)
    assertFocusSections(app, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
    screenshot("active-always-visible-after-restore.png")
    // Explicit Delete is separate from Settle and uses the confirmed action; its local-only Undo restores a source row.
    app.staticTexts["Focus invoice"].firstMatch.swipeLeft()
    app.buttons["Delete"].firstMatch.tap()
    let confirm = app.buttons["Delete Reminder"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 3))
    confirm.tap()
    XCTAssertTrue(app.staticTexts["Focus invoice"].firstMatch.waitForNonExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 3))
    app.buttons["Undo"].firstMatch.tap()
    assertFocusSections(app, snoozed: 0, settled: 0)
  }

  func testAlarmAttentionRestoresAndDeleteRequiresConfirmation() {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments("today-alarm-actions.json") + [
        "-uiTestingNow", "12:00", "-uiTestingPrefs", "showTomorrow=0,showSnooze=1",
        "-today.setting.jumpToNow", "NO", "-today.setting.healthSummary", "NO",
      ]
    app.launch()
    let row = app.buttons.matching(identifier: "today.alarm.row")
      .matching(NSPredicate(format: "label CONTAINS 'Timeline alarm'")).firstMatch
    reveal(row, in: app)
    row.swipeLeft()
    XCTAssertTrue(app.buttons["Settle"].waitForExistence(timeout: 3))
    screenshot("alarm-trailing-attention-actions")
    app.buttons["Settle"].tap()
    assertFocusSections(app, snoozed: 0, settled: 1)
    restore("Timeline alarm", section: "settled", in: app)
    reveal(row, in: app)
    row.swipeLeft()
    app.buttons["Snooze"].tap()
    app.buttons["In 1 hour"].tap()
    assertFocusSections(app, snoozed: 1, settled: 0)
    restore("Timeline alarm", section: "snoozed", in: app)
    reveal(row, in: app)
    row.tap()
    XCTAssertTrue(app.textFields["alarm.label"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.textFields["alarm.label"].value as? String, "Timeline alarm")
    app.buttons["Cancel"].tap()
    reveal(row, in: app)
    row.swipeLeft()
    app.buttons["Delete"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Delete Alarm"].waitForExistence(timeout: 3))
    screenshot("alarm-confirmed-delete")
    // Native confirmation popovers omit Cancel at this size; tapping outside cancels.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    XCTAssertTrue(app.buttons["Delete Alarm"].waitForNonExistence(timeout: 3))
    XCTAssertTrue(row.exists, "Cancelling Delete keeps the source alarm")
  }

  func testAttentionRowsRemainReachableAtLargestTypeInDark() {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments("today-alarm-actions.json") + [
        "-uiTestingNow", "12:00", "-uiTestingPrefs", "showTomorrow=0,showSnooze=1",
        "-today.setting.jumpToNow", "NO", "-today.setting.healthSummary", "NO",
        "-appearance", "dark", "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXXL",
      ]
    app.launch()
    let row = app.buttons.matching(identifier: "today.alarm.row")
      .matching(NSPredicate(format: "label CONTAINS 'Timeline alarm'")).firstMatch
    reveal(row, in: app)
    XCTAssertTrue(row.isHittable)
    for button in [app.buttons["Today"], app.buttons["Ask AI or add anything"], app.buttons["New"]]
    {
      XCTAssertTrue(button.isHittable)
      XCTAssertGreaterThanOrEqual(button.frame.width, 44)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }
    screenshot("today-attention-dark-largest-type")
  }

  func testSnoozeKeepsDeadlineAndSourceAndUndoRestoresActiveRow() {
    let app = launch()
    openReminderSource("Focus invoice", in: app)
    let originalDue = deadlineSnapshot(in: app)
    closeReminder(in: app)
    screenshot("before-snooze.png")
    act("Snooze", on: "Focus invoice", in: app)
    XCTAssertTrue(app.navigationBars["Snooze"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Tomorrow morning"].exists)
    XCTAssertTrue(app.buttons["Choose date and time"].exists)
    app.buttons["In 1 hour"].tap()
    assertFocusSections(app, snoozed: 1, settled: 0)
    XCTAssertFalse(app.staticTexts["Focus invoice"].exists)
    screenshot("after-snooze.png")
    openReminderSource("Focus invoice", in: app)
    XCTAssertEqual(deadlineSnapshot(in: app), originalDue, "Snooze changes Focus visibility only")
    let originalList = app.descendants(matching: .any)["task.list"].firstMatch
    reveal(originalList, in: app)
    XCTAssertTrue(
      originalList.label.contains("Focus work"), "The original reminder list remains selected")
    closeReminder(in: app)
    restore("Focus invoice", section: "snoozed", in: app)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["In 1 hour"].tap()
    let undo = app.buttons["Undo"].firstMatch
    XCTAssertTrue(undo.waitForExistence(timeout: 3))
    undo.tap()
    assertFocusSections(app, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
  }

  func testFocusChoicesPersistAcrossRelaunchWithoutReseedingSourceModels() {
    let store = "today-focus-\(UUID().uuidString)"
    var app = launch(store: store)
    act("Settle", on: "Busy meeting", in: app)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["Tomorrow morning"].tap()
    assertFocusSections(app, snoozed: 1, settled: 1)
    app.terminate()
    app = launch(store: store, seed: false)
    assertFocusSections(app, snoozed: 1, settled: 1)
    XCTAssertFalse(app.staticTexts["Busy meeting"].exists)
    XCTAssertFalse(app.staticTexts["Focus invoice"].exists)
    restore("Busy meeting", section: "settled", in: app)
    restore("Focus invoice", section: "snoozed", in: app)
    assertFocusSections(app, snoozed: 0, settled: 0)
    act("Snooze", on: "Focus invoice", in: app)
    app.buttons["In 1 hour"].tap()
    assertFocusSections(app, snoozed: 1, settled: 0)
    app.terminate()
    app = launch(store: store, seed: false, time: "10:01")
    assertFocusSections(app, snoozed: 0, settled: 0)
    reveal(app.buttons["Complete Focus invoice"].firstMatch, in: app)
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
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", "Busy meeting")
      ).firstMatch.waitForExistence(timeout: 4),
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
    assertFocusSections(app, snoozed: 0, settled: 2)
    restore("Focus overdue", section: "settled", in: app)
    assertFocusSections(app, snoozed: 0, settled: 1)
    reveal(app.buttons["1 overdue"].firstMatch, in: app)
  }
}
