import XCTest

@testable import TodayCore

final class ReminderAlertTests: XCTestCase {
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
}
