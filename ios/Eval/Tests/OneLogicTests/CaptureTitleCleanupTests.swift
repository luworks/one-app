import XCTest
@testable import OneLogic

/// Small inline fixtures for request syntax versus meaningful action wording.
final class CaptureTitleCleanupTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 41))!
    }

    func testMissingTimeAlarmCannotBeAddedAsReminder() {
        var capture = Capture(title: "Sleep", day: now, hasDay: false, ringsAsAlarm: true)
        XCTAssertFalse(capture.isReadyToAdd)
        capture.hour = 23
        XCTAssertTrue(capture.isReadyToAdd)
        capture.hour = nil
        capture.ringsAsAlarm = false
        XCTAssertTrue(capture.isReadyToAdd, "an untimed reminder still supports Add")
    }

    func testReportedReminderKeepsModalityAndTiming() {
        let capture = CaptureParser.parse("今天晚上11点的时候提醒我，必须要睡觉", now: now, calendar: calendar)
        XCTAssertEqual(capture.title, "必须要睡觉")
        XCTAssertEqual(capture.day, calendar.startOfDay(for: now))
        XCTAssertTrue(capture.hasDay)
        XCTAssertEqual(capture.hour, 23)
        XCTAssertEqual(capture.minute, 0)
        XCTAssertEqual(capture.kind, .task)
        XCTAssertFalse(capture.ringsAsAlarm)
        XCTAssertFalse(capture.isWorkBlock)
        let eating = CaptureParser.parse("今天晚上6点的时候吧，就提醒我一定不能再吃饭了", now: now, calendar: calendar)
        XCTAssertEqual(eating.title, "一定不能再吃饭了")
        XCTAssertEqual(eating.hour, 18)
        XCTAssertEqual(eating.minute, 0)
        XCTAssertEqual(eating.day, calendar.startOfDay(for: now))
    }

    func testReminderCleanupPreservesConditionsNegationAndLanguage() {
        let cases = [
            ("今天晚上11点的时候，提醒我：一定要睡觉！", "一定要睡觉"),
            ("明天提醒我下雨的时候带伞", "下雨的时候带伞"),
            ("提醒我不要忘记带药", "不要忘记带药"),
            ("Remind me I must not skip medication tomorrow at 9am", "I must not skip medication"),
            ("Please remind me: I must call Mom tomorrow at 9am!", "I must call Mom"),
            ("下雨的时候带伞", "下雨的时候带伞"),
            ("时候到了检查烤箱", "时候到了检查烤箱"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CaptureParser.parse(input, now: now, calendar: calendar).title, expected, input)
        }
    }

    func testModelTitleCleanupKeepsStructuredFields() throws {
        // The model has already extracted time/date; only its residual title is cleaned.
        let draft = CaptureDraft(kind: "task", title: "的时候提醒我，必须要睡觉。",
                                 date: "2026-10-18", time: "23:00", repeatRule: "daily")
        let capture = try XCTUnwrap(CaptureDraftMapper.capture(from: draft, now: now, calendar: calendar))
        XCTAssertEqual(capture.title, "必须要睡觉")
        XCTAssertEqual(capture.day, calendar.startOfDay(for: now))
        XCTAssertTrue(capture.hasDay)
        XCTAssertEqual(capture.hour, 23)
        XCTAssertEqual(capture.minute, 0)
        XCTAssertEqual(capture.repeatRule, "daily")
        XCTAssertEqual(capture.kind, .task)
        XCTAssertTrue(capture.fromAppleIntelligence)
    }

    func testModelTitlesDoNotLoseActionContent() throws {
        for (input, expected) in [
            ("的时候，必须要睡觉", "必须要睡觉"),
            ("的时候吧，就提醒我一定不能再吃饭了", "一定不能再吃饭了"),
            ("提醒我不要忘记带药", "不要忘记带药"),
            ("remind me to never skip medication!", "never skip medication"),
            ("下雨的时候带伞", "下雨的时候带伞"),
            ("Reminder system design review", "Reminder system design review"),
        ] {
            let capture = try XCTUnwrap(CaptureDraftMapper.capture(
                from: CaptureDraft(kind: "event", title: input, date: "2026-10-19", time: "10:30"),
                now: now, calendar: calendar))
            XCTAssertEqual(capture.title, expected, input)
            XCTAssertEqual(capture.kind, .event, input)
            XCTAssertEqual(capture.hour, 10, input)
            XCTAssertEqual(capture.minute, 30, input)
            XCTAssertEqual(calendar.component(.day, from: capture.day), 19, input)
        }
    }
}
