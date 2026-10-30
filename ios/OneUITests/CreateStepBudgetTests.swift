import XCTest

/// Round 8 step budget: every common, typical and hard Reminder / Event / Alarm creation finishes in at most
/// five user operations, counted from the + tap to Create (both included). One tap, one Return, one wheel
/// column or one typed entry each count as one operation. The clock is fixed at 10:41 so dates are stable.
@MainActor
final class CreateStepBudgetTests: XCTestCase {
  private var app: XCUIApplication!
  private var steps: [String] = []

  override func setUp() async throws {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    // The step list is the evidence: attach it to every scenario, passed or not.
    let attachment = XCTAttachment(
      string: "\(name)\n\(steps.count) ops: \(steps.joined(separator: " → "))")
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // MARK: - Counted operations

  private func launch(tab: String?, extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "10:41"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 10))
    // Being on the matching tab is not an operation.
    if let tab { app.buttons[tab].firstMatch.tap() }
    steps = []
  }

  private func plus() {
    steps.append("+")
    app.buttons["New"].firstMatch.tap()
    XCTAssertTrue(app.buttons["create.save"].waitForExistence(timeout: 5))
  }

  private func type(_ text: String) {
    steps.append("type \"\(text)\"")
    let field = app.textFields["create.title"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    if !(field.value(forKey: "hasKeyboardFocus") as? Bool ?? false) { field.tap() }
    field.typeText(text)
  }

  private func tap(_ element: XCUIElement, _ label: String) {
    steps.append(label)
    XCTAssertTrue(element.waitForExistence(timeout: 3), "\(label) is on screen")
    XCTAssertTrue(element.isHittable, "\(label) is reachable without scrolling")
    element.tap()
  }

  private func chip(_ label: String) { tap(app.buttons[label].firstMatch, label) }

  private func wheel(_ index: Int, _ value: String) {
    steps.append("wheel → \(value)")
    let wheel = app.pickerWheels.element(boundBy: index)
    XCTAssertTrue(wheel.waitForExistence(timeout: 3))
    XCTAssertTrue(wheel.isHittable, "wheel \(index) is visible")
    wheel.adjust(toPickerWheelValue: value)
  }

  private func returnKey() {
    shot()
    steps.append("Return")
    app.textFields["create.title"].typeText("\n")
  }

  private func create() {
    shot()
    tap(app.buttons["create.save"], "Create")
  }

  /// The composer just before Create, kept as evidence.
  private func shot() {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func expectSummary(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
    let summary = app.staticTexts["create.summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 3), file: file, line: line)
    XCTAssertEqual(summary.label, text, file: file, line: line)
  }

  /// Created, within budget, composer closed.
  private func expectCreated(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(
      app.buttons["create.save"].waitForNonExistence(timeout: 5), "Create closed the composer",
      file: file, line: line)
    XCTAssertLessThanOrEqual(
      steps.count, 5, "\(steps.count) ops: \(steps.joined(separator: " → "))", file: file,
      line: line)
  }

  private func expectFound(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
    app.openSidebar()
    app.buttons["Search"].tap()
    let field = app.textFields["search.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
    field.typeText(title)
    let result = app.buttons.matching(
      NSPredicate(format: "identifier == 'search.result' AND label BEGINSWITH %@", title)
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), "\(title) was saved", file: file, line: line)
  }

  private func expectAlarm(
    _ time: String, _ repeatLabel: String?, file: StaticString = #filePath, line: UInt = #line
  ) {
    let rows = app.buttons.matching(identifier: "alarm.row")
    let predicate =
      repeatLabel.map { NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", time, $0) }
      ?? NSPredicate(format: "label CONTAINS %@", time)
    XCTAssertTrue(
      rows.matching(predicate).firstMatch.waitForExistence(timeout: 5),
      "an alarm at \(time) is listed", file: file, line: line)
  }

  /// "Fri 30 Oct, 18:30" for a day offset from the fixed 10:41 today.
  private func day(_ offset: Int, _ time: String? = nil) -> String {
    let date = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE d MMM"
    return f.string(from: date) + (time.map { ", " + $0 } ?? "")
  }

  // MARK: - Reminders (from Today)

  func testR1ReminderTodayAtPreset() {
    launch(tab: nil)
    plus()
    type("Buy milk")
    chip("18:30")
    expectSummary(day(0, "18:30"))
    returnKey()
    expectCreated()
    expectFound("Buy milk")
  }

  func testR2ReminderTomorrowWithChips() {
    launch(tab: nil)
    plus()
    type("Pay rent")
    chip("Tomorrow")
    chip("18:30")
    expectSummary(day(1, "18:30"))
    returnKey()
    expectCreated()
    expectFound("Pay rent")
  }

  func testR3ReminderNextMondayOddTimeTyped() {
    launch(tab: nil)
    plus()
    type("Call mom next mon 19:05")
    let summary = app.staticTexts["create.summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 3))
    XCTAssertTrue(summary.label.hasPrefix("Mon "), summary.label)
    XCTAssertTrue(summary.label.hasSuffix(", 19:05"), summary.label)
    returnKey()
    expectCreated()
    expectFound("Call mom")
  }

  // MARK: - Alarms (from Clock)

  func testA1AlarmWithWheels() {
    launch(tab: "Clock")
    plus()
    wheel(0, "07")
    wheel(1, "00")
    expectSummary("Rings 07:00 · Once")
    create()
    expectCreated()
    expectAlarm("7:00", nil)
  }

  func testA2AlarmWeekdaysWithWheelsAndRepeatCard() {
    launch(tab: "Clock")
    plus()
    wheel(0, "06")
    wheel(1, "30")
    chip("Weekdays")
    expectSummary("Rings 06:30 · Weekdays")
    create()
    expectCreated()
    expectAlarm("6:30", "Weekdays")
  }

  func testA2AlarmPicksSingleDaysDirectly() {
    launch(tab: "Clock")
    plus()
    wheel(0, "06")
    tap(app.buttons["create.day.2"], "Monday")
    tap(app.buttons["create.day.4"], "Wednesday")
    create()
    expectCreated()
  }

  func testA3AlarmInTwentyMinutesTyped() {
    launch(tab: "Clock")
    plus()
    tap(app.textFields["create.title"], "label field")
    type("in 20 min")
    expectSummary("Rings 11:01 · Once")
    returnKey()
    expectCreated()
    expectAlarm("11:01", nil)
  }

  // MARK: - Events (from Calendar)

  func testE1EventTomorrowTyped() {
    launch(tab: "Calendar")
    plus()
    type("Project sync tomorrow 15:00")
    expectSummary(day(1, "15:00") + "–16:00")
    returnKey()
    expectCreated()
    expectFound("Project sync")
  }

  func testE2EventFridayTwoHoursPersonalCalendar() {
    launch(tab: "Calendar", extra: ["-uiTestingCalendars"])
    plus()
    type("Dinner with Alex fri 19:00-21:00")
    chip("Personal")
    XCTAssertTrue(app.buttons["Personal"].firstMatch.isSelected)
    let summary = app.staticTexts["create.summary"]
    XCTAssertTrue(summary.label.hasPrefix("Fri "), summary.label)
    XCTAssertTrue(summary.label.hasSuffix(", 19:00–21:00"), summary.label)
    XCTAssertTrue(app.buttons["2 h"].firstMatch.isSelected, "typed range set the 2 h duration")
    returnKey()
    expectCreated()
  }

  func testE3AllDayEventTyped() {
    launch(tab: "Calendar")
    plus()
    type("Mom's birthday nov 3")
    let summary = app.staticTexts["create.summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 3))
    XCTAssertTrue(summary.label.hasSuffix("3 Nov · All-day"), summary.label)
    returnKey()
    expectCreated()
    expectFound("Mom's birthday")
  }

  /// The chip path for an event: duration and calendar are one tap each, the day and hour one wheel each.
  func testE1EventWithWheels() {
    launch(tab: "Calendar")
    plus()
    type("Planning")
    wheel(1, "15")
    chip("2 h")
    expectSummary(day(0, "15:00") + "–17:00")
    create()
    expectCreated()
  }
}
