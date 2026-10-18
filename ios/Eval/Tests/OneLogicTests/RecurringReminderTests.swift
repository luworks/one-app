import XCTest
@testable import OneLogic

final class RecurringReminderTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))! }

    func testExactOwnerRequestsPreserveTitleTimeAndAllWeekdays() throws {
        for (text, days) in [
            ("每周日下午5点提醒我丢垃圾", [1]),
            ("添加一个reminder：每周五、每周日下午5点提醒我丢垃圾", [1, 6]),
            ("每周五和周日下午五点提醒我丢垃圾", [1, 6]),
            ("Every Friday and Sunday at 5pm remind me to take out trash", [1, 6])
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .capture, text)
            let c = CaptureConversation.parse(text, now: now, calendar: cal)
            XCTAssertEqual(c.title, text.contains("每") ? "丢垃圾" : "take out trash", text)
            XCTAssertEqual(c.kind, .task, text)
            XCTAssertFalse(c.ringsAsAlarm, text)
            XCTAssertEqual(c.hour, 17, text)
            XCTAssertEqual(c.minute, 0, text)
            XCTAssertEqual(c.repeatRule, RepeatRule.weeklyOn(days).rawValue, text)
            XCTAssertEqual(cal.component(.weekday, from: c.day), 1, text)
            let restored = try JSONDecoder().decode(Capture.self, from: JSONEncoder().encode(c))
            XCTAssertEqual(restored, c, "Stored chat must retain the entire recurrence")
        }
    }

    func testWeekdaysWeekendAndPassedOccurrenceStayInTheirSets() {
        let weekday = CaptureConversation.parse("每个工作日中午12点提醒我带午饭", now: now, calendar: cal)
        XCTAssertEqual(ChatRouting.intent("每个工作日中午12点提醒我带午饭"), .capture)
        XCTAssertEqual(weekday.kind, .task)
        XCTAssertEqual(weekday.title, "带午饭")
        XCTAssertEqual(cal.component(.weekday, from: weekday.day), 2)
        XCTAssertEqual(weekday.repeatRule, "weekdays")
        let weekend = CaptureParser.parse("Remind me every weekend at 10am to water plants", now: now, calendar: cal)
        XCTAssertEqual(weekend.repeatRule, "weekly:1,7")
        XCTAssertEqual(weekend.title, "water plants")
        let later = now.addingTimeInterval(10 * 3600)
        let passed = CaptureParser.parse("每周五、每周日下午5点提醒我丢垃圾", now: later, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: passed.day), 6)
        XCTAssertEqual(passed.hour, 17)
    }

    func testAddingRecurrenceAndCorrectingTimeKeepUntouchedFields() throws {
        let initial = CaptureConversation.parse("Remind me to brush the dog today at 4pm", now: now, calendar: cal)
        guard case .updated(let repeated) = Dialogue.refine(initial, with: "Make that repeat every Thursday and Sunday, keeping 4pm.", now: now, calendar: cal) else {
            return XCTFail("Adding recurrence should update the open preview")
        }
        XCTAssertEqual(repeated.title, initial.title)
        XCTAssertEqual(repeated.repeatRule, "weekly:1,5")
        XCTAssertEqual(repeated.hour, 16)
        guard case .updated(let corrected) = Dialogue.refine(repeated, with: "Actually, 6pm.", now: now, calendar: cal) else {
            return XCTFail("Time correction should update the open preview")
        }
        XCTAssertEqual(corrected.title, initial.title)
        XCTAssertEqual(corrected.repeatRule, repeated.repeatRule)
        XCTAssertEqual(corrected.day, repeated.day)
        XCTAssertEqual(corrected.hour, 18)
    }

    func testDiscussionQuotesReportsAndDeclinesStayConversation() {
        for text in [
            "不要创建每周六上午十点洗车的提醒，我只是拿这个当例子。",
            "为什么每周日下午五点倒垃圾比每天倒一次更合适？我只是想聊聊这个安排。",
            "我昨天已经设置了每周五和周日下午五点丢垃圾的提醒，今天只是告诉你这个安排。",
            "Can you explain the sentence \"Remind me every Friday and Sunday at 5pm to take out the trash\"?",
            "Every Sunday at 5pm I already set a reminder to take out trash.",
            "Every Sunday at 5pm don't create a reminder."
        ] { XCTAssertEqual(ChatRouting.intent(text), .conversation, text) }
        let c = CaptureConversation.parse("Remind me every Friday and Sunday at 5pm not to eat peanuts", now: now, calendar: cal)
        XCTAssertTrue(c.title.lowercased().contains("not"))
        XCTAssertTrue(c.title.lowercased().contains("peanuts"))
        XCTAssertEqual(c.repeatRule, "weekly:1,6")
    }

    func testOneOffWeekendDoesNotGainRecurrence() {
        for text in ["Pick up dry cleaning this weekend", "Pick up dry cleaning next weekend"] {
            XCTAssertNil(CaptureParser.parse(text, now: now, calendar: cal).repeatRule, text)
        }
    }

    func testModelMappingRetainsAllExplicitDaysAndRejectsMalformedSets() throws {
        var draft = CaptureDraft(kind: "task", title: "Take out trash", time: "17:00", repeatRule: "weekly", repeatWeekdays: [6, 1, 6])
        let c = try XCTUnwrap(CaptureDraftMapper.capture(from: draft, now: now, calendar: cal))
        XCTAssertEqual(c.repeatRule, "weekly:1,6")
        XCTAssertEqual(cal.component(.weekday, from: c.day), 1)
        draft.date = "2026-10-30"
        draft.repeatWeekdays = [6]
        let future = try XCTUnwrap(CaptureDraftMapper.capture(from: draft, now: now, calendar: cal))
        XCTAssertEqual(cal.component(.day, from: future.day), 30, "An explicit start date is a lower bound")
        draft.repeatWeekdays = [0, 6]
        XCTAssertNil(CaptureDraftMapper.capture(from: draft, now: now, calendar: cal))
    }
}
