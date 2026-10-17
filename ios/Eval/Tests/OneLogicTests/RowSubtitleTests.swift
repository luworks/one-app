import XCTest
@testable import OneLogic

final class RowSubtitleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    /// `offset` days from the real today (DayLabel says "Today" / "Tomorrow" by the real clock).
    private func date(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let base = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    private var today: Date { date(0) }

    private func line(_ i: RowSubtitle.Input, day: Date? = nil) -> String? {
        RowSubtitle.line(i, day: day ?? today, calendar: cal)
    }

    func testPlainReminderInDefaultListHasNoSubtitle() {
        XCTAssertNil(line(.init(listName: "")))
        XCTAssertNil(line(.init(listName: "Reminders")))
    }

    func testDueTodayIsLeftOutBecauseThePositionSaysIt() {
        // Untimed, due today: sits on Today, nothing to add.
        XCTAssertNil(line(.init(due: today, dueHasTime: false)))
        // Timed, and the time column already shows that time.
        XCTAssertNil(line(.init(due: date(0, 11, 30), dueHasTime: true, shownTime: date(0, 11, 30))))
    }

    func testDueTodayAtADifferentTimeThanTheRowIsKept() {
        let s = line(.init(due: date(0, 17), dueHasTime: true, shownTime: date(0, 9)))
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.hasPrefix("Due "))
        XCTAssertFalse(s!.contains("Today"))
    }

    func testSuggestedAndNonDefaultList() {
        // Buy milk: due today (implied), suggested time, Home list, #errands tag is never shown.
        XCTAssertEqual(line(.init(isSuggested: true, due: today, listName: "Home")), "Suggested · Home")
    }

    func testDueTomorrowKeepsItsDayAndTime() {
        let s = line(.init(due: date(1, 17), dueHasTime: true, shownTime: date(0, 13, 30), stepsDone: 1, stepsTotal: 3, listName: "Work"))
        XCTAssertEqual(s, "Due Tomorrow " + date(1, 17).formatted(date: .omitted, time: .shortened) + " · 1/3",
                       "two facts at most: the third (list) is dropped")
    }

    func testOverdueKeepsItsDueDay() {
        let s = line(.init(due: date(-1, 17), dueHasTime: true))
        XCTAssertEqual(s, "Due Yesterday " + date(-1, 17).formatted(date: .omitted, time: .shortened))
    }

    func testRowOnTomorrowDoesNotRepeatTomorrow() {
        XCTAssertNil(line(.init(due: date(1)), day: date(1)))
    }

    func testNeverMoreThanTwoFactsAndOrderIsStable() {
        let all = RowSubtitle.Input(isSuggested: true, due: date(3), planned: date(0, 9), repeats: true,
                                    stepsDone: 0, stepsTotal: 2, listName: "Home")
        let facts = RowSubtitle.facts(all, day: today, calendar: cal)
        XCTAssertEqual(facts.count, 2)
        XCTAssertEqual(facts.first, "Suggested")
        XCTAssertTrue(facts[1].hasPrefix("Due "))
    }

    func testRepeatIconCountsAsAFact() {
        XCTAssertEqual(line(.init(due: today, repeats: true, listName: "Home")), "↻ · Home")
        XCTAssertEqual(line(.init(repeats: true, stepsDone: 1, stepsTotal: 2, listName: "Home")), "↻ · 1/2")
    }

    func testListNameShownWithoutItsSortingNumber() {
        XCTAssertEqual(line(.init(listName: "01 工作")), "工作")
    }

    func testDefaultListDetection() {
        XCTAssertTrue(RowSubtitle.isDefaultList(""))
        XCTAssertTrue(RowSubtitle.isDefaultList(" Reminders "))
        XCTAssertFalse(RowSubtitle.isDefaultList("Home"))
    }
}
