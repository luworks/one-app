import XCTest

/// The Calendar tab (modeled on Apple Calendar): Month grid with the day's list, paging, Year, 2 Day, and the Calendars filter.
/// Launched with -uiTesting: a fresh in-memory store with sample data (events today and tomorrow, "Team offsite" in two days).
@MainActor
final class CalendarTabTests: XCTestCase {
  var app: XCUIApplication!
  private let cal = Calendar.current

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments = ["-uiTesting", "-uiTestingCalendarSync"]
      app.launch()
      app.buttons["Calendar"].firstMatch.tap()
    }
  }

  private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

  /// The Calendar tab opens on the next 2 days; the Month tests switch to Month first.
  private func showMonth() { modeButton("Month").tap() }

  /// The 2 Day / Month / Year pills (buttons, not a segmented control), by identifier: "TwoDay", "Month", "Year".
  private func modeButton(_ title: String) -> XCUIElement {
    app.buttons["calendar.mode.\(title.lowercased())"]
  }

  /// The top bar's month label for a page that shows one month ("October 2026").
  private func monthNames(_ date: Date) -> [String] {
    [
      date.formatted(.dateTime.month(.wide).year()),
      date.formatted(.dateTime.month(.abbreviated).year()),
    ]
  }

  /// The month label is in the top bar on every tab; wait until it names `month`.
  @discardableResult
  private func waitForMonthLabel(_ month: Date, timeout: TimeInterval = 5) -> Bool {
    let label = element("topBar.month")
    let named = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label IN %@", monthNames(month)), object: label)
    return XCTWaiter().wait(for: [named], timeout: timeout) == .completed
  }

  private func dayID(_ date: Date) -> String {
    let c = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "day.%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }

  /// The default view is 2 Day: one switcher row (2 Day / Month / Year), no Day segment, no Today or Calendars
  /// buttons, and the grid starts on today.
  func testTwoDayIsTheDefault() {
    XCTAssertTrue(modeButton("TwoDay").waitForExistence(timeout: 5))
    let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.mode.'"))
    XCTAssertEqual(
      pills.allElementsBoundByIndex.map({ $0.label }), ["2 Day", "Month", "Year"],
      "one switcher: 2 Day / Month / Year (Day is the Today tab, no 7-day Week)")
    XCTAssertFalse(app.segmentedControls.buttons["Month"].exists, "pills, not a segmented control")
    XCTAssertTrue(modeButton("TwoDay").isSelected, "2 Day is selected when the tab opens")
    XCTAssertFalse(modeButton("Month").isSelected)
    XCTAssertTrue(
      element("topBar.month").waitForExistence(timeout: 5), "the top bar names the month")
    for offset in 0..<2 {
      XCTAssertTrue(
        onScreen(dayHeader(offset)), "today and tomorrow are the columns (day \(offset))")
    }
    XCTAssertFalse(dayHeader(2).isFullyVisible(in: app.frame), "only two columns")
    XCTAssertFalse(
      app.buttons["calendar.today"].exists || app.buttons["calendar.calendars"].exists
        || app.buttons["calendar.year"].exists)
  }

  /// The header button of the day `offset` days from today (its label is the full date).
  private func dayHeader(_ offset: Int) -> XCUIElement {
    let day = cal.date(byAdding: .day, value: offset, to: .now)!
    return app.buttons[day.formatted(date: .complete, time: .omitted)].firstMatch
  }

  /// Waits until the element is entirely on screen (columns off to either side exist but are clipped).
  private func onScreen(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let end = Date.now.addingTimeInterval(timeout)
    repeat {
      if e.isFullyVisible(in: app.frame) { return true }
      RunLoop.current.run(until: .now.addingTimeInterval(0.2))
    } while Date.now < end
    return false
  }

  /// A swipe moves the grid by one day, like Apple Calendar's multi-day view; a swipe back returns to today.
  func testTwoDaySwipeMovesOneDay() {
    let grid = element("calendar.dayGrid")
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    grid.swipeLeft()
    XCTAssertTrue(onScreen(dayHeader(2)), "the day after the second comes in from the right")
    XCTAssertFalse(dayHeader(0).isFullyVisible(in: app.frame), "today moved off to the left")
    XCTAssertFalse(
      dayHeader(3).isFullyVisible(in: app.frame), "one day per swipe, not a page of two")
    grid.swipeRight()
    XCTAssertTrue(onScreen(dayHeader(0)), "back to today")
  }

  /// A day picked in Month opens 2 Day on that day.
  func testTwoDayStartsOnTheDayPickedInMonth() {
    showMonth()
    let target = cal.date(byAdding: .day, value: 5, to: .now)!
    if !cal.isDate(target, equalTo: .now, toGranularity: .month) {
      element("calendar.monthPager").swipeUp()
    }
    let cell = element(dayID(target))
    XCTAssertTrue(cell.waitForExistence(timeout: 5))
    cell.tap()
    modeButton("TwoDay").tap()
    XCTAssertTrue(onScreen(dayHeader(5)), "the picked day is the first column")
    XCTAssertFalse(dayHeader(0).isFullyVisible(in: app.frame), "not today")
  }

  /// Month: the top bar names the month, weekday letters, grid, and today's events below.
  func testMonthListsTodaysEvents() {
    showMonth()
    XCTAssertTrue(waitForMonthLabel(.now), "the top bar names this month")
    XCTAssertTrue(element(dayID(.now)).exists, "today is in the grid")
    let today = element(dayID(.now))
    let selected = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isSelected == true"), object: today)
    XCTAssertEqual(
      XCTWaiter().wait(for: [selected], timeout: 3), .completed,
      "and selected: \(today.debugDescription)")
    let first = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Product sync'")
    ).firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 5), "today's events are listed under the grid")
  }

  /// Each vertical swipe moves exactly one month; the top bar remains the device month.
  func testMonthPaging() {
    showMonth()
    let pager = element("calendar.monthPager")
    XCTAssertTrue(pager.waitForExistence(timeout: 5))
    let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
    func middleDay(_ offset: Int) -> XCUIElement {
      let month = cal.date(byAdding: .month, value: offset, to: start)!
      return element(dayID(cal.date(byAdding: .day, value: 14, to: month)!))
    }
    func assertPage(_ offset: Int, _ message: String) {
      let day = middleDay(offset)
      let visible = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in day.isFullyVisible(in: pager.frame) }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [visible], timeout: 5), .completed, message)
    }

    assertPage(0, "starts on the current month")
    pager.swipeUp(velocity: .fast)
    assertPage(1, "one fast swipe up advances exactly one month")
    pager.swipeDown(velocity: .fast)
    assertPage(0, "one fast swipe down returns exactly one month")
    pager.swipeDown()
    assertPage(-1, "one swipe down moves exactly one month earlier")
    pager.swipeLeft()
    assertPage(-1, "a horizontal swipe does not change the month")
    XCTAssertTrue(modeButton("Month").isSelected, "a horizontal grid swipe keeps Calendar open")
    element("calendar.dayList").swipeUp()
    assertPage(-1, "scrolling the day list does not change the month")
    XCTAssertTrue(waitForMonthLabel(start), "the top bar still names the device month")
    XCTAssertFalse(app.buttons["calendar.today"].exists, "paging does not add a Today button")
  }

  /// Tapping a day selects it and lists its events below the grid, all-day first.
  func testSelectingADayListsItsEvents() throws {
    let twoDays = cal.date(byAdding: .day, value: 2, to: .now)!
    try XCTSkipUnless(
      cal.isDate(twoDays, equalTo: .now, toGranularity: .month),
      "needs the sample events in this month's grid")
    showMonth()
    let cell = element(dayID(twoDays))
    XCTAssertTrue(cell.waitForExistence(timeout: 5))
    cell.tap()
    let row = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Team offsite'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "the day's event is listed")
    XCTAssertTrue(row.label.contains("all-day"), "all-day events read as all-day: \(row.label)")
    XCTAssertTrue(cell.isSelected)
  }

  /// Year: twelve mini months; tapping one opens it as Month.
  func testYearViewOpensAMonth() {
    modeButton("Year").tap()
    XCTAssertTrue(element("calendar.year.scroll").waitForExistence(timeout: 5))
    let year = cal.component(.year, from: .now)
    let january = element(String(format: "miniMonth.%04d-01", year))
    XCTAssertTrue(january.waitForExistence(timeout: 5), "January of this year is on screen")
    XCTAssertTrue(
      element(String(format: "miniMonth.%04d-12", year)).exists, "so is the rest of the year")
    XCTAssertTrue(waitForMonthLabel(.now), "the top bar names the device month")
    january.tap()
    let january1 = DateComponents(calendar: cal, year: year, month: 1, day: 1).date!
    XCTAssertTrue(
      waitForMonthLabel(.now), "tapping a mini month keeps the device month in the top bar")
    let landing = cal.isDate(january1, equalTo: .now, toGranularity: .month) ? Date.now : january1
    XCTAssertTrue(
      element(dayID(landing)).isSelected, "month headers retain their usual landing day")
  }

  /// Year marks holidays (a red day number, read out as the month's value) and explains its marks in a key.
  /// The built-in "Christmas, Easter and more" set is on in every region by default.
  func testYearMarksHolidaysAndHasAKey() throws {
    modeButton("Year").tap()
    XCTAssertTrue(element("calendar.year.scroll").waitForExistence(timeout: 5))
    let year = cal.component(.year, from: .now)
    let december = element(String(format: "miniMonth.%04d-12", year))
    XCTAssertTrue(december.waitForExistence(timeout: 5))
    let value = december.value as? String ?? ""
    XCTAssertTrue(value.contains("Christmas Day"), "December's holidays are read out: \(value)")
    let october = element(String(format: "miniMonth.%04d-10", year))
    XCTAssertTrue((october.value as? String ?? "").contains("Halloween"))
    let keys = app.buttons.matching(identifier: "calendar.year.key")
    XCTAssertTrue(keys.firstMatch.waitForExistence(timeout: 5), "an (i) opens the key")
    // Lazy year sections also expose offscreen keys; tap the one the user can reach.
    let key = try XCTUnwrap(
      keys.allElementsBoundByIndex.first(where: { $0.isHittable }),
      "the visible year has a hittable key button")
    key.tap()
    XCTAssertTrue(
      app.staticTexts["Unusually busy"].waitForExistence(timeout: 5),
      "the key says what the gray tint means")
    XCTAssertTrue(app.staticTexts["Holiday or festival"].exists)
    XCTAssertTrue(app.staticTexts["Multi-day event"].exists)
  }

  func testYearDayOpensMonthWithChosenDateAndItsItems() {
    app.terminate()
    app.launchArguments = TestData.fixtureArguments("year-day-month-agenda.json")
    app.launch()
    app.buttons["Calendar"].firstMatch.tap()
    // 400 days always lands outside the current month and year, regardless of the run date.
    for offset in [0, 400] {
      let chosen = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!
      modeButton("Year").tap()
      let cell = app.buttons["year.\(dayID(chosen))"]
      let scroll = element("calendar.year.scroll")
      XCTAssertTrue(scroll.waitForExistence(timeout: 5))
      for _ in 0..<12 {
        if cell.exists && cell.isFullyVisible(in: scroll.frame)
          && cell.frame.maxY < app.frame.maxY - 140 && cell.isHittable
        {
          break
        }
        let isAbove = cell.exists && cell.frame.minY < scroll.frame.minY
        let start = scroll.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: isAbove ? 0.4 : 0.7))
        let end = scroll.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: isAbove ? 0.7 : 0.4))
        start.press(
          forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      XCTAssertTrue(
        cell.isFullyVisible(in: scroll.frame) && cell.frame.maxY < app.frame.maxY - 140
          && cell.isHittable, "chosen day is visible in Year")
      cell.tap()
      XCTAssertTrue(waitForMonthLabel(.now))
      XCTAssertTrue(modeButton("Month").isSelected, "Year day taps stay in Calendar's Month view")
      let selected = app.buttons[dayID(chosen)]
      XCTAssertTrue(selected.waitForExistence(timeout: 5))
      let selection = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "isSelected == true"), object: selected)
      XCTAssertEqual(
        XCTWaiter().wait(for: [selection], timeout: 3), .completed, "the exact day is selected")
      let agenda = element("calendar.dayList")
      for name in ["Year event \(offset)", "Year reminder \(offset)"] {
        let row = agenda.descendants(matching: .any).matching(
          NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(
          row.waitForExistence(timeout: 5), "chosen day's item appears below the grid: \(name)")
      }
      let other = offset == 0 ? 400 : 0
      XCTAssertFalse(
        agenda.descendants(matching: .any).matching(
          NSPredicate(format: "label BEGINSWITH %@", "Year event \(other)")
        ).firstMatch.exists)
    }
    let chosen = cal.date(byAdding: .day, value: 400, to: cal.startOfDay(for: .now))!
    modeButton("Year").tap()
    let scroll = element("calendar.year.scroll")
    let january = element(String(format: "miniMonth.%04d-01", cal.component(.year, from: chosen)))
    let positioned = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        january.exists && january.isFullyVisible(in: scroll.frame) && january.isHittable
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter().wait(for: [positioned], timeout: 5), .completed,
      "reentering Year starts at the selected year without corrective scrolling")
    modeButton("Month").tap()
    XCTAssertTrue(element(dayID(chosen)).isSelected, "reentering Year preserves the chosen date")
  }

  func testYearReadsTripDaysButLeavesLocalBirthdayInMonth() {
    app.terminate()
    app.launchArguments = TestData.launchArguments
    app.launch()
    app.buttons["Calendar"].firstMatch.tap()
    modeButton("Year").tap()
    let tripStart = cal.date(byAdding: .day, value: 2, to: .now)!
    let tripLast = cal.date(byAdding: .day, value: 3, to: .now)!
    let birthday = cal.date(byAdding: .day, value: 4, to: .now)!
    for date in [tripStart, tripLast] {
      let cell = app.buttons["year.\(dayID(date))"]
      XCTAssertTrue(cell.waitForExistence(timeout: 5))
      XCTAssertTrue((cell.value as? String ?? "").contains("Team offsite"))
    }
    let birthdayCell = app.buttons["year.\(dayID(birthday))"]
    XCTAssertTrue(birthdayCell.waitForExistence(timeout: 5))
    XCTAssertFalse((birthdayCell.value as? String ?? "").contains("birthday"))
    birthdayCell.tap()
    XCTAssertTrue(waitForMonthLabel(.now))
    XCTAssertTrue(modeButton("Month").isSelected)
    let day = element(dayID(birthday))
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    XCTAssertTrue(day.isSelected)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", "Mia's birthday")
      ).firstMatch.waitForExistence(timeout: 5))
  }

  /// 2 Day keeps the time grid with all-day banners on top.
  func testTwoDayShowsAllDayBanner() {
    modeButton("TwoDay").tap()
    XCTAssertTrue(modeButton("TwoDay").waitForSelected())
    // "Team offsite" starts two days from now: one swipe brings it on screen.
    let grid = element("calendar.dayGrid")
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    grid.swipeLeft()
    let banner = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Team offsite'")
    ).firstMatch
    XCTAssertTrue(banner.waitForExistence(timeout: 5), "multi-day all-day event shows in the strip")
    XCTAssertTrue(banner.label.contains("all-day"))
  }

  /// Which calendars show is a Setting (sidebar > Settings > Calendars), not a button on the Calendar tab.
  func testCalendarsListLivesInSettings() throws {
    XCTAssertFalse(
      app.buttons["calendar.calendars"].exists, "no Calendars button on the Calendar tab")
    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let row = app.buttons["Calendars"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings has a Calendars row")
    row.tap()
    let chooser = app.navigationBars["Calendars"]
    let off = app.buttons["Turn On"]
    XCTAssertTrue(
      chooser.waitForExistence(timeout: 5) || off.waitForExistence(timeout: 2),
      "the Calendars list opens")
  }

  /// Hiding the calendar an event lives in removes it from the Calendar tab; showing it brings it back.
  func testCalendarsFilterHidesEvents() throws {
    // The new event starts at the next full hour; in the last hour of the day that is tomorrow.
    try XCTSkipIf(
      Calendar.current.component(.hour, from: .now) >= 23, "the default event time is tomorrow")
    // Needs Calendar sync on. Where the sidebar still has the "Show Apple Calendar" row, turn it on from there
    // (iOS asks for access the first time); otherwise rely on it having been enabled in Settings already.
    addUIInterruptionMonitor(withDescription: "Calendar access") { alert in
      for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists {
        alert.buttons[label].tap()
        return true
      }
      return false
    }
    // Turn Apple Calendar on in Settings (sidebar > Settings > Apple Calendar); iOS asks for access the first time.
    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let toggle = app.switches["Apple Calendar"]
    if toggle.waitForExistence(timeout: 5), (toggle.value as? String) != "1" {
      // the knob is at the right edge
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      for label in ["Allow Full Access", "Allow"] {
        let b = springboard.buttons[label]
        if b.waitForExistence(timeout: 3) {
          b.tap()
          break
        }
      }
      sleep(1)
    }
    if app.buttons["Done"].waitForExistence(timeout: 5) { app.buttons["Done"].tap() }
    app.closeSidebar()
    showMonth()

    // An all-day event sorts first in the day's list, so it is on screen without scrolling.
    let name = "Filter check \(Int(Date.now.timeIntervalSince1970) % 100000)"
    app.addNew("New event")
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.typeText(name)
    // Tap the switch itself (right end of the row), not the label.
    app.switches["All-day"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    app.buttons["Done"].tap()

    let row = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", name)
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 8), "the new all-day event is listed")
    // The row's label ends with "Calendar: <name>": that is the calendar to hide.
    let label = row.label
    let marker = "Calendar: "
    let calendarName = String(label[(label.range(of: marker)?.upperBound ?? label.startIndex)...])
    XCTAssertFalse(calendarName.isEmpty, "row names its calendar: \(label)")

    func toggleCalendar() {
      app.openSidebar()
      app.buttons["Settings"].firstMatch.tap()
      app.buttons["Calendars"].firstMatch.tap()
      XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 5))
      let cell = app.cells.containing(.staticText, identifier: calendarName).firstMatch
      XCTAssertTrue(cell.waitForExistence(timeout: 5), "Apple's list has \(calendarName)")
      cell.tap()
      app.navigationBars["Calendars"].buttons.firstMatch.tap()  // Done
      XCTAssertTrue(app.navigationBars["Calendars"].waitForNonExistence(timeout: 5))
      app.buttons["Done"].firstMatch.tap()  // leave Settings
      app.closeSidebar()
    }
    toggleCalendar()
    XCTAssertTrue(
      row.waitForNonExistence(timeout: 5), "hidden calendar: the event is gone from the list")
    toggleCalendar()
    XCTAssertTrue(row.waitForExistence(timeout: 5), "shown again: the event is back")

    // Clean up: delete the event (it also lives in the simulator's calendar).
    row.tap()
    let delete = app.buttons["Delete event"]
    if delete.waitForExistence(timeout: 5) { delete.tap() }
  }
}
