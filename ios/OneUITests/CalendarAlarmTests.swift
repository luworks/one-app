import XCTest

/// Alarms in the Calendar tab: Month's day list and grid marks, the 3 Day grid's chips, and Settings → "Show alarms in
/// Today and Calendar". Launched with the test dataset (alarms: 06:30 Wake up weekdays, 08:30 Weekend run off,
/// 13:00 Take medicine once, 22:30 Wind down Sun-Thu) and the clock pinned at 09:00, so "Take medicine" rings today.
@MainActor
final class CalendarAlarmTests: XCTestCase {
  var app: XCUIApplication!
  private let cal = Calendar.current

  /// The setting is a user default, which outlives the in-memory test store: the tests that need alarms on pin it to on,
  /// so a run that left it off can't break them. The setting test launches without the pin and puts the switch back.
  private static let pinAlarmsOn = ["-today.setting.showAlarmsInToday", "YES"]

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      launch(pinned: !name.contains("testTheSettingHides"))
    }
  }

  private func launch(pinned: Bool) {
    app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + ["-uiTestingNow", "09:00"] + (pinned ? Self.pinAlarmsOn : [])
    app.launch()
    app.buttons["Calendar"].firstMatch.tap()
  }

  private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
  private func mode(_ title: String) -> XCUIElement {
    app.buttons["calendar.mode.\(title.lowercased())"]
  }

  private var medicineRow: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "agenda.alarmRow")
      .matching(NSPredicate(format: "label BEGINSWITH 'Alarm Take medicine'")).firstMatch
  }

  private var medicineMarker: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "calendar.alarmMarker")
      .matching(NSPredicate(format: "label BEGINSWITH 'Alarm Take medicine'")).firstMatch
  }

  /// Month: today's list has the alarm with its time; tapping it opens the alarm editor.
  func testMonthListsTheAlarmAndOpensItsEditor() {
    mode("Month").tap()
    XCTAssertTrue(medicineRow.waitForExistence(timeout: 5), "the 13:00 alarm is in today's list")
    XCTAssertTrue(
      medicineRow.label.contains("1:00") || medicineRow.label.contains("13:00"),
      "with its time: \(medicineRow.label)")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Weekend run'"))
        .firstMatch.exists,
      "an alarm that is off is hidden, as on Today")
    medicineRow.tap()
    XCTAssertTrue(
      app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5), "the alarm editor opens")
    shot("month-editor")
    app.buttons["Cancel"].tap()
  }

  /// Month: the day cell counts the alarm in its accessibility value, and the list shows it before anything else is added.
  func testMonthDayCellCountsTheAlarm() {
    mode("Month").tap()
    let today = element(calendarDayID(.now))
    XCTAssertTrue(today.waitForExistence(timeout: 5))
    XCTAssertTrue(today.label.contains("alarm"), "the cell says it has an alarm: \(today.label)")
    shot("month")
  }

  /// 3 Day: the alarm is a one-line chip in today's column; tapping it opens the editor.
  func testThreeDayGridShowsTheAlarmMarker() {
    mode("ThreeDay").tap()
    XCTAssertTrue(element("calendar.dayGrid").waitForExistence(timeout: 5))
    sleep(1)
    shot("week")
    XCTAssertTrue(medicineMarker.waitForExistence(timeout: 5), "the 13:00 alarm is on the grid")
    medicineMarker.tap()
    XCTAssertTrue(
      app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5),
      "tapping the chip opens the alarm editor")
    XCTAssertEqual(
      app.textFields["alarm.label"].value as? String, "Take medicine",
      "the chip opens its own alarm")
  }

  /// Even an otherwise empty afternoon grid must let the alarm receive its tap.
  func testWeekLateAlarmOpensItsEditorWithoutOtherEntries() {
    app.terminate()
    app.launchArguments =
      TestData.fixtureArguments("week-alarm-afternoon.json")
      + ["-uiTestingNow", "09:00"] + Self.pinAlarmsOn
    app.launch()
    app.buttons["Calendar"].firstMatch.tap()
    mode("ThreeDay").tap()
    XCTAssertTrue(medicineMarker.waitForExistence(timeout: 5))
    medicineMarker.tap()
    XCTAssertTrue(app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields["alarm.label"].value as? String, "Take medicine")
  }

  /// 3 Day: a ring during an event takes the right half beside it, and remains a working tap target.
  func testThreeDayOverlappingEventAndAlarmHaveDisjointFramesAndOpenAlarmEditor() throws {
    try assertThreeDayOverlap(eventCount: 1)
  }

  func testThreeDayDenseOverlapClusterStaysInsideAssignedFramesAndOpensAlarmEditor() throws {
    try assertThreeDayOverlap(eventCount: 8)
  }

  private func assertThreeDayOverlap(eventCount: Int) throws {
    // Keep the one-event regression and also exercise columns narrower than the block's stripe and padding.
    app.terminate()
    app.launchArguments =
      TestData.fixtureArguments("week-alarm-overlap-\(eventCount).json")
      + ["-uiTestingNow", "09:00"] + Self.pinAlarmsOn
    app.launch()
    app.buttons["Calendar"].firstMatch.tap()
    mode("ThreeDay").tap()

    let grids = app.descendants(matching: .any).matching(identifier: "calendar.dayGrid")
    XCTAssertTrue(grids.firstMatch.waitForExistence(timeout: 5))
    guard
      let grid = grids.allElementsBoundByIndex.first(where: {
        $0.isFullyVisible(in: app.frame) && $0.isHittable
      })
    else {
      XCTFail("The 3 Day grid is visible")
      return
    }
    let event = grid.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Lane overlap event 0,'")).firstMatch
    let marker = grid.descendants(matching: .any).matching(identifier: "calendar.alarmMarker")
      .matching(NSPredicate(format: "label BEGINSWITH 'Alarm Lane overlap alarm at '")).firstMatch
    let visible = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        event.exists && marker.exists && event.isHittable && marker.isHittable
          && grid.frame.contains(event.frame) && grid.frame.contains(marker.frame)
          && self.app.frame.contains(event.frame) && self.app.frame.contains(marker.frame)
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter().wait(for: [visible], timeout: 5), .completed,
      "both overlapping items must be fully visible in the 3 Day grid: event \(event.exists ? event.frame : .null), alarm \(marker.exists ? marker.frame : .null), grid \(grid.frame)"
    )

    let eventFrame = event.frame
    let alarmFrame = marker.frame
    XCTAssertGreaterThan(eventFrame.width, 0)
    XCTAssertGreaterThan(alarmFrame.width, 0)
    XCTAssertGreaterThan(
      alarmFrame.minY, eventFrame.minY, "the ring is inside the event's time span")
    XCTAssertLessThan(alarmFrame.maxY, eventFrame.maxY, "the fixture exercises vertical overlap")
    XCTAssertLessThanOrEqual(
      eventFrame.maxX, alarmFrame.minX,
      "the event keeps the left half, the alarm chip the right: event \(eventFrame), alarm \(alarmFrame)"
    )
    let eventFrames = (0..<eventCount).map { index in
      grid.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "Lane overlap event \(index),"))
        .firstMatch
    }
    for block in eventFrames {
      XCTAssertTrue(block.exists)
      XCTAssertTrue(block.isHittable)
      XCTAssertGreaterThan(block.frame.width, 0)
      if eventCount == 8 {
        XCTAssertLessThan(
          block.frame.width, 9, "the dense fixture exercises the former minimum-content overflow")
      }
      XCTAssertLessThanOrEqual(
        block.frame.maxX, alarmFrame.minX,
        "even a dense block stays left of the alarm chip: \(block.frame)")
    }
    let sortedFrames = eventFrames.map({ $0.frame }).sorted { $0.minX < $1.minX }
    for (left, right) in zip(sortedFrames, sortedFrames.dropFirst()) {
      XCTAssertLessThanOrEqual(
        left.maxX, right.minX + 0.5, "adjacent blocks stay within their assigned columns")
    }
    marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["Edit Alarm"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.textFields["alarm.label"].value as? String, "Lane overlap alarm",
      "the tap opens this alarm, even beside an event")
  }

  /// Turning off "Show alarms in Today and Calendar" hides them from Month and 3 Day.
  func testTheSettingHidesAlarmsInTheCalendar() {
    mode("Month").tap()
    XCTAssertTrue(medicineRow.waitForExistence(timeout: 5))

    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let toggle = app.switches["Show alarms in Today and Calendar"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.value as? String, "1", "alarms show by default")
    // Whatever happens next, leave the switch on (it is a user default on this simulator).
    addTeardownBlock { [app = app!] in
      let reopen = XCUIApplication()
      reopen.launchArguments = app.launchArguments
      reopen.launch()
      reopen.openSidebar()
      reopen.buttons["Settings"].firstMatch.tap()
      let toggle = reopen.switches["Show alarms in Today and Calendar"]
      if toggle.waitForExistence(timeout: 5), (toggle.value as? String) == "0" {
        toggle.toggleSwitch()
      }
    }
    toggle.toggleSwitch()
    app.buttons["Done"].tap()
    app.closeSidebar()

    XCTAssertTrue(medicineRow.waitForNonExistence(timeout: 5), "no alarm rows in Month")
    XCTAssertFalse(
      element(calendarDayID(.now)).label.contains("alarm"), "and no alarm in the day cell")
    mode("ThreeDay").tap()
    XCTAssertTrue(element("calendar.dayGrid").waitForExistence(timeout: 5))
    XCTAssertTrue(medicineMarker.waitForNonExistence(timeout: 3), "and no markers in 3 Day")
  }

  /// Set TEST_RUNNER_ALARM_SHOTS=<folder> to save screenshots (for design review).
  private func shot(_ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["ALARM_SHOTS"] else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? app.screenshot().pngRepresentation.write(
      to: URL(fileURLWithPath: dir).appending(path: "calendar-alarms-\(name).png"))
  }
}
