import XCTest
@testable import OneShared

/// The widgets' "next three things today": selection, order, tomorrow fallback, timeline dates, JSON round trip.
final class WidgetSnapshotTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    func date(_ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: min))!
    }
    /// Friday 2026-10-16, 09:41
    lazy var now = date(16, 9, 41)

    func item(_ title: String, _ start: Date, end: Date? = nil, allDay: Bool = false, kind: WidgetItem.Kind = .event) -> WidgetItem {
        WidgetItem(id: title, title: title, start: start, end: end, isAllDay: allDay, kind: kind)
    }

    func testNextThreeMergedAndSortedByTime() {
        let items = [
            item("Dentist", date(16, 15), end: date(16, 16)),
            item("Call Alex", date(16, 11), kind: .reminder),
            item("Gym", date(16, 18), kind: .alarm),
            item("Standup", date(16, 10), end: date(16, 10, 15)),
            item("Late", date(16, 21), kind: .reminder),
        ]
        let next = NextItems.select(from: items, now: now, calendar: cal)
        XCTAssertEqual(next.today.map(\.title), ["Standup", "Call Alex", "Dentist"])
        XCTAssertEqual(next.remainingToday, 5)
        XCTAssertNil(next.tomorrow)
    }

    func testPastItemsDropOutButEventsInProgressStay() {
        let items = [
            item("Breakfast reminder", date(16, 8), kind: .reminder),
            item("Wake up", date(16, 7), kind: .alarm),
            item("Long meeting", date(16, 9), end: date(16, 10)),
            item("Finished meeting", date(16, 8), end: date(16, 9)),
            item("Lunch", date(16, 12)),
        ]
        let next = NextItems.select(from: items, now: now, calendar: cal)
        XCTAssertEqual(next.today.map(\.title), ["Long meeting", "Lunch"])
        XCTAssertEqual(next.remainingToday, 2)
    }

    /// The timeline redraws exactly at each start and end; those entries must advance the list.
    func testItemsLeaveAtTheirTimelineEntry() {
        let items = [item("Call Alex", date(16, 11), kind: .reminder), item("Dentist", date(16, 15), end: date(16, 16))]
        XCTAssertEqual(NextItems.select(from: items, now: date(16, 11), calendar: cal).today.map(\.title), ["Dentist"])
        XCTAssertEqual(NextItems.select(from: items, now: date(16, 15), calendar: cal).today.map(\.title), ["Dentist"])
        XCTAssertTrue(NextItems.select(from: items, now: date(16, 16), calendar: cal).today.isEmpty)
    }

    func testAllDayFirstAndStaysAllDay() {
        let items = [
            item("Lunch", date(16, 12)),
            item("Holiday", date(16), allDay: true),
        ]
        let late = date(16, 23, 30)
        XCTAssertEqual(NextItems.select(from: items, now: now, calendar: cal).today.map(\.title), ["Holiday", "Lunch"])
        XCTAssertEqual(NextItems.select(from: items, now: late, calendar: cal).today.map(\.title), ["Holiday"])
    }

    func testOtherDaysAreNotToday() {
        let items = [item("Yesterday", date(15, 15)), item("Tomorrow", date(17, 9))]
        let next = NextItems.select(from: items, now: now, calendar: cal)
        XCTAssertTrue(next.today.isEmpty)
        XCTAssertEqual(next.remainingToday, 0)
        XCTAssertEqual(next.tomorrow?.title, "Tomorrow")
    }

    func testTomorrowOnlyWhenNothingLeftToday() {
        let items = [item("Tonight", date(16, 20), kind: .reminder), item("Tomorrow", date(17, 9))]
        XCTAssertNil(NextItems.select(from: items, now: now, calendar: cal).tomorrow)
        let next = NextItems.select(from: items, now: date(16, 20, 30), calendar: cal)
        XCTAssertTrue(next.today.isEmpty)
        XCTAssertEqual(next.tomorrow?.title, "Tomorrow")
    }

    func testTomorrowPicksFirstInAppleOrder() {
        let items = [item("Early", date(17, 7)), item("Trip", date(17), allDay: true), item("Later", date(17, 11))]
        XCTAssertEqual(NextItems.select(from: items, now: date(16, 22), calendar: cal).tomorrow?.title, "Trip")
    }

    func testNothingAtAll() {
        let next = NextItems.select(from: [], now: now, calendar: cal)
        XCTAssertEqual(next, NextUp(today: [], remainingToday: 0, tomorrow: nil))
    }

    func testLimit() {
        let items = (10...15).map { item("T\($0)", date(16, $0)) }
        let next = NextItems.select(from: items, now: now, calendar: cal, limit: 1)
        XCTAssertEqual(next.today.map(\.title), ["T10"])
        XCTAssertEqual(next.remainingToday, 6)
    }

    func testTimelineDatesAdvanceAtEachStartAndEndUntilMidnight() {
        let items = [
            item("Standup", date(16, 10), end: date(16, 10, 15)),
            item("Past", date(16, 8), kind: .reminder),
            item("Holiday", date(16), allDay: true),
            item("Tomorrow", date(17, 9)),
        ]
        XCTAssertEqual(NextItems.timelineDates(for: items, now: now, calendar: cal),
                       [now, date(16, 10), date(16, 10, 15), date(17)])
    }

    func testDeepLinks() {
        let url = WidgetLink.url(day: date(17, 9), calendar: cal)
        XCTAssertEqual(url.absoluteString, "today://today?day=2026-10-17")
        XCTAssertEqual(WidgetLink.day(from: url, now: now, calendar: cal), date(17))
        XCTAssertEqual(WidgetLink.day(from: WidgetLink.url(), now: now, calendar: cal), date(16))
        XCTAssertEqual(WidgetLink.day(from: URL(string: "today://today?day=bad")!, now: now, calendar: cal), date(16))
        XCTAssertNil(WidgetLink.day(from: URL(string: "https://example.com")!, now: now, calendar: cal))
    }

    func testSnapshotRoundTrip() throws {
        let snap = WidgetSnapshot(generatedAt: date(16, 9), items: [
            item("Dentist", date(16, 15), end: date(16, 16)),
            item("Holiday", date(16), allDay: true),
            item("Gym", date(16, 18), kind: .alarm),
        ])
        XCTAssertEqual(WidgetSnapshot.decode(try snap.encoded()), snap)
        XCTAssertNil(WidgetSnapshot.decode(Data("nope".utf8)))
    }
}
