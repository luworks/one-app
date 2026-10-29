import XCTest

@testable import TodayCore

final class CreateDraftTests: XCTestCase {
  func testSwitchingTypesPreservesTextAndIndependentSettings() {
    let now = Date(timeIntervalSince1970: 1000)
    var draft = CreateDraft(now: now)
    draft.title = "Call Alex"
    draft.notes = "Bring notes"
    draft.duration = 90
    draft.weekdays = [2, 4]
    draft.kind = .calendar
    draft.kind = .alarm
    draft.kind = .reminder
    XCTAssertEqual(draft.title, "Call Alex")
    XCTAssertEqual(draft.notes, "Bring notes")
    XCTAssertEqual(draft.duration, 90)
    XCTAssertEqual(draft.weekdays, [2, 4])
  }

  func testWhitespaceAndRepeatWithoutDateCannotCreate() {
    var draft = CreateDraft(now: Date())
    draft.title = " \n "
    XCTAssertFalse(draft.isValid)
    draft.title = "  Retry me  "
    XCTAssertTrue(draft.isValid)
    XCTAssertEqual(draft.trimmedTitle, "Retry me")
    draft.reminderRepeat = .daily
    XCTAssertFalse(draft.isValid)
    draft.hasDueDate = true
    XCTAssertTrue(draft.isValid)
  }
  func testCommitRejectsDuplicateAndAllowsRetryAfterFailure() {
    var state = CreateCommitState()
    XCTAssertTrue(state.begin())
    XCTAssertFalse(state.begin())
    state.finish(success: false)
    XCTAssertTrue(state.begin())
    state.finish(success: true)
    XCTAssertFalse(state.begin())
  }
}
