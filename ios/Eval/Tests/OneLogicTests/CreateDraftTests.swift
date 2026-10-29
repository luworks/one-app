import XCTest

@testable import TodayCore

final class CreateDraftTests: XCTestCase {
  func testWeekStartReordersWithoutChangingWeekdayIdentity() {
    XCTAssertEqual(CreateWeekdays.order(starting: 2), [2, 3, 4, 5, 6, 7, 1])
    XCTAssertEqual(CreateWeekdays.order(starting: 1), [1, 2, 3, 4, 5, 6, 7])
    let chosen: Set<Int> = [2, 4, 6]
    for start in [1, 2] {
      XCTAssertEqual(Set(CreateWeekdays.order(starting: start).filter(chosen.contains)), chosen)
    }
    XCTAssertEqual(
      CreateWeekdays.days(for: .weeklyOn([2, 4, 6]), date: Date(), calendar: .current), chosen)
    XCTAssertEqual(CreateWeekdays.days(for: .monthly, date: Date(), calendar: .current), [])
  }

  func testReminderDeliveryRoundTripAndDisabledSnooze() throws {
    let alert = ReminderAlert(sound: "Chimes", snoozeMinutes: 15)
    XCTAssertEqual(ReminderAlert(rawValue: alert.rawValue), alert)
    XCTAssertEqual(alert.category, "TODAY_REMINDER_15")
    let disabled = ReminderAlert(sound: "", snoozeMinutes: nil)
    XCTAssertNil(ReminderAlert(rawValue: disabled.rawValue)?.snoozeMinutes)
    XCTAssertEqual(disabled.category, "TODAY_REMINDER_OFF")
    XCTAssertNil(ReminderAlert(rawValue: nil))
    XCTAssertNil(ReminderAlert(rawValue: "invalid"))
    var snapshot = TaskSnapshot(title: "Delivery survives Undo")
    snapshot.reminderAlert = alert.rawValue
    let decoded = try JSONDecoder().decode(TaskSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertEqual(decoded.reminderAlert, alert.rawValue)
    snapshot.reminderAlert = nil
    let legacy = try JSONDecoder().decode(TaskSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertNil(legacy.reminderAlert)
  }

  func testReminderAndAlarmDeliveryDraftsStayIndependent() {
    var draft = CreateDraft(now: Date())
    draft.reminderSnoozeMinutes = 15
    draft.reminderSound = "Chimes"
    draft.sound = "Glass"
    draft.snoozeMinutes = 5
    draft.kind = .alarm
    draft.kind = .reminder
    XCTAssertEqual(draft.reminderSnoozeMinutes, 15)
    XCTAssertEqual(draft.reminderSound, "Chimes")
    XCTAssertEqual(draft.sound, "Glass")
    XCTAssertEqual(draft.snoozeMinutes, 5)
  }

  func testEventDetailsSurviveUndoSnapshotRoundTrip() throws {
    let original = EventSnapshot(
      title: "Review", start: Date(timeIntervalSince1970: 1000),
      durationMinutes: 60, local: true, location: "Office", url: "https://example.com/meeting",
      busy: false)
    let restored = try JSONDecoder().decode(
      EventSnapshot.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(restored, original)
    let legacy = EventSnapshot(title: "Legacy", start: original.start, durationMinutes: 30)
    let decoded = try JSONDecoder().decode(EventSnapshot.self, from: JSONEncoder().encode(legacy))
    XCTAssertNil(decoded.location)
    XCTAssertNil(decoded.url)
    XCTAssertNil(decoded.busy)
  }
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
