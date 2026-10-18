import XCTest
@testable import OneLogic

/// The Recents list on the Timer tab: newest first, no repeats, at most 20, presets while it is empty.
final class TimerRecentsTests: XCTestCase {
    private func r(_ seconds: Int, _ label: String? = nil) -> RecentTimer { RecentTimer(seconds: seconds, label: label) }

    func testAddingPutsTheNewestFirst() {
        var list: [RecentTimer] = []
        list = TimerRecents.adding(r(420), to: list)
        list = TimerRecents.adding(r(1200), to: list)
        list = TimerRecents.adding(r(1200, "go to lion market"), to: list)
        XCTAssertEqual(list.map(\.seconds), [1200, 1200, 420])
        XCTAssertEqual(list.map(\.label), ["go to lion market", nil, nil])
    }

    func testSameLengthAndNameMovesUpInsteadOfRepeating() {
        var list = [r(600), r(1200), r(420)]
        list = TimerRecents.adding(r(420), to: list)
        XCTAssertEqual(list.map(\.seconds), [420, 600, 1200])
        list = TimerRecents.adding(r(420, "Tea"), to: list)
        XCTAssertEqual(list.count, 4, "the same length with another name is another recent")
        list = TimerRecents.adding(r(420, "  Tea "), to: list)
        XCTAssertEqual(list.count, 4, "a trimmed name is the same name")
    }

    func testBlankNameIsNoName() {
        XCTAssertNil(r(60, "   ").label)
        XCTAssertEqual(r(60, "  ").id, r(60).id)
    }

    func testCapKeepsTheNewestTwenty() {
        var list: [RecentTimer] = []
        for minutes in 1...25 { list = TimerRecents.adding(r(minutes * 60), to: list) }
        XCTAssertEqual(list.count, TimerRecents.cap)
        XCTAssertEqual(TimerRecents.cap, 20)
        XCTAssertEqual(list.first?.seconds, 25 * 60)
        XCTAssertEqual(list.last?.seconds, 6 * 60, "the oldest five fell off")
    }

    func testZeroLengthIsNotRemembered() {
        XCTAssertEqual(TimerRecents.adding(r(0), to: [r(60)]), [r(60)])
    }

    func testRemoving() {
        let list = [r(420), r(1200, "market"), r(600)]
        XCTAssertEqual(TimerRecents.removing(id: r(1200, "market").id, from: list), [r(420), r(600)])
        XCTAssertEqual(TimerRecents.removing(id: "nope", from: list), list)
    }

    func testPresetsShowOnlyWhileTheListIsEmpty() {
        XCTAssertEqual(TimerRecents.presets.map(\.seconds), [1500, 300, 900])
        XCTAssertEqual(TimerRecents.presets.map(\.label), ["Focus", "Short break", "Long break"])
        XCTAssertEqual(TimerRecents.shown([]), TimerRecents.presets)
        XCTAssertEqual(TimerRecents.shown([r(420)]), [r(420)], "the user's own recents replace the presets")
    }

    func testRecordingFirstCustomTimerLeavesPresetsOut() {
        XCTAssertEqual(TimerRecents.recording(r(420), in: []), [r(420)])
    }

    func testRecordingAPresetKeepsAllThreeTogether() {
        let list = TimerRecents.recording(r(300, "Short break"), in: [])
        XCTAssertEqual(list.map(\.label), ["Short break", "Focus", "Long break"])
        XCTAssertEqual(TimerRecents.recording(r(420), in: list).map(\.seconds), [420, 300, 1500, 900])
    }

    func testCaptionAndSpokenStart() {
        XCTAssertEqual(TimerRecents.caption(r(420)), "7 min")
        XCTAssertEqual(TimerRecents.caption(r(3600)), "1 h")
        XCTAssertEqual(TimerRecents.caption(r(1200, "go to lion market")), "go to lion market")
        XCTAssertEqual(TimerRecents.startLabel(r(420)), "Start timer 7 minutes")
        XCTAssertEqual(TimerRecents.startLabel(r(5400, "have a rest")), "Start timer 1 hour 30 minutes, have a rest")
        XCTAssertEqual(TimerRecents.startLabel(r(30)), "Start timer 30 seconds")
    }

    func testStorageRoundTripAndCap() {
        let defaults = UserDefaults(suiteName: "TimerRecentsTests")!
        defaults.removePersistentDomain(forName: "TimerRecentsTests")
        XCTAssertEqual(TimerRecentsStore.load(defaults), [])
        let list = [r(420), r(1200, "market")]
        TimerRecentsStore.save(list, defaults)
        XCTAssertEqual(TimerRecentsStore.load(defaults), list)
        let long = (1...30).map { r($0 * 60) }
        TimerRecentsStore.save(long, defaults)
        XCTAssertEqual(TimerRecentsStore.load(defaults).count, TimerRecents.cap)
    }
}
