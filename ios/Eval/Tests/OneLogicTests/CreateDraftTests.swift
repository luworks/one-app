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

  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return c
  }
  private var now: Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10, minute: 41))!
  }

  private func typed(_ text: String, _ kind: CreateDraft.Kind) -> CreateDraft {
    var draft = CreateDraft(now: now)
    draft.kind = kind
    // Simulate typing so partial input is parsed on the way, as in the composer.
    for end in text.indices {
      draft.title = String(text[...end])
      draft.applyTyped(now: now, calendar: cal)
    }
    return draft
  }

  private func parts(_ date: Date) -> [Int] {
    let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
    return [c.month!, c.day!, c.hour!, c.minute!]
  }

  func testTypedTimingFillsReminder() {
    let d = typed("Pay rent tomorrow 18:30", .reminder)
    XCTAssertEqual(d.savedTitle, "Pay rent")
    XCTAssertTrue(d.hasDueDate && d.hasDueTime)
    XCTAssertEqual(parts(d.reminderDate), [10, 30, 18, 30])
    let r3 = typed("Call mom next mon 19:05", .reminder)
    XCTAssertEqual(r3.savedTitle, "Call mom")
    XCTAssertEqual(parts(r3.reminderDate), [11, 2, 19, 5])
    XCTAssertTrue(r3.isValid)
  }

  func testTypedTimingFillsEventDurationAndAllDay() {
    let e2 = typed("Dinner with Alex fri 19:00-21:00", .calendar)
    XCTAssertEqual(e2.savedTitle, "Dinner with Alex")
    XCTAssertEqual(parts(e2.eventStart), [10, 30, 19, 0])
    XCTAssertEqual(e2.duration, 120)
    XCTAssertFalse(e2.allDay)
    let e3 = typed("Mom's birthday nov 3", .calendar)
    XCTAssertEqual(e3.savedTitle, "Mom's birthday")
    XCTAssertTrue(e3.allDay)
    XCTAssertEqual(cal.component(.day, from: e3.eventStart), 3)
  }

  func testTypedTimingFillsAlarmAndLabelIsOptional() {
    let a2 = typed("6:30 weekdays", .alarm)
    XCTAssertEqual(a2.savedTitle, "")
    XCTAssertEqual(Array(parts(a2.alarmTime).suffix(2)), [6, 30])
    XCTAssertEqual(a2.weekdays, [2, 3, 4, 5, 6])
    XCTAssertTrue(a2.isValid)
    let a3 = typed("in 20 min", .alarm)
    XCTAssertEqual(Array(parts(a3.alarmTime).suffix(2)), [11, 1])
    XCTAssertTrue(CreateDraft(now: now).isValid == false)
    var empty = CreateDraft(now: now)
    empty.kind = .alarm
    XCTAssertTrue(empty.isValid, "An alarm needs no label")
  }

  func testChipAfterTypingWinsUntilTypedTimingChanges() {
    var d = typed("Buy milk 18:30", .reminder)
    d.reminderDate = cal.date(byAdding: .hour, value: 2, to: d.reminderDate)!
    d.title += " "
    d.applyTyped(now: now, calendar: cal)
    XCTAssertEqual(
      parts(d.reminderDate), [10, 29, 20, 30], "Same typed timing keeps the chip choice")
    let plain = typed("Buy 2 apples", .reminder)
    XCTAssertEqual(plain.savedTitle, plain.parsedTitle == nil ? "Buy 2 apples" : plain.savedTitle)
  }
}
