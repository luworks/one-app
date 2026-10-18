import XCTest

/// The Calendar tab (modeled on Apple Calendar): Month grid with the day's list, paging, Year, Week, and the Calendars filter.
/// Launched with -uiTesting: a fresh in-memory store with sample data (events today and tomorrow, "Team offsite" in two days).
final class CalendarTabTests: XCTestCase {
    var app: XCUIApplication!
    private let cal = Calendar.current

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingCalendarSync"]
        app.launch()
        app.buttons["Calendar"].firstMatch.tap()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// The Calendar tab opens on the next 3 days; the Month tests switch to Month first.
    private func showMonth() { modeButton("Month").tap() }

    /// The Week / Month / Year pills (buttons, not a segmented control).
    private func modeButton(_ title: String) -> XCUIElement { app.buttons["calendar.mode.\(title.lowercased())"] }

    private func monthName(_ date: Date) -> String { date.formatted(.dateTime.month(.wide)) }

    private func dayID(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "day.%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The default view is Week: one switcher row (Week / Month / Year), no Day segment, no Today or Calendars buttons.
    func testWeekIsTheDefault() {
        XCTAssertTrue(modeButton("Week").waitForExistence(timeout: 5))
        let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.mode.'"))
        XCTAssertEqual(pills.allElementsBoundByIndex.map(\.label), ["Week", "Month", "Year"],
                       "one switcher: Week / Month / Year (Day is the Today tab)")
        XCTAssertFalse(app.segmentedControls.buttons["Month"].exists, "pills, not a segmented control")
        XCTAssertTrue(modeButton("Week").isSelected, "Week is selected when the tab opens")
        XCTAssertFalse(modeButton("Month").isSelected)
        XCTAssertTrue(element("calendar.weekTitle").waitForExistence(timeout: 5), "a time grid with a month title")
        XCTAssertFalse(app.buttons["calendar.today"].exists || app.buttons["calendar.calendars"].exists || app.buttons["calendar.year"].exists)
    }

    /// Month: big month title, weekday letters, grid, and today's events below.
    func testMonthListsTodaysEvents() {
        showMonth()
        let title = element("calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, monthName(.now))
        XCTAssertTrue(element(dayID(.now)).exists, "today is in the grid")
        let today = element(dayID(.now))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: today)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 3), .completed, "and selected: \(today.debugDescription)")
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Product sync'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "today's events are listed under the grid")
    }

    /// Swipe the grid sideways to change month (no Today button appears).
    func testMonthPaging() {
        showMonth()
        let title = element("calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let next = cal.date(byAdding: .month, value: 1, to: .now)!
        element("calendar.monthPager").swipeLeft()
        XCTAssertTrue(NSPredicate(format: "label == %@", monthName(next)).evaluate(with: title) ||
                      title.waitForExistence(timeout: 2), "title follows the page")
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", monthName(next)), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "paged to next month")
        element("calendar.monthPager").swipeRight()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", monthName(.now)), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed, "and back")
        element("calendar.monthPager").swipeRight()
        let prev = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@",
                                                                    monthName(cal.date(byAdding: .month, value: -1, to: .now)!)), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [prev], timeout: 5), .completed, "previous month")
        XCTAssertFalse(app.buttons["calendar.today"].exists, "paging does not add a Today button")
    }

    /// Tapping a day selects it and lists its events below the grid, all-day first.
    func testSelectingADayListsItsEvents() throws {
        let twoDays = cal.date(byAdding: .day, value: 2, to: .now)!
        try XCTSkipUnless(cal.isDate(twoDays, equalTo: .now, toGranularity: .month), "needs the sample events in this month's grid")
        showMonth()
        let cell = element(dayID(twoDays))
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Team offsite'")).firstMatch
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
        XCTAssertTrue(element(String(format: "miniMonth.%04d-12", year)).exists, "so is the rest of the year")
        january.tap()
        let title = element("calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let january1 = DateComponents(calendar: cal, year: year, month: 1, day: 1).date!
        XCTAssertEqual(title.label, monthName(january1), "tapping a mini month opens it")
    }

    /// Year marks holidays (a red day number, read out as the month's value) and explains its marks in a key.
    /// The built-in "Christmas, Easter and more" set is on in every region by default.
    func testYearMarksHolidaysAndHasAKey() {
        modeButton("Year").tap()
        XCTAssertTrue(element("calendar.year.scroll").waitForExistence(timeout: 5))
        let year = cal.component(.year, from: .now)
        let december = element(String(format: "miniMonth.%04d-12", year))
        XCTAssertTrue(december.waitForExistence(timeout: 5))
        let value = december.value as? String ?? ""
        XCTAssertTrue(value.contains("Christmas Day"), "December's holidays are read out: \(value)")
        let october = element(String(format: "miniMonth.%04d-10", year))
        XCTAssertTrue((october.value as? String ?? "").contains("Halloween"))
        let key = element("calendar.year.key").firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5), "an (i) opens the key")
        key.tap()
        XCTAssertTrue(app.staticTexts["Unusually busy"].waitForExistence(timeout: 5), "the key says what the gray tint means")
        XCTAssertTrue(app.staticTexts["Holiday or festival"].exists)
    }

    /// Week keeps the time grid with all-day banners on top.
    func testWeekShowsAllDayBanner() {
        modeButton("Week").tap()
        XCTAssertTrue(element("calendar.weekTitle").waitForExistence(timeout: 5))
        // "Team offsite" is two days from now: this week or, near the weekend, the next one.
        let banner = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Team offsite'")).firstMatch
        if !banner.waitForExistence(timeout: 3) {
            app.swipeLeft()
        }
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "multi-day all-day event shows in the strip")
        XCTAssertTrue(banner.label.contains("all-day"))
    }

    /// Which calendars show is a Setting (sidebar > Settings > Calendars), not a button on the Calendar tab.
    func testCalendarsListLivesInSettings() throws {
        XCTAssertFalse(app.buttons["calendar.calendars"].exists, "no Calendars button on the Calendar tab")
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let row = app.buttons["Calendars"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings has a Calendars row")
        row.tap()
        let chooser = app.navigationBars["Calendars"]
        let off = app.buttons["Turn On"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5) || off.waitForExistence(timeout: 2), "the Calendars list opens")
    }

    /// Hiding the calendar an event lives in removes it from the Calendar tab; showing it brings it back.
    func testCalendarsFilterHidesEvents() throws {
        // The new event starts at the next full hour; in the last hour of the day that is tomorrow.
        try XCTSkipIf(Calendar.current.component(.hour, from: .now) >= 23, "the default event time is tomorrow")
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
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()   // the knob is at the right edge
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow Full Access", "Allow"] {
                let b = springboard.buttons[label]
                if b.waitForExistence(timeout: 3) { b.tap(); break }
            }
            sleep(1)
        }
        if app.buttons["Done"].waitForExistence(timeout: 5) { app.buttons["Done"].tap() }
        app.closeSidebar()
        showMonth()

        // An all-day event sorts first in the day's list, so it is on screen without scrolling.
        let name = "Filter check \(Int(Date.now.timeIntervalSince1970) % 100000)"
        app.buttons["New"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText(name)
        // Tap the switch itself (right end of the row), not the label.
        app.switches["All-day"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["Done"].tap()

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
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
            app.navigationBars["Calendars"].buttons.firstMatch.tap()   // Done
            XCTAssertTrue(app.navigationBars["Calendars"].waitForNonExistence(timeout: 5))
            app.buttons["Done"].firstMatch.tap()                        // leave Settings
            app.closeSidebar()
        }
        toggleCalendar()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "hidden calendar: the event is gone from the list")
        toggleCalendar()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "shown again: the event is back")

        // Clean up: delete the event (it also lives in the simulator's calendar).
        row.tap()
        let delete = app.buttons["Delete event"]
        if delete.waitForExistence(timeout: 5) { delete.tap() }
    }
}
