import XCTest
@testable import OneLogic

final class TimerListTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func timer(_ seconds: Int, label: String? = nil, source: TimerSource = .voice, start: Date? = nil) -> RunningTimer {
        RunningTimer.start(id: UUID(), seconds: seconds, now: start ?? t0, label: label, source: source)
    }

    // MARK: Rows

    func testRowsOrderRingingThenSoonestThenPaused() {
        let long = timer(900), soon = timer(60), paused = timer(30).paused(now: t0), done = timer(10)
        let order = TimerList.ordered([paused, long, soon, done], ringing: [done.id], now: t0)
        XCTAssertEqual(order.map(\.id), [done.id, soon.id, long.id, paused.id])
    }

    func testTwoRowsAndMore() {
        let a = timer(60), b = timer(120), c = timer(180), d = timer(240)
        let one = TimerList.rows([a], now: t0)
        XCTAssertEqual(one.shown.count, 1)
        XCTAssertEqual(one.more, 0)
        let four = TimerList.rows([d, c, b, a], now: t0)
        XCTAssertEqual(four.shown.map(\.id), [a.id, b.id])
        XCTAssertEqual(four.more, 2)
        XCTAssertEqual(TimerList.moreLabel(2), "+2 more")
        XCTAssertEqual(TimerList.rows([], now: t0).shown.count, 0)
    }

    func testTitles() {
        XCTAssertEqual(TimerList.title(timer(60)), "Timer")
        XCTAssertEqual(TimerList.title(timer(60, label: "Pasta")), "Pasta")
        XCTAssertEqual(TimerList.title(timer(60, label: "  ")), "Timer", "a blank name is no name")
        XCTAssertEqual(TimerList.title(timer(1500, source: .card)), "Focus")
        let breakTimer = RunningTimer.start(id: UUID(), seconds: 300, now: t0, phase: .shortBreak, source: .card)
        XCTAssertEqual(TimerList.title(breakTimer), "Break")
        XCTAssertEqual(TimerList.title(timer(300, label: "Tea", source: .card)), "Tea")
    }

    func testFormatting() {
        XCTAssertEqual(TimerList.totalText(600), "10 min")
        XCTAssertEqual(TimerList.totalText(5400), "1 h 30 min")
        XCTAssertEqual(TimerList.totalText(3600), "1 h")
        XCTAssertEqual(TimerList.totalText(45), "45 s")
        XCTAssertEqual(TimerList.totalText(90), "1 min 30 s")
        XCTAssertEqual(TimerList.clock(0), "0:00")
        XCTAssertEqual(TimerList.clock(75), "1:15")
        XCTAssertEqual(TimerList.clock(74.2), "1:15", "rounds up like the dial")
        XCTAssertEqual(TimerList.clock(3725), "1:02:05")
    }

    func testSpoken() {
        let pasta = timer(600, label: "Pasta")
        XCTAssertEqual(TimerList.spoken(pasta, ringing: false, now: t0), "Pasta, 10 minutes 0 seconds left")
        XCTAssertEqual(TimerList.spoken(pasta.paused(now: t0.addingTimeInterval(60)), ringing: false, now: t0),
                       "Pasta, paused, 9 minutes 0 seconds left")
        XCTAssertEqual(TimerList.spoken(pasta, ringing: true, now: t0), "Pasta, ringing")
    }

    func testSpokenRemainingForTheTimerTabCards() {
        let plain = timer(420)
        XCTAssertEqual(TimerList.spokenRemaining(plain, ringing: false, now: t0), "Timer 7 minutes, 0 seconds remaining")
        let pasta = timer(65, label: "Pasta")
        XCTAssertEqual(TimerList.spokenRemaining(pasta, ringing: false, now: t0), "Pasta 1 minute, 5 seconds remaining")
        XCTAssertEqual(TimerList.spokenRemaining(pasta.paused(now: t0.addingTimeInterval(5)), ringing: false, now: t0),
                       "Pasta, paused, 1 minute, 0 seconds remaining")
        XCTAssertEqual(TimerList.spokenRemaining(timer(45), ringing: false, now: t0), "Timer 45 seconds remaining")
        XCTAssertEqual(TimerList.spokenRemaining(timer(3725), ringing: false, now: t0), "Timer 1 hour, 2 minutes, 5 seconds remaining")
        XCTAssertEqual(TimerList.spokenRemaining(timer(3600), ringing: false, now: t0), "Timer 1 hour, 0 minutes, 0 seconds remaining")
        XCTAssertEqual(TimerList.spokenRemaining(pasta, ringing: true, now: t0), "Pasta, ringing")
    }

    // MARK: Adding

    func testCardTimerReplacesCardTimerButNotVoiceTimers() {
        let voice = timer(600, label: "Pasta")
        let card1 = timer(1500, source: .card)
        let card2 = timer(300, source: .card)
        var list = TimerList.adding(card1, to: [voice])
        XCTAssertEqual(list.map(\.id), [voice.id, card1.id])
        list = TimerList.adding(card2, to: list)
        XCTAssertEqual(list.map(\.id), [voice.id, card2.id], "one Focus/break at a time")
        let another = timer(120, label: "Tea")
        list = TimerList.adding(another, to: list)
        XCTAssertEqual(list.count, 3, "voice timers run side by side")
    }

    func testSameIDIsReplacedNotDuplicated() {
        let a = timer(60)
        let list = TimerList.adding(a.paused(now: t0), to: [a])
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].isPaused)
    }

    // MARK: Reconcile with AlarmKit

    func testStartedByIntentWhileAppWasClosedIsKept() {
        // The intent saved the timer to the store; AlarmKit has it running: the next launch shows it.
        let intentTimer = timer(600, label: "Pasta")
        let result = TimerList.reconcile(local: [intentTimer], live: [intentTimer.id: .running], now: t0.addingTimeInterval(30))
        XCTAssertEqual(result.timers, [intentTimer])
        XCTAssertTrue(result.finished.isEmpty)
        XCTAssertTrue(result.ringing.isEmpty)
    }

    func testRanToEndAndGoneIsFinished() {
        let a = timer(60)
        let result = TimerList.reconcile(local: [a], live: [:], now: t0.addingTimeInterval(61))
        XCTAssertTrue(result.timers.isEmpty)
        XCTAssertEqual(result.finished, [a], "stopped on the Lock Screen after it rang")
    }

    func testCancelledEarlyIsDroppedAndNotFinished() {
        let a = timer(600)
        let result = TimerList.reconcile(local: [a], live: [:], now: t0.addingTimeInterval(60))
        XCTAssertTrue(result.timers.isEmpty)
        XCTAssertTrue(result.finished.isEmpty, "cancelled from the Lock Screen: no round, no finish")
    }

    func testRingingFinishesButStays() {
        let a = timer(60), b = timer(900)
        let result = TimerList.reconcile(local: [a, b], live: [a.id: .ringing, b.id: .running], now: t0.addingTimeInterval(61))
        XCTAssertEqual(result.timers.map(\.id), [a.id, b.id])
        XCTAssertEqual(result.finished.map(\.id), [a.id])
        XCTAssertEqual(result.ringing, [a.id])
    }

    func testPauseAndResumeOutsideTheAppAreFollowed() {
        let a = timer(600), b = timer(600).paused(now: t0)
        let now = t0.addingTimeInterval(100)
        let result = TimerList.reconcile(local: [a, b], live: [a.id: .paused, b.id: .running], now: now)
        XCTAssertTrue(result.timers[0].isPaused)
        XCTAssertEqual(result.timers[0].remaining(now: now.addingTimeInterval(500)), 500, "paused time does not run")
        XCTAssertFalse(result.timers[1].isPaused)
        XCTAssertEqual(result.timers[1].endsAt, now.addingTimeInterval(600))
    }

    func testAlarmKitTimersWeNeverStoredAreIgnored() {
        let known = timer(60)
        let result = TimerList.reconcile(local: [known], live: [known.id: .running, UUID(): .running], now: t0)
        XCTAssertEqual(result.timers, [known])
    }

    // MARK: Storage

    func testFocusLifecycleSurvivesRelaunchAndCountsRingingThenStoppedOnce() throws {
        let suite = "TimerLifecycle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let focus = timer(1500, label: "Focus", source: .card)
        let tea = timer(300, label: "Tea")
        TimerStore.save(TimerList.adding(focus, to: [tea]), defaults)

        let pausedAt = t0.addingTimeInterval(120)
        let paused = TimerList.reconcile(local: TimerStore.load(defaults),
                                         live: [focus.id: .paused, tea.id: .running], now: pausedAt)
        TimerStore.save(paused.timers, defaults)
        let reloaded = try XCTUnwrap(TimerStore.load(defaults).first { $0.id == focus.id })
        XCTAssertEqual(reloaded.remaining(now: t0.addingTimeInterval(2000)), 1380, "relaunch must not run down paused time")
        XCTAssertTrue(paused.finished.isEmpty)

        let resumedAt = t0.addingTimeInterval(2000)
        let resumed = TimerList.reconcile(local: TimerStore.load(defaults), live: [focus.id: .running], now: resumedAt)
        XCTAssertEqual(resumed.timers.map(\.id), [focus.id], "the unrelated expired timer leaves the list")
        XCTAssertEqual(resumed.finished.map(\.id), [tea.id])
        TimerStore.save(resumed.timers, defaults)
        let end = resumedAt.addingTimeInterval(1380)
        XCTAssertEqual(TimerStore.load(defaults).first?.endsAt, end)

        var log = PomodoroLog.empty(end)
        for live: [UUID: LiveTimerState] in [[focus.id: .ringing], [focus.id: .ringing], [:]] {
            let result = TimerList.reconcile(local: TimerStore.load(defaults), live: live, now: end)
            for completed in result.finished where completed.isCard {
                log = log.completing(completed.pomodoroPhase, id: completed.id, now: end)
            }
            PomodoroLog.save(log, defaults)
            log = PomodoroLog.load(defaults, now: end)
            TimerStore.save(result.timers, defaults)
            XCTAssertEqual(log.rounds, 1, "repeated ring updates and a later Stop must count one Focus round")
        }
        XCTAssertTrue(TimerStore.load(defaults).isEmpty)
        XCTAssertEqual(log.nextStep, .shortBreak)
    }

    func testStoreRoundTripAndMigration() {
        let defaults = UserDefaults(suiteName: "TimerListTests")!
        defaults.removePersistentDomain(forName: "TimerListTests")
        XCTAssertEqual(TimerStore.load(defaults), [])
        let a = timer(90, label: "Eggs")
        TimerStore.save([a], defaults)
        XCTAssertEqual(TimerStore.load(defaults), [a])

        // A single timer saved by an older version is carried over once.
        defaults.removePersistentDomain(forName: "TimerListTests")
        let legacy = RunningTimer.start(id: UUID(), seconds: 1500, now: t0)
        RunningTimer.save(legacy, defaults)
        XCTAssertEqual(TimerStore.load(defaults), [legacy])
        XCTAssertNil(RunningTimer.load(defaults), "the old key is gone")
        XCTAssertEqual(TimerStore.load(defaults), [legacy], "and the list is kept")
    }

    func testOldSavedTimerWithoutLabelOrSourceDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString)","total":300,"endsAt":0,"phase":"shortBreak"}"#
        let decoded = try JSONDecoder().decode(RunningTimer.self, from: Data(json.utf8))
        XCTAssertNil(decoded.label)
        XCTAssertTrue(decoded.isCard, "a timer saved before voice timers belongs to the card")
        XCTAssertEqual(decoded.pomodoroPhase, .shortBreak)
    }

    func testVoiceTimerHasNoPomodoroPhase() {
        let v = RunningTimer.start(id: UUID(), seconds: 600, now: t0, phase: .shortBreak, source: .voice)
        XCTAssertNil(v.phase)
        XCTAssertFalse(v.isCard)
    }
}

