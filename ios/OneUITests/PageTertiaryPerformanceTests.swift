import XCTest

/// Additional opt-in screen measurements; no selection, save, grant or permission actions.
/// Each method launches once: first_cycle_plus_two_revisits, in the exact order below.
/// Keep ordered raw samples; compare candidates with the same sequence, not a pooled warm/cold baseline.
/// Endpoints describe destination geometry + two display-link callbacks, not async readiness or presentation.
@MainActor
final class PageTertiaryPerformanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastSequence = 0

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = TestData.launchArguments + ["-performanceTrace", "-performancePageRevisits",
                                                            "-uiTestingNow", "09:41"]
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
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10),
                       .completed, "Fresh app endpoint: \(route), visit \(visit)")
        guard let report = reports.allElementsBoundByIndex.map({ $0.label }).first(where: {
            $0.contains(";name=\(name);") && $0.contains(";route=\(route);") && $0.hasSuffix(expectedVisit)
        }) else { XCTFail("Missing destination report"); return }
        let fields = Dictionary(uniqueKeysWithValues: report.split(separator: ";").compactMap { field -> (String, String)? in
            let pair = field.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
        XCTAssertEqual(fields["v"], "1")
        XCTAssertEqual(fields["name"], name)
        XCTAssertEqual(fields["route"], route)
        XCTAssertEqual(fields["page_context"], "first_cycle_plus_two_revisits")
        XCTAssertEqual(fields["route_visit"], String(visit))
        guard let seq = Int(fields["seq"] ?? ""), let start = UInt64(fields["start_ns"] ?? ""),
              let end = UInt64(fields["end_ns"] ?? ""), let ms = Double(fields["ms"] ?? "") else {
            XCTFail("Missing exact app-monotonic fields: \(report)"); return
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

    /// Estimated 90-140 seconds. Existing visible Year key and Add List journeys, open/close only.
    func testYearKeyAndNewListEditorEndpoints() throws {
        app.buttons["Calendar"].firstMatch.tap()
        app.buttons["calendar.mode.year"].tap()
        for visit in 1...3 {
            let keys = app.buttons.matching(identifier: "calendar.year.key")
            XCTAssertTrue(keys.firstMatch.waitForExistence(timeout: 5))
            // Match CalendarTabTests: lazy years expose offscreen buttons, so choose the visible one.
            let key = try XCTUnwrap(keys.allElementsBoundByIndex.first(where: { $0.isHittable }),
                                    "The visible year has a reachable key button")
            tap(key, route: "calendar.year.key", visit: visit, ready: app.staticTexts["Unusually busy"])
            app.navigationBars["Year"].buttons["Done"].tap()

            app.buttons["Reminders"].firstMatch.tap()
            let addList = app.buttons["addList"]
            for _ in 0..<6 where !(addList.exists && addList.isHittable) { app.swipeUp() }
            // Existing CRUDTests Add List locator, without entering a name or saving.
            tap(addList, route: "list.editor", visit: visit, ready: app.textFields["List Name"])
            XCTAssertTrue(app.navigationBars["New List"].exists)
            app.navigationBars["New List"].buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["New List"].waitForNonExistence(timeout: 5))
            app.buttons["Calendar"].firstMatch.tap()
        }
    }

    /// Estimated 90-140 seconds. Shared SoundScreen opened from alarm and timer; no sound selection.
    /// Timer Label is an inline text field, not another screen: presence only, no label latency sample.
    func testAlarmAndTimerSoundEndpoints() {
        app.buttons["Clock"].firstMatch.tap()
        for visit in 1...3 {
            tap(app.buttons["New"], route: "alarm.editor", visit: visit, ready: app.staticTexts["Add Alarm"])
            let alarmSound = app.buttons["alarm.sound"]
            for _ in 0..<4 where !(alarmSound.exists && alarmSound.isHittable) { app.swipeUp() }
            tap(alarmSound, route: "alarm.sound", visit: visit, ready: app.navigationBars["Sound"])
            XCTAssertTrue(app.buttons["Default"].exists)
            // Existing AlarmsTabTests back selector; none of the tone rows are tapped.
            app.navigationBars["Sound"].buttons.firstMatch.tap()
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Add Alarm"].waitForNonExistence(timeout: 5))

            app.buttons["clock.section.timer"].tap()
            let timerSound = app.buttons["timer.sound"]
            for _ in 0..<4 where !(timerSound.exists && timerSound.isHittable) { app.swipeUp() }
            XCTAssertTrue(app.textFields["timer.label"].exists)
            let soundBefore = timerSound.label
            tap(timerSound, route: "timer.sound", visit: visit, ready: app.navigationBars["Sound"])
            XCTAssertTrue(app.buttons["Default"].exists)
            app.navigationBars["Sound"].buttons.firstMatch.tap()
            XCTAssertTrue(timerSound.waitForExistence(timeout: 5))
            XCTAssertEqual(timerSound.label, soundBefore, "Returning without a choice preserves the sound")
            app.buttons["clock.section.alarms"].tap()
        }
    }
}
