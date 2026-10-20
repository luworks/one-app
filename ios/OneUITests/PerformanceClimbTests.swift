import XCTest

/// Run on frozen source and candidate with identical compiler settings; retain the build identity.
/// XCTest drives journeys; only the app's monotonic samples measure operation latency.
@MainActor
final class PerformanceClimbTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
      app.launchArguments =
        TestData.launchArguments + ["-performanceTrace", "-uiTestingNow", "09:41"]
    }
  }

  private func element(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)[id].firstMatch
  }

  private func reports() -> Set<String> {
    Set(
      app.staticTexts.matching(identifier: "performance.trace").allElementsBoundByIndex.map({
        $0.label
      }))
  }

  @discardableResult
  private func sample(_ name: String, after previous: String = "") -> String {
    var report = ""
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let matches = self.reports().filter { $0 != previous && $0.contains(";name=\(name);") }
        guard matches.count == 1, let value = matches.first else { return false }
        report = value
        return true
      }, object: nil)
    XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 10), .completed, "App endpoint: \(name)")
    let fields = Dictionary(
      uniqueKeysWithValues: report.split(separator: ";").compactMap { field -> (String, String)? in
        let pair = field.split(separator: "=", maxSplits: 1)
        return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
      })
    guard let start = UInt64(fields["start_ns"] ?? ""), let end = UInt64(fields["end_ns"] ?? ""),
      let ms = Double(fields["ms"] ?? "")
    else {
      XCTFail("Missing monotonic endpoint fields: \(report)")
      return report
    }
    XCTAssertGreaterThanOrEqual(end, start)
    XCTAssertTrue(ms.isFinite && ms >= 0)
    print("PERF_SAMPLE_APP \(report)")
    let attachment = XCTAttachment(string: report)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if app.launchArguments.contains("-performanceResources") {
      guard let sequence = Int(fields["seq"] ?? ""), let route = fields["route"] else {
        XCTFail("Missing resource identity: \(report)")
        return report
      }
      return capturePageResourceWindow(
        app: app, sequence: sequence, start: start, layout: end, route: route) ?? report
    }
    return report
  }

  private func tap(_ label: String, sample name: String, ready: XCUIElement) {
    let current = reports()
    XCTAssertEqual(current.count, 1, "Visible trace mirrors must agree before navigation")
    let previous = current.first ?? ""
    let automationStart = DispatchTime.now().uptimeNanoseconds
    app.buttons[label].firstMatch.tap()
    sample(name, after: previous)
    XCTAssertTrue(ready.waitForExistence(timeout: 5), "Destination content exists: \(label)")
    let automationEnd = DispatchTime.now().uptimeNanoseconds
    print(
      "PERF_AUTOMATION name=\(name) start_ns=\(automationStart) end_ns=\(automationEnd) ms=\(Double(automationEnd - automationStart) / 1_000_000)"
    )
  }

  func testLaunchAndResumeEndpoints() {
    for _ in 0..<3 {
      app.terminate()
      app.launch()
      let launch = sample("app_init_to_content_layout")
      XCTAssertTrue(app.staticTexts["todayDate"].exists)
      XCTAssertTrue(app.buttons["New"].isHittable)
      XCTAssertTrue(app.buttons["Ask AI or add anything"].isHittable)
      XCUIDevice.shared.press(.home)
      app.activate()
      sample("resume_to_content_layout", after: launch)
      XCTAssertTrue(app.staticTexts["todayDate"].exists)
      XCTAssertTrue(app.buttons["New"].isHittable)
    }
  }

  /// Separate opt-in diagnostic cohort; retain the resource journey and all kept-state assertions.
  func testRootYearCacheDiagnosticWindows() {
    app.launchArguments.append("-performanceYearCacheCounts")
    testRootNavigationResourceWindows()
  }

  /// Resource-only wrapper: preserve the original navigation and kept-state journey unchanged.
  func testRootNavigationResourceWindows() {
    app.launchArguments.append("-performanceResources")
    testNavigationEndpointsAndKeptState()
  }

  /// One profiled entry with a fixed idle observation; never use its elapsed time as a speed sample.
  func testYearEntryAllocationDiagnostic() {
    app.launch()
    sample("app_init_to_content_layout")
    tap("Calendar", sample: "today_to_calendar.week", ready: element("calendar.weekGrid"))
    tap(
      "calendar.mode.month", sample: "calendar.week_to_calendar.month",
      ready: element("calendar.monthPager"))
    tap(
      "calendar.mode.year", sample: "calendar.month_to_calendar.year",
      ready: element("calendar.year.scroll"))
    print("YEAR_ALLOCATION_IDLE_BEGIN ns=\(DispatchTime.now().uptimeNanoseconds)")
    Thread.sleep(forTimeInterval: 8)
    print("YEAR_ALLOCATION_IDLE_END ns=\(DispatchTime.now().uptimeNanoseconds)")
    XCTAssertTrue(element("calendar.year.scroll").exists)
    XCTAssertTrue(app.buttons["New"].isHittable)
  }

  func testNavigationEndpointsAndKeptState() {
    app.launch()
    sample("app_init_to_content_layout")
    for _ in 0..<3 {
      tap("Calendar", sample: "today_to_calendar.week", ready: element("calendar.weekGrid"))
      tap(
        "calendar.mode.month", sample: "calendar.week_to_calendar.month",
        ready: element("calendar.monthPager"))
      tap(
        "calendar.mode.year", sample: "calendar.month_to_calendar.year",
        ready: element("calendar.year.scroll"))
      tap(
        "calendar.mode.week", sample: "calendar.year_to_calendar.week",
        ready: element("calendar.weekGrid"))
      tap("Reminders", sample: "calendar.week_to_tasks", ready: element("list.Work"))
      tap("Clock", sample: "tasks_to_clock", ready: app.buttons["World Clock"])
      tap("Today", sample: "clock_to_today", ready: app.staticTexts["todayDate"])
    }
    app.buttons["Reminders"].firstMatch.tap()
    let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home, '")).firstMatch
    XCTAssertTrue(home.waitForExistence(timeout: 5))
    home.tap()
    XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
    app.buttons["Today"].firstMatch.tap()
    app.buttons["Reminders"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
    XCTAssertFalse(home.exists, "The open reminder list survives tab switching")
    app.buttons["Calendar"].firstMatch.tap()
    app.buttons["calendar.mode.month"].tap()
    XCTAssertTrue(element("calendar.monthPager").waitForExistence(timeout: 5))
    app.buttons["Clock"].firstMatch.tap()
    app.buttons["Calendar"].firstMatch.tap()
    XCTAssertTrue(
      element("calendar.monthPager").waitForExistence(timeout: 5), "Calendar keeps Month")
  }

  /// Matched baseline/candidate cohort: populated fixture, pinned time, first entry then two revisits.
  func testTodayWeekResponse() {
    app.launchArguments += ["-appearance", "light"]
    app.launch()
    sample("app_init_to_content_layout")
    for visit in 0..<3 {
      tap("Calendar", sample: "today_to_calendar.week", ready: element("calendar.weekGrid"))
      XCTAssertTrue(app.buttons["Calendar"].firstMatch.isSelected)
      XCTAssertTrue(app.buttons["calendar.mode.week"].isSelected)
      if visit == 0 { captureNavigation("week-light") }
      tap("Today", sample: "calendar.week_to_today", ready: app.staticTexts["todayDate"])
      XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected)
    }
  }

  func testYearWeekResponse() {
    app.launchArguments += ["-appearance", "dark"]
    app.launch()
    sample("app_init_to_content_layout")
    tap("Calendar", sample: "today_to_calendar.week", ready: element("calendar.weekGrid"))
    for visit in 0..<3 {
      tap(
        "calendar.mode.year", sample: "calendar.week_to_calendar.year",
        ready: element("calendar.year.scroll"))
      XCTAssertTrue(app.buttons["calendar.mode.year"].isSelected)
      if visit == 0 { captureNavigation("year-dark") }
      tap(
        "calendar.mode.week", sample: "calendar.year_to_calendar.week",
        ready: element("calendar.weekGrid"))
      XCTAssertTrue(app.buttons["calendar.mode.week"].isSelected)
      if visit == 0 { captureNavigation("week-dark") }
    }
  }

  func testRepeatedNavigationRetainsCalendarSelection() {
    app.launch()
    sample("app_init_to_content_layout")
    tap("Calendar", sample: "today_to_calendar.week", ready: element("calendar.weekGrid"))
    tap(
      "calendar.mode.month", sample: "calendar.week_to_calendar.month",
      ready: element("calendar.monthPager"))
    for _ in 0..<3 {
      tap("Today", sample: "calendar.month_to_today", ready: app.staticTexts["todayDate"])
      // Repeated taps on the selected destination must not toggle it or schedule a later switch.
      app.buttons["Today"].firstMatch.doubleTap()
      XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected)
      tap("Calendar", sample: "today_to_calendar.month", ready: element("calendar.monthPager"))
      app.buttons["calendar.mode.month"].doubleTap()
      XCTAssertTrue(app.buttons["calendar.mode.month"].isSelected)
      XCTAssertFalse(element("calendar.weekGrid").exists)
    }
  }

  private func captureNavigation(_ name: String) {
    let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    capture.name = "navigation-response-\(name)"
    capture.lifetime = .keepAlways
    add(capture)
  }

  func testYearScrollMemory() {
    app.launch()
    sample("app_init_to_content_layout")
    app.buttons["Calendar"].firstMatch.tap()
    app.buttons["calendar.mode.year"].tap()
    let scroll = element("calendar.year.scroll")
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))
    sample("calendar.week_to_calendar.year")
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(
      metrics: [
        XCTMemoryMetric(application: app), XCTOSSignpostMetric.scrollingAndDecelerationMetric,
      ], options: options
    ) {
      scroll.swipeUp()
      scroll.swipeDown()
    }
  }
}
