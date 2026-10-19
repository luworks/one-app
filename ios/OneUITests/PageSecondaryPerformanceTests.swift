import XCTest

/// Additional measurement coverage using the frozen production probes only.
/// Each method launches once: first_cycle_plus_two_revisits, in the exact order below.
/// Keep ordered raw samples; compare candidates with the same sequence, not a pooled warm/cold baseline.
/// Endpoints describe destination geometry + two display-link callbacks, not async readiness or presentation.
@MainActor
final class PageSecondaryPerformanceTests: XCTestCase {
  private var app: XCUIApplication!
  private var lastSequence = 0

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments =
        TestData.launchArguments + [
          "-performanceTrace", "-performancePageRevisits",
          "-uiTestingNow", "09:41",
        ]
      // No -uiTestingCalendarSync: the existing test hook keeps EventKit sync off.
      XCTAssertFalse(app.launchArguments.contains("-uiTestingCalendarSync"))
      app.launch()
      XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    }
  }

  private func sample(_ route: String, visit: Int) {
    let name = "page.\(route)"
    let reports = app.staticTexts.matching(identifier: "performance.trace")
    let expectedVisit = ";route_visit=\(visit)"
    let predicate = NSPredicate { _, _ in
      reports.allElementsBoundByIndex.contains {
        $0.label.contains(";name=\(name);") && $0.label.contains(";route=\(route);")
          && $0.label.hasSuffix(expectedVisit)
      }
    }
    XCTAssertEqual(
      XCTWaiter().wait(
        for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10),
      .completed, "Fresh app endpoint: \(route), visit \(visit)")
    guard
      let report = reports.allElementsBoundByIndex.map({ $0.label }).first(where: {
        $0.contains(";name=\(name);") && $0.contains(";route=\(route);")
          && $0.hasSuffix(expectedVisit)
      })
    else {
      XCTFail("Missing destination report")
      return
    }
    let fields = Dictionary(
      uniqueKeysWithValues: report.split(separator: ";").compactMap { field -> (String, String)? in
        let pair = field.split(separator: "=", maxSplits: 1)
        return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
      })
    XCTAssertEqual(fields["v"], "1")
    XCTAssertEqual(fields["name"], name)
    XCTAssertEqual(fields["route"], route)
    XCTAssertEqual(fields["page_context"], "first_cycle_plus_two_revisits")
    XCTAssertEqual(fields["route_visit"], String(visit))
    guard let seq = Int(fields["seq"] ?? ""), let start = UInt64(fields["start_ns"] ?? ""),
      let end = UInt64(fields["end_ns"] ?? ""), let ms = Double(fields["ms"] ?? "")
    else {
      XCTFail("Missing exact app-monotonic fields: \(report)")
      return
    }
    XCTAssertGreaterThan(seq, lastSequence, "Raw sample order must remain monotonic")
    XCTAssertGreaterThanOrEqual(end, start)
    XCTAssertTrue(ms.isFinite && ms >= 0)
    XCTAssertEqual(ms, Double(end - start) / 1_000_000, accuracy: 0.001)
    lastSequence = seq
    print("PERF_SAMPLE_APP \(report)")
    let attachment = XCTAttachment(string: report)
    attachment.name = "\(name).visit\(visit)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func tap(_ target: XCUIElement, route: String, visit: Int, ready: XCUIElement) {
    XCTAssertTrue(target.waitForExistence(timeout: 5))
    XCTAssertTrue(target.isHittable, "Reachable action: \(route)")
    target.tap()
    sample(route, visit: visit)
    XCTAssertTrue(ready.waitForExistence(timeout: 5), "Destination content: \(route)")
  }

  /// Estimated 120-180 seconds. Calendar-off sheet, holidays, then automatic scope; no settings change.
  func testSettingsCalendarsHolidaysAndAutomaticScopeEndpoints() {
    for visit in 1...3 {
      app.buttons["Open menu"].tap()
      tap(
        app.buttons["Settings"].firstMatch, route: "settings", visit: visit,
        ready: app.navigationBars["Settings"])

      // Existing CalendarTabTests locator; the off sheet is measured without requesting access.
      tap(
        app.buttons["Calendars"].firstMatch, route: "settings.calendars", visit: visit,
        ready: app.navigationBars["Calendars"])
      XCTAssertTrue(app.staticTexts["Apple Calendar is off for Today"].exists)
      app.navigationBars["Calendars"].buttons["Done"].tap()
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

      let holidays = app.buttons["settings.yearHolidays"]
      app.revealSettingsRow(holidays)
      tap(
        holidays, route: "settings.holidays", visit: visit,
        ready: app.navigationBars["Holidays in Year"])
      app.navigationBars.buttons["Settings"].tap()

      // Existing LedgerTests entry; read scope only, never touch the grant toggle or Revoke.
      let automatic = app.buttons["settings.automaticChanges"]
      app.revealSettingsRow(automatic)
      tap(
        automatic, route: "settings.automaticChanges", visit: visit,
        ready: app.navigationBars["Automatic changes"])
      XCTAssertTrue(app.staticTexts["None. AI changes wait for your tap."].exists)
      XCTAssertFalse(app.buttons["grant.revoke"].exists)
      app.navigationBars.buttons["Settings"].tap()
      app.navigationBars["Settings"].buttons["Done"].tap()
      app.closeSidebar()
      // Reopening Settings starts its Form at the top; no backwards scan of lazy off-screen rows.
    }
  }

  /// Estimated 60-100 seconds. Calendar draft and new alarm open/cancel; no title, save or permission action.
  func testLocalEventAndAlarmDraftEndpoints() {
    for visit in 1...3 {
      app.buttons["Calendar"].firstMatch.tap()
      XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 5))
      // Existing CRUDTests local editor path; -uiTesting selects this draft instead of EventKit UI.
      tap(
        app.buttons["New"], route: "event.editor", visit: visit,
        ready: app.navigationBars["New event"])
      XCTAssertTrue(app.textFields["event.title"].exists)
      app.navigationBars["New event"].buttons["Cancel"].tap()
      XCTAssertTrue(app.navigationBars["New event"].waitForNonExistence(timeout: 5))

      app.buttons["Clock"].firstMatch.tap()
      let alarms = app.buttons.matching(identifier: "alarm.row")
      XCTAssertTrue(
        alarms.firstMatch.waitForExistence(timeout: 5), "Existing dataset alarms are ready")
      let countBefore = alarms.count
      // Existing AlarmsTabTests header, field and Cancel selectors. No scheduling occurs.
      tap(
        app.buttons["New"], route: "alarm.editor", visit: visit,
        ready: app.staticTexts["Add Alarm"])
      XCTAssertTrue(app.textFields["alarm.label"].exists)
      app.buttons["Cancel"].firstMatch.tap()
      XCTAssertTrue(app.staticTexts["Add Alarm"].waitForNonExistence(timeout: 5))
      XCTAssertEqual(alarms.count, countBefore, "Cancel must preserve the existing alarms")
      app.buttons["Today"].firstMatch.tap()
    }
  }
}
