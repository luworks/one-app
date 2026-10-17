import XCTest
@testable import OneLogic

final class ReminderSuggestTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    // Friday 16 Oct 2026, 18:00
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 18, minute: 0))!

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: -daysAgo, to: now)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    private func past(_ title: String, daysAgo: Int, hour: Int, dueHour: Int? = nil, open: Bool = false) -> ReminderSuggest.Past {
        let created = at(daysAgo: daysAgo, hour: hour)
        let due = dueHour.map { cal.date(bySettingHour: $0, minute: 30, second: 0, of: created)! }
        return .init(title: title, createdAt: created, due: due, isOpen: open)
    }

    func testHabitsAtThisTimeOfDayComeFirstWithTheirUsualTime() {
        let history = [
            past("Water the plants", daysAgo: 7, hour: 18, dueHour: 18),
            past("Water the plants", daysAgo: 14, hour: 18, dueHour: 18),
            past("Water the plants", daysAgo: 21, hour: 17, dueHour: 18),
            past("Buy coffee beans", daysAgo: 3, hour: 9),
            past("Buy coffee beans", daysAgo: 10, hour: 8),
            past("One-off thing", daysAgo: 1, hour: 18),
        ]
        let s = ReminderSuggest.suggest(from: history, now: now, calendar: cal)
        XCTAssertEqual(s.first?.title, "Water the plants", "weekly at this hour on Fridays")
        XCTAssertEqual(s.first?.when.map { cal.dateComponents([.day, .hour, .minute], from: $0) },
                       DateComponents(day: 16, hour: 18, minute: 30), "today at the usual time")
        XCTAssertTrue(s.contains { $0.title == "Buy coffee beans" && $0.when == nil }, "no usual time: no time")
        XCTAssertFalse(s.contains { $0.title == "One-off thing" }, "a one-off is not a habit")
    }

    func testWhatIsAlreadyOpenIsNotSuggested() {
        let history = [
            past("Call mom", daysAgo: 7, hour: 18), past("Call mom", daysAgo: 14, hour: 18),
            past("Call mom", daysAgo: 0, hour: 17, open: true),
        ]
        XCTAssertTrue(ReminderSuggest.suggest(from: history, now: now, calendar: cal).isEmpty)
    }

    func testAPassedUsualTimeMovesToTomorrowAndTheListIsCapped() {
        var history = [past("Morning run", daysAgo: 1, hour: 6, dueHour: 6), past("Morning run", daysAgo: 2, hour: 6, dueHour: 6)]
        for i in 0..<6 { history += [past("Task \(i)", daysAgo: 1, hour: 12), past("Task \(i)", daysAgo: 2, hour: 12)] }
        let s = ReminderSuggest.suggest(from: history, now: now, calendar: cal)
        XCTAssertEqual(s.count, 4)
        let run = ReminderSuggest.suggest(from: Array(history.prefix(2)), now: now, calendar: cal).first
        XCTAssertEqual(run?.when.map { cal.dateComponents([.day, .hour], from: $0) }, DateComponents(day: 17, hour: 6))
    }
}
