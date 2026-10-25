import XCTest

@testable import TodayCore

final class DraftMatchTests: XCTestCase {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func item(_ id: Int, _ title: String, hours: Double?, done: Bool = false)
    -> DraftMatch.Candidate
  {
    .init(
      id: id, fields: [title], date: hours.map { now.addingTimeInterval($0 * 3600) },
      isDone: done)
  }

  func testShortDraftsMatchNothing() {
    XCTAssertEqual(DraftMatch.pick("d", from: [item(0, "Dentist", hours: 1)], now: now), [])
    XCTAssertEqual(DraftMatch.pick("  ", from: [item(0, "Dentist", hours: 1)], now: now), [])
  }

  func testEveryWordMustMatchAndDoneItemsAreLeftOut() {
    let items = [
      item(0, "Dentist", hours: 2), item(1, "Call the dentist", hours: 5),
      item(2, "Dentist", hours: 1, done: true), item(3, "Gym", hours: 1),
    ]
    XCTAssertEqual(DraftMatch.pick("dentist", from: items, now: now), [0, 1])
    XCTAssertEqual(DraftMatch.pick("call dentist", from: items, now: now), [1])
    XCTAssertEqual(DraftMatch.pick("dentist tomorrow 3pm", from: items, now: now), [])
  }

  func testUpcomingFirstThenUndatedThenRecentPastAndLimit() {
    let items = [
      item(0, "Review", hours: -30), item(1, "Review", hours: nil), item(2, "Review", hours: 48),
      item(3, "Review", hours: 3), item(4, "Review", hours: -2),
    ]
    XCTAssertEqual(DraftMatch.pick("review", from: items, now: now, limit: 5), [3, 2, 1, 4, 0])
    XCTAssertEqual(DraftMatch.pick("review", from: items, now: now), [3, 2, 1])
  }
}
