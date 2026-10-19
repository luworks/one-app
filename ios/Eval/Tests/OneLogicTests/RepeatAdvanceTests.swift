import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// A repeating reminder rolls to its next occurrence: the finished occurrence's plan must not stay on today.
final class RepeatAdvanceTests: XCTestCase {
  var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return c
  }()

  func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
  }

  /// Thu Oct 15 2026, 08:00.
  var now: Date { date(2026, 10, 15, 8) }

  func plan(
    _ planned: Date?, from oldDue: Date?, to newDue: Date?, repeats: Bool = true,
    isDone: Bool = false
  ) -> Date? {
    RepeatAdvance.plannedStart(
      planned, dueMovedFrom: oldDue, to: newDue, repeats: repeats, isDone: isDone, now: now,
      calendar: cal)
  }

  func testPlanToday_isClearedForEveryRule() {
    let planned = date(2026, 10, 15, 9)
    let due = date(2026, 10, 15, 7)
    for rule in RepeatRule.allCases {
      XCTAssertNil(plan(planned, from: due, to: rule.next(after: due, calendar: cal)), "\(rule)")
    }
    // Every 2 weeks (the user's case: Apple's rule, no RepeatRule of its own).
    XCTAssertNil(plan(planned, from: due, to: date(2026, 10, 29, 7)))
  }

  func testPlanToday_whileOverdueAndThePlanIsLaterThanTheOldDue() {
    // Due Oct 14 07:00 (overdue), planned today 09:00, completed: next due Oct 28 07:00. The plan goes.
    XCTAssertNil(
      plan(date(2026, 10, 15, 9), from: date(2026, 10, 14, 7), to: date(2026, 10, 28, 7)))
  }

  func testPlanTomorrow_ofTheFinishedOccurrence_isCleared() {
    // Weekly, due today, planned tomorrow: tomorrow is nearer the finished due (1 day) than the next (6 days).
    XCTAssertNil(
      plan(date(2026, 10, 16, 9), from: date(2026, 10, 15, 7), to: date(2026, 10, 22, 7)))
    // Every 2 weeks.
    XCTAssertNil(
      plan(date(2026, 10, 16, 9), from: date(2026, 10, 15, 7), to: date(2026, 10, 29, 7)))
  }

  func testPlanTomorrow_ofTheNextOccurrence_isKept() {
    // Daily, due today 07:00, planned tomorrow 09:00: nearer the next occurrence (tomorrow 07:00).
    let planned = date(2026, 10, 16, 9)
    XCTAssertEqual(plan(planned, from: date(2026, 10, 15, 7), to: date(2026, 10, 16, 7)), planned)
    // Monthly, planned the day before the next due date.
    let beforeNext = date(2026, 11, 14, 9)
    XCTAssertEqual(
      plan(beforeNext, from: date(2026, 10, 15, 7), to: date(2026, 11, 15, 7)), beforeNext)
  }

  func testNoPlan_staysNil() {
    XCTAssertNil(plan(nil, from: date(2026, 10, 15, 7), to: date(2026, 10, 22, 7)))
  }

  func testCompletedTwice_staysUnplanned() {
    var planned: Date? = date(2026, 10, 15, 9)
    var due = date(2026, 10, 15, 7)
    for _ in 0..<2 {
      let next = RepeatRule.weekly.next(after: due, calendar: cal)
      planned = plan(planned, from: due, to: next)
      due = next
    }
    XCTAssertNil(planned)
    XCTAssertEqual(due, date(2026, 10, 29, 7))
  }

  func testOnlyARepeatingOpenReminderLosesItsPlan() {
    let planned = date(2026, 10, 15, 9)
    let old = date(2026, 10, 15, 7)
    let new = date(2026, 10, 22, 7)
    XCTAssertEqual(
      plan(planned, from: old, to: new, repeats: false), planned,
      "a one-off keeps its plan when its deadline moves")
    XCTAssertEqual(
      plan(planned, from: old, to: new, isDone: true), planned, "a finished series is left alone")
    XCTAssertEqual(
      plan(planned, from: new, to: old), planned, "a due date moved earlier is not a roll forward")
    XCTAssertEqual(plan(planned, from: old, to: old), planned, "no change, no effect")
    XCTAssertEqual(plan(planned, from: nil, to: new), planned)
    XCTAssertEqual(plan(planned, from: old, to: nil), planned)
  }

  func testRollingTheSamePairTwiceGivesTheSameResult() {
    // Undo (TaskActions) writes back the captured due and plan, and completing again must roll the same way.
    let planned: Date? = date(2026, 10, 15, 9)
    let due = date(2026, 10, 15, 7)
    let next = RepeatRule.monthly.next(after: due, calendar: cal)
    XCTAssertNil(plan(planned, from: due, to: next))
    XCTAssertNil(plan(planned, from: due, to: next))
    XCTAssertTrue(RepeatAdvance.movedForward(from: due, to: next))
    XCTAssertFalse(RepeatAdvance.movedForward(from: next, to: due))
  }
}