final class TimerPhraseTests: XCTestCase {
    private func s(_ text: String) -> Int? { TimerPhrase.seconds(from: text) }

    func testEnglishMinutes() {
        XCTAssertEqual(s("10 minutes"), 600)
        XCTAssertEqual(s("ten minutes"), 600)
        XCTAssertEqual(s("Ten Minutes"), 600)
        XCTAssertEqual(s("10 min"), 600)
        XCTAssertEqual(s("10m"), 600)
        XCTAssertEqual(s("a minute"), 60)
        XCTAssertEqual(s("twenty five minutes"), 1500)
        XCTAssertEqual(s("twenty-five minutes"), 1500)
        XCTAssertEqual(s("fifteen minutes"), 900)
        XCTAssertEqual(s("for 5 minutes please"), 300)
        XCTAssertEqual(s("set a timer for ten minutes"), 600)
    }

    func testEnglishHoursAndHalves() {
        XCTAssertEqual(s("an hour"), 3600)
        XCTAssertEqual(s("an hour and a half"), 5400)
        XCTAssertEqual(s("one and a half hours"), 5400)
        XCTAssertEqual(s("two and a half hours"), 9000)
        XCTAssertEqual(s("half an hour"), 1800)
        XCTAssertEqual(s("half hour"), 1800)
        XCTAssertEqual(s("a half hour"), 1800)
        XCTAssertEqual(s("1 hour 30 minutes"), 5400)
        XCTAssertEqual(s("1h30"), 5400)
        XCTAssertEqual(s("1h 30m"), 5400)
        XCTAssertEqual(s("a quarter of an hour"), 900)
        XCTAssertEqual(s("three quarters of an hour"), 2700)
        XCTAssertEqual(s("an hour and 15 minutes"), 4500)
    }

