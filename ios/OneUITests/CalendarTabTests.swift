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

    private func monthName(_ date: Date) -> String { date.formatted(.dateTime.month(.wide)) }

    private func dayID(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "day.%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Month is the default view: big month title, weekday letters, grid, and today's events below.
    func testMonthIsTheDefaultAndListsTodaysEvents() {
        let title = element("calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, monthName(.now))
        XCTAssertTrue(element(dayID(.now)).exists, "today is in the grid")
        let today = element(dayID(.now))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: today)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 3), .completed, "and selected: \(today.debugDescription)")
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Product sync'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "today's events are listed under the grid")
        XCTAssertTrue(app.segmentedControls.buttons["Week"].exists && app.segmentedControls.buttons["Year"].exists
                      && app.segmentedControls.buttons["Day"].exists, "Day / Week / Month / Year switcher")
    }

    /// Swipe the grid sideways to change month; Today brings you back.
    func testMonthPagingAndTodayButton() {
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
        app.buttons["calendar.today"].tap()
        let today = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", monthName(.now)), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [today], timeout: 5), .completed, "Today jumps back to this month")
    }

    /// Tapping a day selects it and lists its events below the grid, all-day first.
    func testSelectingADayListsItsEvents() throws {
        let twoDays = cal.date(byAdding: .day, value: 2, to: .now)!
        try XCTSkipUnless(cal.isDate(twoDays, equalTo: .now, toGranularity: .month), "needs the sample events in this month's grid")
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
        app.segmentedControls.buttons["Year"].tap()
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

    /// The year button in the top row goes to the Year view, like Apple's back button.
    func testYearButtonGoesToYear() {
        app.buttons["calendar.year"].tap()
        XCTAssertTrue(element("calendar.year.scroll").waitForExistence(timeout: 5))
    }

    /// Day is the Today tab: the switcher's Day segment opens the selected day there.
    func testDaySegmentOpensToday() {
        app.segmentedControls.buttons["Day"].tap()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5), "Today's schedule is showing")
    }

    /// Week keeps the time grid with all-day banners on top.
    func testWeekShowsAllDayBanner() {
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertTrue(element("calendar.weekTitle").waitForExistence(timeout: 5))
        // "Team offsite" is two days from now: this week or, near the weekend, the next one.
        let banner = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Team offsite'")).firstMatch
        if !banner.waitForExistence(timeout: 3) {
            app.swipeLeft()
        }
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "multi-day all-day event shows in the strip")
        XCTAssertTrue(banner.label.contains("all-day"))
    }

    /// The Calendars button opens Apple's calendar list when Calendar access is on, otherwise an explanation.
    func testCalendarsButtonOpensTheList() {
        app.buttons["calendar.calendars"].tap()
        let chooser = app.navigationBars["Calendars"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5), "Calendars sheet opens")
    }

    /// Hiding the calendar an event lives in removes it from the Calendar tab; showing it brings it back.
    func testCalendarsFilterHidesEvents() throws {
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
        app.buttons["Open sidebar"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Apple Calendar"]
        if toggle.waitForExistence(timeout: 5), (toggle.value as? String) != "1" {
            toggle.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow Full Access", "Allow"] {
                let b = springboard.buttons[label]
                if b.waitForExistence(timeout: 3) { b.tap(); break }
            }
            sleep(1)
        }
        app.buttons["Done"].tap()
        app.buttons["calendar.calendars"].tap()
        try XCTSkipIf(app.buttons["Turn On"].waitForExistence(timeout: 3), "Calendar sync is off in this simulator")
        XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 5))
        app.navigationBars["Calendars"].buttons.firstMatch.tap()   // Done
        XCTAssertTrue(app.navigationBars["Calendars"].waitForNonExistence(timeout: 5))

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
            app.buttons["calendar.calendars"].tap()
            XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 5))
            let cell = app.cells.containing(.staticText, identifier: calendarName).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "Apple's list has \(calendarName)")
            cell.tap()
            app.navigationBars["Calendars"].buttons.firstMatch.tap()   // Done
            XCTAssertTrue(app.navigationBars["Calendars"].waitForNonExistence(timeout: 5))
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
