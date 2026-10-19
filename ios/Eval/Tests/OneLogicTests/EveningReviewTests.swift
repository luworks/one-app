import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

final class EveningReviewTests: XCTestCase {
  private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return c
  }()

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  // MARK: When it shows

  func testShowsFromSixInTheEvening() {
    XCTAssertFalse(EveningReview.shows(now: date(16, 17, 59), calendar: cal))
    XCTAssertTrue(EveningReview.shows(now: date(16, 18), calendar: cal))
    XCTAssertTrue(EveningReview.shows(now: date(16, 23, 30), calendar: cal))
  }

  // MARK: Done vs planned

  func testSummaryCountsDoneTodayAndWhatIsLeft() {
    let now = date(16, 19, 30)
    let items = [
      EveningReview.Item(id: 0, isDone: true, doneAt: date(16, 10)),  // done today
      EveningReview.Item(id: 1, isDone: true, doneAt: date(15, 10)),  // done yesterday: not today's
      EveningReview.Item(id: 2, plannedStart: date(16, 17)),  // planned today, open
      EveningReview.Item(id: 3, due: cal.startOfDay(for: date(16, 0))),  // due today, no plan
      // planned tomorrow
      EveningReview.Item(id: 4, plannedStart: date(17, 9), due: cal.startOfDay(for: date(16, 0))),
      EveningReview.Item(id: 5, due: date(14, 17)),  // overdue: stays in its line
      EveningReview.Item(id: 6),  // no date
      EveningReview.Item(id: 7, plannedStart: date(16, 21)),  // later tonight, still left
    ]
    let s = EveningReview.summary(items, now: now, calendar: cal)
    XCTAssertEqual(s.done, [0])
    XCTAssertEqual(s.left, [2, 3, 7])
    XCTAssertEqual(s.planned, 4)
    XCTAssertEqual(EveningReview.headline(s), "1 of 4 done")
    XCTAssertEqual(EveningReview.headline(.init(done: [], left: [])), "Nothing was planned today")
  }

  // MARK: Choices

  func testChoicesPerRow() {
    XCTAssertEqual(
      EveningReview.choices(for: .init(id: 0, plannedStart: date(16, 17))),
      [.keep, .tomorrow, .later, .drop])
    XCTAssertEqual(
      EveningReview.choices(for: .init(id: 0, due: date(16, 0))), [.keep, .tomorrow, .drop],
      "Later clears a plan, so a reminder with only a deadline doesn't offer it")
    XCTAssertEqual(
      EveningReview.choices(for: .init(id: 0, plannedStart: date(16, 17), repeats: true)),
      [.keep, .tomorrow, .later],
      "dropping a repeating reminder would lose the series")
  }

  func testTomorrowKeepsTheTimeOfDay() {
    let now = date(16, 19, 30)
    XCTAssertEqual(
      EveningReview.newPlannedStart(
        .init(id: 0, plannedStart: date(16, 17, 15)), .tomorrow, now: now, calendar: cal),
      date(17, 17, 15))
    XCTAssertEqual(
      EveningReview.newPlannedStart(
        .init(id: 0, due: date(16, 11, 30)), .tomorrow, now: now, calendar: cal), date(17, 11, 30),
      "a timed deadline lends its time")
    XCTAssertEqual(
      EveningReview.newPlannedStart(
        .init(id: 0, due: cal.startOfDay(for: date(16, 0))), .tomorrow, now: now, calendar: cal),
      date(17, 9),
      "no time: 09:00")
  }

  func testLaterKeepAndDrop() {
    let now = date(16, 19, 30)
    let item = EveningReview.Item(id: 0, plannedStart: date(16, 17))
    XCTAssertNil(EveningReview.newPlannedStart(item, .later, now: now, calendar: cal))
    XCTAssertEqual(
      EveningReview.newPlannedStart(item, .keep, now: now, calendar: cal), date(16, 17))
    XCTAssertEqual(
      EveningReview.newPlannedStart(item, .drop, now: now, calendar: cal), date(16, 17))
  }

  /// Principle 3: moving work never moves the deadline. The note tells the user the deadline stays.
  func testNoChoiceTouchesTheDeadline() {
    let now = date(16, 19, 30)
    let due = date(16, 17)
    let item = EveningReview.Item(id: 0, plannedStart: date(16, 15), due: due)
    for choice in EveningReview.Choice.allCases {
      _ = EveningReview.newPlannedStart(item, choice, now: now, calendar: cal)
      XCTAssertEqual(item.due, due)
    }
    XCTAssertEqual(
      EveningReview.note(for: item, .tomorrow, now: now, calendar: cal), "Still due today")
    XCTAssertEqual(
      EveningReview.note(for: item, .later, now: now, calendar: cal), "Still due today")
    XCTAssertNil(EveningReview.note(for: item, .keep, now: now, calendar: cal))
    XCTAssertNil(
      EveningReview.note(
        for: .init(id: 1, plannedStart: date(16, 15), due: date(18, 9)), .tomorrow, now: now,
        calendar: cal))
  }
}
