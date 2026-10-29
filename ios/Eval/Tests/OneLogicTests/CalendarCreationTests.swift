import XCTest

@testable import TodayCore

final class CalendarCreationTests: XCTestCase {
  private enum Failure: Error { case commit }

  func testSelectedAndDefaultDestinationsCommitExactlyOnce() throws {
    for selection: String? in [nil, "chosen"] {
      var saved: [String] = []
      let receipt = try CalendarCreation.commit(
        calendarID: selection, connected: true,
        resolve: { $0 ?? "default" }, writable: { _ in true },
        save: {
          saved.append($0)
          return "saved-id"
        })
      XCTAssertEqual(saved, [selection ?? "default"])
      XCTAssertEqual(receipt, .committed(externalID: "saved-id"))
    }
  }

  func testInvalidSelectedDestinationNeverFallsBackOrSaves() {
    for readOnly in [false, true] {
      XCTAssertThrowsError(
        try CalendarCreation.commit(
          calendarID: "chosen", connected: true,
          resolve: { id -> String? in
            XCTAssertEqual(id, "chosen")
            return readOnly ? id : nil
          }, writable: { _ in false },
          save: { _ in
            XCTFail("Must not save")
            return "id"
          })
      ) { error in
        XCTAssertEqual(
          error as? CalendarCreationError,
          readOnly ? .calendarReadOnly : .calendarMissing)
      }
    }
  }

  func testCommitFailurePropagatesWithoutSuccessReceipt() {
    XCTAssertThrowsError(
      try CalendarCreation.commit(
        calendarID: nil, connected: true, resolve: { _ in "default" },
        writable: { _ in true }, save: { _ in throw Failure.commit })
    ) { XCTAssertTrue($0 is Failure) }
    XCTAssertThrowsError(
      try CalendarCreation.commit(
        calendarID: nil, connected: true, resolve: { _ in "default" },
        writable: { _ in true }, save: { _ in nil })
    ) { XCTAssertEqual($0 as? CalendarCreationError, .missingIdentifier) }
  }

  func testLocalOnlyDoesNotResolveOrSaveAndRejectsExplicitSystemCalendar() throws {
    func attempt(_ id: String?) throws -> CalendarCreationReceipt {
      try CalendarCreation.commit(
        calendarID: id, connected: false,
        resolve: { _ -> String? in
          XCTFail("No system access")
          return nil
        },
        writable: { _ in
          XCTFail("No system access")
          return true
        },
        save: { _ in
          XCTFail("No system access")
          return nil
        })
    }
    XCTAssertEqual(try attempt(nil), .localOnly)
    XCTAssertThrowsError(try attempt("chosen")) {
      XCTAssertEqual($0 as? CalendarCreationError, .unavailable)
    }
  }
}
