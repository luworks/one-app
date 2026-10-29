import XCTest

@testable import TodayCore

/// The Year view's per-month values: grid placement, holidays, busy days, bands and VoiceOver text.
final class YearLayoutTests: XCTestCase {
  private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()

  private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
  }

  private func months(
    _ entries: [YearEntry] = [], sets: Set<HolidaySet> = [], today: Date? = nil,
    calendar: Calendar? = nil
  ) -> [YearMonth] {
    YearLayout.months(
      yearStart: date(2026, 1, 1), entries: entries, holidaySets: sets,
      today: today ?? date(2030, 1, 1), calendar: calendar ?? cal)
  }

  private func timed(_ id: String, _ m: Int, _ d: Int, repeats: Bool = false) -> YearEntry {
    YearEntry(
      id: id, title: id, start: date(2026, m, d, 10), end: date(2026, m, d, 11), isAllDay: false,
      repeats: repeats)
  }

  private func allDay(
    _ title: String, from start: Date, to end: Date, background: Bool = false,
    holiday: Bool = false, tint: Int = 0
  ) -> YearEntry {
    YearEntry(
      id: title, title: title, start: start, end: end, isAllDay: true, isBackground: background,
      isHoliday: holiday, tint: tint)
  }

  func testMonthsSitInTheWeekGridOfTheChosenFirstWeekday() {
    let year = months()
    XCTAssertEqual(year.count, 12)
    XCTAssertEqual(year.map(\.days.count), [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
    XCTAssertEqual(year[0].start, date(2026, 1, 1))
    XCTAssertEqual(year[0].lead, 4, "January 1, 2026 is a Thursday")
    XCTAssertEqual(year[0].weekCount, 5)
    XCTAssertEqual(year[1].lead, 0, "February 1, 2026 is a Sunday")
    XCTAssertEqual(year[1].weekCount, 4)
    XCTAssertNil(year[0].day(week: 0, column: 3))
    XCTAssertEqual(year[0].day(week: 0, column: 4), 0)
    XCTAssertEqual(year[0].day(week: 4, column: 6), 30)
    XCTAssertNil(year[0].day(week: 5, column: 0))
    XCTAssertTrue(year[0].cell(of: 30) == (4, 6))

    var monday = cal
    monday.firstWeekday = 2
    XCTAssertEqual(months(calendar: monday)[0].lead, 3)
    XCTAssertEqual(months(calendar: monday)[1].lead, 6)
  }

  func testBlankYearHasTheSameGridAndToday() {
    let today = date(2026, 10, 12, 9)
    let blank = YearLayout.blank(yearStart: date(2026, 1, 1), today: today, calendar: cal)
    let full = months(today: today)
    XCTAssertEqual(blank.map(\.start), full.map(\.start))
    XCTAssertEqual(blank.map(\.lead), full.map(\.lead))
    XCTAssertEqual(blank.map(\.days.count), full.map(\.days.count))
    XCTAssertEqual(blank.map(\.today), full.map(\.today))
    XCTAssertTrue(blank.allSatisfy { $0.bands.isEmpty && $0.summary.isEmpty })
  }

  func testTodayIsMarkedOnlyInItsMonth() {
    let year = months(today: date(2026, 10, 12, 9))
    XCTAssertEqual(year[9].today, 11)
    XCTAssertEqual(year.compactMap(\.today).count, 1)
    XCTAssertTrue(months(today: date(2025, 12, 31)).allSatisfy { $0.today == nil })
  }

  func testHolidaysFromRulesAndHolidayCalendarsWithoutRepeats() {
    let year = months(
      [
        allDay(
          "Thanksgiving", from: date(2026, 11, 26), to: date(2026, 11, 27), background: true,
          holiday: true),
        allDay(
          "Christmas Eve", from: date(2026, 12, 24), to: date(2026, 12, 25), background: true,
          holiday: true),
        allDay(
          "Holiday week", from: date(2026, 12, 28), to: date(2026, 12, 31), background: true,
          holiday: true),
      ], sets: [.unitedStates])
    XCTAssertEqual(year[10].days[25], YearDay(isHoliday: true, notes: ["Thanksgiving"]))
    XCTAssertEqual(year[11].days[23].notes, ["Christmas Eve"])
    XCTAssertTrue(year[11].days[24].isHoliday, "Christmas Day comes from the rules")
    XCTAssertFalse(
      year[11].days[28].isHoliday, "a multi-day holiday-calendar event is not a holiday")
    XCTAssertTrue(year[11].bands.isEmpty, "background calendars draw no bands")
    XCTAssertEqual(year[10].summary, "Veterans Day; Thanksgiving")
    XCTAssertTrue(year[11].summary.contains("Christmas Eve; Christmas Day"))
  }

  func testMultiDayEventsBecomeBandsSplitAtWeeksAndMonths() {
    let year = months([
      allDay("Ski trip", from: date(2026, 3, 30), to: date(2026, 4, 3), tint: 2),
      allDay("Offsite", from: date(2026, 3, 6), to: date(2026, 3, 10), tint: 1),
    ])
    // March 1, 2026 is a Sunday (lead 0); April 1 is a Wednesday (lead 3).
    XCTAssertEqual(
      year[2].bands,
      [
        YearBand(week: 4, firstColumn: 1, lastColumn: 2, tint: 2),
        YearBand(week: 1, firstColumn: 0, lastColumn: 1, tint: 1),
        YearBand(week: 0, firstColumn: 5, lastColumn: 6, tint: 1),
      ], "later events are drawn first so the earliest ends on top")
    XCTAssertEqual(year[3].bands, [YearBand(week: 0, firstColumn: 3, lastColumn: 4, tint: 2)])
    XCTAssertEqual(year[2].days[6].notes, ["Offsite"])
    XCTAssertEqual(year[2].days[9].notes, [], "the end is exclusive")
    XCTAssertEqual(year[3].days[1].notes, ["Ski trip"])
    XCTAssertEqual(year[2].summary, "Offsite; Ski trip")
    XCTAssertEqual(year[3].summary, "Ski trip")
    XCTAssertTrue(year[4].bands.isEmpty)
  }

  func testBusyDaysShowUnlessABandCoversThem() {
    var entries = (1...10).map { timed("one-off \($0)", 6, $0) }
    entries += (1...4).map { timed("meeting \($0)", 5, 5) }
    entries += (1...20).map { timed("standup \($0)", 5, 6, repeats: true) }
    let year = months(entries)
    XCTAssertEqual(year[4].days[4], YearDay(showsBusy: true, notes: ["Unusually busy"]))
    XCTAssertFalse(year[4].days[5].showsBusy, "repeating items are not load")
    XCTAssertEqual(year[4].summary, "1 busy day")
    XCTAssertEqual(year[5].summary, "")

    let covered = months(entries + [allDay("Trip", from: date(2026, 5, 4), to: date(2026, 5, 7))])
    XCTAssertEqual(covered[4].days[4], YearDay(notes: ["Trip"]))
    XCTAssertEqual(covered[4].summary, "1 busy day; Trip", "the month still counts it")
  }

  func testSpansOutsideTheYearAreClipped() {
    let year = months([
      allDay("New Year trip", from: date(2025, 12, 30), to: date(2026, 1, 2)),
      allDay("Last year", from: date(2025, 12, 1), to: date(2025, 12, 3)),
    ])
    XCTAssertEqual(year[0].bands, [YearBand(week: 0, firstColumn: 4, lastColumn: 4, tint: 0)])
    XCTAssertEqual(year[0].days[0].notes, ["New Year trip"])
    XCTAssertEqual(year[0].summary, "New Year trip")
  }
}
