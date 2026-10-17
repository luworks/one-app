import XCTest
@testable import OneShared

final class ShareInboxTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    // Friday 16 Oct 2026, 22:17
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 22, minute: 17))!

    func testDraftFromTextAndLinks() {
        let a = ShareInbox.draft(text: "Buy oat milk\nthe barista one", url: nil, pageTitle: nil)
        XCTAssertEqual(a.title, "Buy oat milk")
        XCTAssertEqual(a.note, "the barista one")

        let url = URL(string: "https://www.example.com/a/b")!
        let b = ShareInbox.draft(text: nil, url: url, pageTitle: "How to fix a bike")
        XCTAssertEqual(b.title, "How to fix a bike")
        XCTAssertEqual(b.note, url.absoluteString)

        let c = ShareInbox.draft(text: url.absoluteString, url: url, pageTitle: nil)
        XCTAssertEqual(c.title, "example.com", "a bare link is named after its site")
        XCTAssertEqual(c.note, url.absoluteString)
    }

    func testDays() {
        func day(_ d: Date?) -> DateComponents? { d.map { cal.dateComponents([.month, .day, .hour], from: $0) } }
        XCTAssertNil(ShareInbox.due(for: .none, now: now, calendar: cal))
        XCTAssertEqual(day(ShareInbox.due(for: .today, now: now, calendar: cal)), DateComponents(month: 10, day: 16, hour: 0))
        XCTAssertEqual(day(ShareInbox.due(for: .tomorrow, now: now, calendar: cal)), DateComponents(month: 10, day: 17, hour: 0))
        XCTAssertEqual(day(ShareInbox.due(for: .nextWeek, now: now, calendar: cal)), DateComponents(month: 10, day: 19, hour: 0))
    }

    func testAppendThenDrainEmptiesTheInbox() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-inbox-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(ShareInbox.append(SharedReminder(title: "One", sharedAt: now), at: url))
        XCTAssertTrue(ShareInbox.append(SharedReminder(title: "Two", due: now, sharedAt: now.addingTimeInterval(5)), at: url))
        XCTAssertEqual(ShareInbox.drain(at: url).map(\.title), ["One", "Two"])
        XCTAssertEqual(ShareInbox.drain(at: url), [], "taken once")
    }
}