    func testSecondsAndBareNumbers() {
        XCTAssertEqual(s("90 seconds"), 90)
        XCTAssertEqual(s("thirty seconds"), 30)
        XCTAssertEqual(s("1 minute 30 seconds"), 90)
        XCTAssertEqual(s("45s"), 45)
        XCTAssertEqual(s("10"), 600, "a bare number is minutes")
        XCTAssertEqual(s("ten"), 600)
    }

    func testChinese() {
        XCTAssertEqual(s("十分钟"), 600)
        XCTAssertEqual(s("半小时"), 1800)
        XCTAssertEqual(s("半个小时"), 1800)
        XCTAssertEqual(s("一个半小时"), 5400)
        XCTAssertEqual(s("两个小时"), 7200)
        XCTAssertEqual(s("两小时"), 7200)
        XCTAssertEqual(s("二十五分钟"), 1500)
        XCTAssertEqual(s("三分钟"), 180)
        XCTAssertEqual(s("30分钟"), 1800)
        XCTAssertEqual(s("九十秒"), 90)
        XCTAssertEqual(s("一小时三十分钟"), 5400)
        XCTAssertEqual(s("一小时半"), 5400)
        XCTAssertEqual(s("一刻钟"), 900)
        XCTAssertEqual(s("半分钟"), 30)
        XCTAssertEqual(s("定时十分钟"), 600)
        XCTAssertEqual(s("十"), 600)
    }

