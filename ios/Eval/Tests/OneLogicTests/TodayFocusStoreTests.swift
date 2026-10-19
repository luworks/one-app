import Foundation
import XCTest

@testable import TodayData

final class TodayFocusStoreTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("focus-v1.json") }
  private let now = Date(timeIntervalSince1970: 1_792_000_000)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "focus-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  private func identity(
    account: String = "account-1", calendar: String = "calendar-1", item: String = "item-1",
    occurrence: Date? = nil
  ) -> FocusIdentity {
    FocusIdentity(
      provider: "eventkit", account: account, calendar: calendar, item: item, occurrence: occurrence
    )
  }

  private func disk() throws -> TodayFocusStore { try TodayFocusStore(location: .file(url)) }

  func testDiskReopenRestoresOverlayAndExplicitClearRemovesIt() throws {
    let settled = identity()
    let snoozed = identity(item: "item-2")
    let until = now.addingTimeInterval(3600)
    do {
      let focus = try disk()
      try focus.set(state: .settled, for: settled, now: now)
      try focus.set(state: .snoozed(until: until), for: snoozed, now: now)
    }
    do {
      let focus = try disk()
      XCTAssertEqual(focus.state(for: settled, now: now), .settled)
      XCTAssertEqual(focus.state(for: snoozed, now: now), .snoozed(until: until))
      try focus.set(state: nil, for: settled, now: now)
      XCTAssertNil(focus.state(for: settled, now: now))
      XCTAssertEqual(focus.records.count, 1)
      try focus.clear()
    }
    XCTAssertTrue(try disk().records.isEmpty)
  }

  func testCorruptAndNewerPayloadsAreRejectedWithoutOverwrite() throws {
    for raw in ["not-json", "{\"version\":2,\"future\":true}", "{\"version\":1,\"records\":[{}]}"] {
      let bytes = Data(raw.utf8)
      try bytes.write(to: url)
      XCTAssertThrowsError(try disk())
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  func testOpaqueLocalReferenceSurvivesDiskReopenAndStateUpdates() throws {
    let focus = try disk()
    try focus.set(state: .settled, for: identity(), now: now, localReference: "opaque-local-id")
    let reopened = try disk()
    XCTAssertEqual(reopened.records.first?.localReference, "opaque-local-id")
    try reopened.set(state: .snoozed(until: now.addingTimeInterval(60)), for: identity(), now: now)
    XCTAssertEqual(try disk().records.first?.localReference, "opaque-local-id")
    XCTAssertNil(reopened.state(for: identity(account: "different-source"), now: now))
  }

  func testSnoozeExpiresAtAbsoluteTimeAcrossDSTAndMidnight() throws {
    let formatter = ISO8601DateFormatter()
    // The fall-back hour repeats locally, but the stored instant stays unambiguous.
    let start = try XCTUnwrap(formatter.date(from: "2026-11-01T08:55:00Z"))
    let until = try XCTUnwrap(formatter.date(from: "2026-11-01T10:05:00Z"))
    let focus = try disk()
    try focus.set(state: .snoozed(until: until), for: identity(), now: start)
    XCTAssertEqual(
      focus.state(for: identity(), now: until.addingTimeInterval(-1)), .snoozed(until: until))
    XCTAssertNil(focus.state(for: identity(), now: until))
    XCTAssertNil(focus.state(for: identity(), now: until.addingTimeInterval(86400)))
    XCTAssertNil(try disk().state(for: identity(), now: until))
    try focus.set(state: .settled, for: identity(), now: start)
    XCTAssertEqual(focus.state(for: identity(), now: until.addingTimeInterval(86400)), .settled)
  }

  func testStableIdentitySurvivesRefreshButDoesNotLeakAcrossSourcesOrOccurrences() throws {
    let first = identity(occurrence: now)
    let focus = try disk()
    try focus.set(state: .settled, for: first, now: now)
    // A refreshed source object supplies the same IDs, independently of title/time edits.
    XCTAssertEqual(focus.state(for: identity(occurrence: now), now: now), .settled)
    for other in [
      identity(account: "account-2", occurrence: now),
      identity(calendar: "calendar-2", occurrence: now),
      identity(item: "item-2", occurrence: now),
      identity(occurrence: now.addingTimeInterval(86400)),
      identity(),
    ] {
      XCTAssertNil(focus.state(for: other, now: now))
    }
  }

  func testInvalidIdentityAndTimeLeaveMemoryAndDiskUnchanged() throws {
    let focus = try disk()
    try focus.set(state: .settled, for: identity(), now: now)
    let prior = focus.records
    let raw = try Data(contentsOf: url)
    for until in [
      now, now.addingTimeInterval(-1), Date(timeIntervalSinceReferenceDate: .infinity),
      Date(timeIntervalSinceReferenceDate: .nan),
    ] {
      XCTAssertThrowsError(try focus.set(state: .snoozed(until: until), for: identity(), now: now))
    }
    XCTAssertThrowsError(try focus.set(state: .settled, for: identity(account: ""), now: now))
    XCTAssertThrowsError(try focus.set(state: .settled, for: identity(calendar: " "), now: now))
    XCTAssertThrowsError(try focus.set(state: .settled, for: identity(item: ""), now: now))
    XCTAssertThrowsError(
      try focus.set(
        state: .settled, for: identity(), now: Date(timeIntervalSinceReferenceDate: .nan)))
    XCTAssertEqual(focus.records, prior)
    XCTAssertEqual(try Data(contentsOf: url), raw)
  }

  func testStaleWriterCannotOverwriteChangedOrCorruptPayload() throws {
    let stale = try disk()
    let current = try disk()
    try current.set(state: .settled, for: identity(), now: now)
    XCTAssertThrowsError(try stale.set(state: .settled, for: identity(item: "other"), now: now)) {
      XCTAssertEqual($0 as? TodayFocusStoreError, .concurrentChange)
    }
    XCTAssertTrue(stale.records.isEmpty)
    XCTAssertEqual(try disk().records, current.records)
    try Data("corrupt".utf8).write(to: url)
    XCTAssertThrowsError(try current.clear())
    XCTAssertEqual(current.records.count, 1)
    XCTAssertEqual(try Data(contentsOf: url), Data("corrupt".utf8))
  }

  func testFileWriteFailurePreservesPriorState() throws {
    let focus = try disk()
    try focus.set(state: .settled, for: identity(), now: now)
    let prior = focus.records
    let raw = try Data(contentsOf: url)
    let held = directory.appendingPathExtension("held")
    try FileManager.default.moveItem(at: directory, to: held)
    try Data("parent-is-a-file".utf8).write(to: directory)
    do {
      defer {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.moveItem(at: held, to: directory)
      }
      XCTAssertThrowsError(
        try focus.set(state: .snoozed(until: now.addingTimeInterval(60)), for: identity(), now: now)
      )
      XCTAssertEqual(focus.records, prior)
      XCTAssertEqual(try Data(contentsOf: held.appendingPathComponent("focus-v1.json")), raw)
    }
    XCTAssertEqual(try disk().records, prior)
  }
}
