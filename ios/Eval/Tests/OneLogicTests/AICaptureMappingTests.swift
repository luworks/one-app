import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

/// Model output -> Capture. The model itself cannot run in `swift test`; this covers everything around it.
final class AICaptureMappingTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// Thursday 2026-10-15
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    lazy var now = date(2026, 10, 15, 9, 41)

    func map(_ draft: CaptureDraft, now: Date? = nil) -> Capture? {
        CaptureDraftMapper.capture(from: draft, now: now ?? self.now, calendar: cal)
    }

    // MARK: Dates

    func testNextTuesdayFromModelDate() throws {
        let c = try XCTUnwrap(map(.init(kind: "event", title: "Dentist", date: "2026-10-20", time: "15:00")))
        XCTAssertEqual(c.day, date(2026, 10, 20))
        XCTAssertTrue(c.hasDay)
        XCTAssertEqual(c.hour, 15)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(c.kind, .event)
        XCTAssertTrue(c.fromAppleIntelligence)
    }

    func testTomorrowAndToday() throws {
        XCTAssertEqual(try XCTUnwrap(map(.init(kind: "task", title: "Buy milk", date: "2026-10-16"))).day, date(2026, 10, 16))
        let today = try XCTUnwrap(map(.init(kind: "task", title: "Buy milk", date: "2026-10-15")))
        XCTAssertEqual(today.day, date(2026, 10, 15))
        XCTAssertTrue(today.hasDay)
    }

    func testYearRollover() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Pay rent", date: "2027-01-02"), now: date(2026, 12, 30, 10)))
        XCTAssertEqual(c.day, date(2027, 1, 2))
    }

    func testDateWithTimeSuffixIsAccepted() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "A", date: "2026-10-20T15:00:00")))
        XCTAssertEqual(c.day, date(2026, 10, 20))
    }

    func testBadDatesAreDropped() throws {
        for bad in ["2026-02-31", "tomorrow", "10/20", "2026-13-01", "", "2026-10"] {
            let c = try XCTUnwrap(map(.init(kind: "task", title: "A", date: bad)), bad)
            XCTAssertFalse(c.hasDay, bad)
            XCTAssertEqual(c.day, date(2026, 10, 15), bad)
        }
    }

    func testPastDateIsDropped() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "A", date: "2026-10-01")))
        XCTAssertFalse(c.hasDay)
    }

    // MARK: Time

    func testMissingTimeKeepsDueDate() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Send report", date: "2026-10-16")))
        XCTAssertNil(c.hour)
        XCTAssertNil(c.plannedStart)
        XCTAssertTrue(c.summary.hasPrefix("Due "), c.summary)
    }

    func testNoDayNoTime() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Call mom")))
        XCTAssertFalse(c.hasDay)
        XCTAssertNil(c.hour)
        XCTAssertEqual(c.summary, "No date")
    }

    func testTimeWithoutDayLaterTodayStaysToday() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Call", time: "15:30")))
        XCTAssertEqual(c.day, date(2026, 10, 15))
        XCTAssertFalse(c.hasDay)
        XCTAssertEqual(c.hour, 15)
        XCTAssertEqual(c.minute, 30)
    }

    func testTimeWithoutDayAlreadyPassedMeansTomorrow() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Call", time: "08:00")))
        XCTAssertEqual(c.day, date(2026, 10, 16))
        XCTAssertTrue(c.hasDay)
    }

    func testBadTimesAreDropped() throws {
        for bad in ["25:00", "3pm", "15", "12:75", "", "15:00:00"] {
            let c = try XCTUnwrap(map(.init(kind: "task", title: "A", date: "2026-10-16", time: bad)), bad)
            XCTAssertNil(c.hour, bad)
        }
    }

    func testDuration() throws {
        XCTAssertEqual(try XCTUnwrap(map(.init(kind: "event", title: "A", durationMinutes: 90))).durationMinutes, 90)
        for bad in [0, -5, 5000] {
            XCTAssertNil(try XCTUnwrap(map(.init(kind: "event", title: "A", durationMinutes: bad))).durationMinutes)
        }
    }

    // MARK: Repeat

    func testRepeatNames() throws {
        let cases: [(String?, String?)] = [
            ("daily", "daily"), ("weekdays", "weekdays"), ("weekly", "weekly"), ("monthly", "monthly"), ("yearly", "yearly"),
            ("Weekly", "weekly"), (" daily ", "daily"), ("weekday", "weekdays"),
            ("never", nil), ("none", nil), ("", nil), (nil, nil), ("fortnightly", nil),
        ]
        for (name, expected) in cases {
            let c = try XCTUnwrap(map(.init(kind: "task", title: "Water plants", repeatRule: name)))
            XCTAssertEqual(c.repeatRule, expected, "\(String(describing: name))")
        }
    }

    func testEveryRepeatNameIsARealRule() {
        for rule in RepeatRule.allCases {
            XCTAssertEqual(CaptureDraftMapper.repeatRule(rule.rawValue), rule.rawValue)
        }
    }

    // MARK: All day, kind, title

    func testAllDayEventDropsTimeAndDuration() throws {
        let c = try XCTUnwrap(map(.init(kind: "event", title: "Mia's birthday", date: "2026-10-20", time: "10:00",
                                        durationMinutes: 60, isAllDay: true)))
        XCTAssertTrue(c.isAllDay)
        XCTAssertEqual(c.kind, .event)
        XCTAssertNil(c.hour)
        XCTAssertNil(c.durationMinutes)
        XCTAssertTrue(c.summary.hasSuffix("All day"), c.summary)
    }

    func testAllDayOnATaskIsIgnored() throws {
        let c = try XCTUnwrap(map(.init(kind: "task", title: "Renew passport", date: "2026-10-20", isAllDay: true)))
        XCTAssertFalse(c.isAllDay)
        XCTAssertEqual(c.kind, .task)
    }

    func testKindDefaultsToTask() throws {
        XCTAssertEqual(try XCTUnwrap(map(.init(kind: "Event", title: "A"))).kind, .event)
        XCTAssertEqual(try XCTUnwrap(map(.init(kind: "reminder", title: "A"))).kind, .task)
    }

    func testEmptyTitleIsRejected() {
        XCTAssertNil(map(.init(kind: "task", title: "   ")))
        XCTAssertNil(map(.init(kind: "task", title: "")))
    }

    func testTitleIsTrimmed() throws {
        XCTAssertEqual(try XCTUnwrap(map(.init(kind: "task", title: "  Buy milk \n"))).title, "Buy milk")
    }

    func testRuleParserCapturesAreNotMarkedAsAI() {
        XCTAssertFalse(CaptureParser.parse("Buy milk tomorrow", now: now, calendar: cal).fromAppleIntelligence)
    }

    // MARK: Instructions

    func testInstructionsCarryDateZoneLocaleAndTable() {
        let text = CaptureDraftMapper.instructions(now: now, calendar: cal, localeIdentifier: "en_US")
        XCTAssertTrue(text.contains("Today is 2026-10-15, Thursday"))
        XCTAssertTrue(text.contains("09:41"))
        XCTAssertTrue(text.contains("America/Los_Angeles"))
        XCTAssertTrue(text.contains("en_US"))
        XCTAssertTrue(text.contains("2026-10-15 Thursday (today)"))
        XCTAssertTrue(text.contains("2026-10-16 Friday (tomorrow)"))
        // Weeks start on Monday: Sunday the 18th is still this week, Monday the 19th starts next week.
        XCTAssertTrue(text.contains("2026-10-18 Sunday\n"))
        XCTAssertTrue(text.contains("2026-10-19 Monday (next week)"))
        XCTAssertTrue(text.contains("2026-10-25 Sunday (next week)"))
        XCTAssertTrue(text.contains("2026-10-28 Wednesday\n"), "14th day is the last row")
        XCTAssertFalse(text.contains("2026-10-29"))
    }

    func testInstructionsAcrossYearEnd() {
        let text = CaptureDraftMapper.instructions(now: date(2026, 12, 30, 22), calendar: cal, localeIdentifier: "en_US")
        XCTAssertTrue(text.contains("2027-01-01 Friday"))
        XCTAssertTrue(text.contains("2027-01-04 Monday (next week)"))
    }

    // MARK: Keeping the user's words

    func testLabelledContentReplacesATranslatedTitle() {
        let line = "给我添加两个 reminder：\n\n1. 今天下午 4 点\n2. 今天晚上 8 点\n\n提醒内容：去走路，今天一定要走到 5 万步吧"
        XCTAssertEqual(CaptureDraftMapper.userWording("walk", source: line), "去走路，今天一定要走到 5 万步吧")
        XCTAssertEqual(CaptureDraftMapper.userWording("走路", source: line), "去走路，今天一定要走到 5 万步吧",
                       "a shortened copy of the labelled text becomes the full text")
    }

    func testTitleWithoutALabelIsKept() {
        XCTAssertEqual(CaptureDraftMapper.userWording("Call Alex", source: "call Alex tomorrow at 3pm"), "Call Alex")
        XCTAssertEqual(CaptureDraftMapper.userWording("walk", source: "明天早上 7 点去走路"), "walk")
        XCTAssertEqual(CaptureDraftMapper.labelledContent("Title: Dentist\nTomorrow 3pm"), "Dentist")
        XCTAssertNil(CaptureDraftMapper.labelledContent("Add a reminder: buy milk"), "“reminder:” introduces the request, not the title")
    }
}