    func testNoLengthIsNil() {
        XCTAssertNil(s(""))
        XCTAssertNil(s("   "))
        XCTAssertNil(s("set a timer"))
        XCTAssertNil(s("pasta"))
        XCTAssertNil(s("a"))
        XCTAssertNil(s("0 minutes"))
        XCTAssertNil(s("计时器"))
    }

    func testZhNumber() {
        XCTAssertEqual(TimerPhrase.zhNumber("十"), 10)
        XCTAssertEqual(TimerPhrase.zhNumber("十二"), 12)
        XCTAssertEqual(TimerPhrase.zhNumber("二十"), 20)
        XCTAssertEqual(TimerPhrase.zhNumber("九十"), 90)
        XCTAssertEqual(TimerPhrase.zhNumber("两"), 2)
        XCTAssertEqual(TimerPhrase.zhNumber("一百二十"), 120)
        XCTAssertEqual(TimerPhrase.zhNumber("45"), 45)
        XCTAssertNil(TimerPhrase.zhNumber("分钟"))
    }

    func testIntentRange() {
        XCTAssertEqual(IntentTimer.seconds(seconds: 600), 600)
        XCTAssertEqual(IntentTimer.seconds(seconds: 90 * 60), 5400)
        XCTAssertNil(IntentTimer.seconds(seconds: 0))
        XCTAssertEqual(IntentTimer.seconds(seconds: 90 * 60 + 1), 5401, "timers can exceed the former 90-minute limit")
        let maximum = 23 * 3600 + 59 * 60
        XCTAssertEqual(TimerDial.maxSeconds, maximum, "the product limit is 23 hours 59 minutes")
        XCTAssertEqual(IntentTimer.seconds(seconds: maximum), 86340, "the maximum duration is accepted")
        XCTAssertNil(IntentTimer.seconds(seconds: maximum + 1), "one second beyond 23 hours 59 minutes is rejected")
        XCTAssertEqual(IntentTimer.spoken(seconds: 600), "10 minutes")
        XCTAssertEqual(IntentTimer.spoken(seconds: 5400), "1 hour 30 minutes")
        XCTAssertEqual(IntentTimer.spoken(seconds: 1), "1 second")
        XCTAssertEqual(IntentTimer.label("  Pasta "), "Pasta")
        XCTAssertNil(IntentTimer.label(" "))
        XCTAssertNil(IntentTimer.label(nil))
    }
}
