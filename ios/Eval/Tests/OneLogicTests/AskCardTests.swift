import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

/// The AI preview card says what will be created: "New reminder", "Tomorrow 9:00 AM · alerts you", the list, and the saved
/// reminder is written that way (due time + alert at it, never a planned time unless the line is about working time).
final class AskCardTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
                return c
    }()

    /// Real time: `DayLabel` ("Tomorrow") decides with the real clock.
    var now: Date { .now }

    func parse(_ s: String) -> Capture { CaptureParser.parse(s, now: now, calendar: cal) }

    func testRemindMeWithTimeAlertsAtThatTime() {
        let c = parse("remind me to call mom tomorrow at 9am")
        XCTAssertEqual(c.kind, .task)
        XCTAssertTrue(c.alertsAtTime)
        XCTAssertEqual(c.kindLabel, "New reminder")
        XCTAssertTrue(c.summary.hasPrefix("Tomorrow "), c.summary)
        XCTAssertTrue(c.summary.hasSuffix(" · alerts you"), c.summary)
        XCTAssertFalse(c.summary.contains("Planned"), c.summary)
        // Written as a due time with the alert at it: the same as Quick Add.
        let t = c.taskTiming
        XCTAssertNil(t.plannedStart)
        XCTAssertEqual(t.due, c.plannedStart)
        XCTAssertEqual(t.alertMinutesBefore, 0)
    }

    func testChineseRemindWithTime() {
        let c = parse("明天早上9点提醒我给妈妈打电话")
        XCTAssertTrue(c.alertsAtTime, c.summary)
        XCTAssertTrue(c.summary.hasSuffix("alerts you"), c.summary)
        XCTAssertEqual(c.taskTiming.alertMinutesBefore, 0)
    }

    func testWorkTimeStaysPlanned() {
        for line in ["work on the report tomorrow at 2pm", "write the proposal tomorrow at 2pm for 2 hours"] {
            let c = parse(line)
            XCTAssertTrue(c.isWorkBlock, line)
            XCTAssertFalse(c.alertsAtTime, line)
            XCTAssertTrue(c.summary.hasPrefix("Planned "), c.summary)
            XCTAssertFalse(c.summary.contains("alerts you"), c.summary)
            let t = c.taskTiming
            XCTAssertEqual(t.plannedStart, c.plannedStart, line)
            XCTAssertNil(t.due, line)
            XCTAssertNil(t.alertMinutesBefore, line)
        }
    }

    func testRemindWordsBeatWorkWords() {
        XCTAssertFalse(parse("remind me to work on the report at 3pm").isWorkBlock)
    }

    func testDateOnlyIsADeadlineWithoutAlert() {
        let c = parse("send the Q3 report by Friday")
        XCTAssertFalse(c.alertsAtTime)
        XCTAssertTrue(c.summary.hasPrefix("Due "), c.summary)
        XCTAssertFalse(c.summary.contains("alerts you"))
        let t = c.taskTiming
        XCTAssertNil(t.plannedStart)
        XCTAssertEqual(t.due, c.day)
    }

    func testEventAndAlarmLabels() {
        XCTAssertEqual(parse("dentist appointment tomorrow at 3pm").kindLabel, "New event")
        var alarm = parse("call mom tomorrow at 9am")
        alarm.ringsAsAlarm = true
        XCTAssertEqual(alarm.kindLabel, "New alarm")
        XCTAssertFalse(alarm.alertsAtTime)
        XCTAssertTrue(alarm.summary.hasPrefix("Alarm "), alarm.summary)
        XCTAssertEqual(alarm.taskTiming.plannedStart, alarm.plannedStart, "an alarm keeps its time")
    }

    func testAIDraftWithLengthIsWorkTime() throws {
        let work = try XCTUnwrap(CaptureDraftMapper.capture(
            from: .init(kind: "task", title: "Write report", time: "14:00", durationMinutes: 120), now: now, calendar: cal))
        XCTAssertTrue(work.isWorkBlock)
        let plain = try XCTUnwrap(CaptureDraftMapper.capture(
            from: .init(kind: "task", title: "Call mom", time: "09:00"), now: now, calendar: cal))
        XCTAssertTrue(plain.alertsAtTime)
    }

    func testListLabelUsesRemindersForTheDefault() {
        var c = parse("buy milk")
        XCTAssertEqual(c.listLabel, "Reminders")
        c.listName = ""
        XCTAssertEqual(c.listLabel, "Reminders")
        c.listName = "Groceries"
        XCTAssertEqual(c.listLabel, "Groceries")
    }

    // MARK: Title leftovers

    func testDanglingConnectorsAreStripped() {
        XCTAssertEqual(parse("请把我可以卖的东西都放到车库去，然后今天下午 3 点的时候提醒我移动一下").title,
                       "把我可以卖的东西都放到车库去，然后提醒我移动一下")
        XCTAssertEqual(parse("then call mom tomorrow at 9am and").title, "call mom")
        XCTAssertEqual(parse("下雨的时候带伞").title, "下雨的时候带伞", "a 的时候 that is part of the sentence stays")
    }
}
