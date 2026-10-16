import XCTest
@testable import OneLogic

/// Which Reminders list a new task is filed in. Weak or ambiguous evidence must leave it in the Inbox.
final class ListGuessTests: XCTestCase {
    /// Shaped like a real setup: numbered GTD lists plus area lists, with titles in Chinese and English.
    let lists: [ListGuess.Candidate] = [
        .init(name: "00 收件箱", titles: ["买牛奶", "看一下周末天气"]),
        .init(name: "财务与证件", titles: [
            "发送$750 invoice 和后期$1000invoice 直接给自己的mercury账户吧 或者boa等 自己用的。 提示我",
            "alden 打字练习 typing.com 每天带他1个小时 收拾书包 Reading and focus improve",
            "交水电费 10 月",
            "Pay credit card",
        ]),
        .init(name: "健康", titles: ["跑步 30 分钟", "预约牙医"]),
        .init(name: "Travel", titles: ["Book flights to Tokyo"]),
    ]

    func testInboxIsFound() {
        XCTAssertEqual(ListGuess.inbox(in: lists.map(\.name)), "00 收件箱")
        XCTAssertEqual(ListGuess.inbox(in: ["Work", "Inbox"]), "Inbox")
        XCTAssertNil(ListGuess.inbox(in: ["Work", "Home"]))
    }

    func testWalkIsNeverFiledUnderFinance() {
        for title in ["walk", "去走路，今天一定要走到 5 万步吧", "走路"] {
            let r = ListGuess.guess(title, lists: lists)
            XCTAssertNotEqual(r.list, "财务与证件", title)
            XCTAssertNil(r.list, "no list is a confident match for “\(title)”: it stays in the Inbox")
        }
    }

    func testNearCopyOfAnExistingTaskIsFiled() {
        XCTAssertEqual(ListGuess.guess("交水电费", lists: lists).list, "财务与证件")
        XCTAssertEqual(ListGuess.guess("Pay credit card bill", lists: lists).list, "财务与证件")
    }

    func testListNameInTheTitleIsFiled() {
        let r = ListGuess.guess("Buy travel insurance", lists: lists)
        XCTAssertEqual(r.list, "Travel")
        XCTAssertGreaterThanOrEqual(r.confidence, ListGuess.threshold)
    }

    func testOneSharedWordIsNotEnough() {
        // "invoice" alone appears in a finance task, but one common word is chance, not evidence.
        XCTAssertNil(ListGuess.guess("Ask Sam about the invoice template design", lists: lists).list)
        XCTAssertNil(ListGuess.guess("今天晚上提醒我一下", lists: lists).list, "only filler words")
    }

    func testAmbiguousStaysInInbox() {
        let two: [ListGuess.Candidate] = [
            .init(name: "Work travel", titles: []),
            .init(name: "Family travel", titles: []),
        ]
        let r = ListGuess.guess("Plan travel", lists: two)
        XCTAssertNil(r.list)
        XCTAssertEqual(r.confidence, 0)
    }

    func testTheInboxIsNotAGuess() {
        // A title like one already in the Inbox still goes to the Inbox via the fallback, not as a confident guess.
        XCTAssertNil(ListGuess.guess("买牛奶", lists: lists).list)
    }

    func testTokens() {
        XCTAssertEqual(ListGuess.tokens("Pay bills"), ["pay", "bill"])
        XCTAssertEqual(ListGuess.tokens("交水电费"), ["交水", "水电", "电费"])
        XCTAssertFalse(ListGuess.tokens("今天去走路").contains("今天"))
    }
}
