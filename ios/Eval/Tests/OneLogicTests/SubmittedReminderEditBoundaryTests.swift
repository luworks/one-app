import Foundation
import XCTest

@testable import TodayCore

final class SubmittedReminderEditBoundaryTests: XCTestCase {
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    return result
  }
  private let now = Date(timeIntervalSince1970: 1_792_314_000)

  func testTimeOnlyRefinementsCannotBecomeNewOneOffReminders() throws {
    let pending = CaptureConversation.parse(
      "Every Friday at 3pm remind me to call Alex", now: now, calendar: calendar)
    for text in ["make it 4pm", "改成下午4点", "Actually 4:30"] {
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
      guard
        case .updated(let updated) = Dialogue.refine(
          pending, with: text, now: now, calendar: calendar)
      else { return XCTFail("Expected a preview refinement: \(text)") }
      XCTAssertEqual(updated.title, pending.title, text)
      XCTAssertEqual(updated.repeatRule, pending.repeatRule, text)
      XCTAssertEqual(updated.kind, pending.kind, text)
      XCTAssertEqual(updated.ringsAsAlarm, pending.ringsAsAlarm, text)
    }
  }

  func testAmbiguousExistingEditCannotUseSubmittedCreationGrant() throws {
    let items = try [15, 16].map { hour in
      EditItem(
        id: "visit-\(hour)", type: "task", title: "[QA] dentist",
        start: try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)),
        minutes: 30, attendees: 0)
    }
    let text = "Move [QA] dentist to 5pm"
    XCTAssertNil(
      OneOffReminderRequest.capture(text, now: now, calendar: calendar, existingItems: { items }))
    let decision = Editing.decide(text: text, plan: nil, items: items, now: now, calendar: calendar)
    XCTAssertEqual(decision.op, .clarify)
    XCTAssertNil(decision.target)
  }

  func testPhysicalNewReminderWithChangeVerbKeepsItsGrant() throws {
    let item = EditItem(id: "visit", type: "task", title: "Dentist", minutes: 30, attendees: 0)
    let capture = try XCTUnwrap(
      OneOffReminderRequest.capture(
        "Remind me to change the oil tomorrow at 9am", now: now, calendar: calendar,
        existingItems: { [item] }))
    XCTAssertTrue(capture.title.lowercased().contains("oil"))
    XCTAssertEqual(capture.hour, 9)
    XCTAssertNil(capture.repeatRule)
  }

  func testOrdinaryNewReminderDoesNotReadEditCandidates() throws {
    let capture = try XCTUnwrap(
      OneOffReminderRequest.capture(
        "Remind me to buy paper tomorrow at 9am", now: now, calendar: calendar,
        existingItems: {
          XCTFail("Ordinary capture must not read edit candidates")
          return []
        }))
    XCTAssertEqual(capture.hour, 9)
    XCTAssertTrue(capture.title.lowercased().contains("paper"))
    XCTAssertNil(capture.repeatRule)
  }
}
