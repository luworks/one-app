import XCTest
@testable import OneLogic

final class WorldClockTests: XCTestCase {
    private func tz(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    /// 2026-10-17 12:00 UTC (no DST change nearby).
    private let noonUTC = Date(timeIntervalSince1970: 1_792_238_400)

    func testCityNames() {
        XCTAssertEqual(WorldClock.cityName(fromIdentifier: "America/New_York"), "New York")
        XCTAssertEqual(WorldClock.cityName(fromIdentifier: "America/Argentina/Buenos_Aires"), "Buenos Aires")
        XCTAssertEqual(WorldClock.cityName(fromIdentifier: "Europe/London"), "London")
        XCTAssertEqual(WorldClock.cityName(fromIdentifier: "Asia/Kolkata"), "Kolkata")
        XCTAssertNil(WorldClock.cityName(fromIdentifier: "UTC"))
        XCTAssertNil(WorldClock.cityName(fromIdentifier: "GMT"))
        XCTAssertNil(WorldClock.cityName(fromIdentifier: "Etc/GMT+5"))
        XCTAssertNil(WorldClock.cityName(fromIdentifier: "US/Pacific"))
    }

    func testCitiesAreSortedAndSearchable() {
        let all = WorldClock.cities(from: TimeZone.knownTimeZoneIdentifiers)
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.map(\.name), all.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertFalse(all.contains { $0.identifier == "UTC" })
        let tokyo = WorldClock.search("tok", in: all)
        XCTAssertEqual(tokyo.first?.identifier, "Asia/Tokyo")
        XCTAssertEqual(WorldClock.search("new york", in: all).first?.identifier, "America/New_York")
        XCTAssertEqual(WorldClock.search("  ", in: all).count, all.count, "empty search lists every city")
        let par = WorldClock.search("Par", in: all)
        XCTAssertTrue(par.first?.name.hasPrefix("Par") == true, "names starting with the query come first")
        XCTAssertTrue(par.contains { $0.identifier == "Europe/Paris" })
        XCTAssertTrue(WorldClock.search("sao paulo", in: all).contains { $0.identifier == "America/Sao_Paulo" }, "accents and underscores don't matter")
    }

    func testOffsets() {
        let la = tz("America/Los_Angeles")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/New_York"), local: la, at: noonUTC), "+3 hrs")
        XCTAssertEqual(WorldClock.offsetText(zone: la, local: la, at: noonUTC), "+0 hrs")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/Denver"), local: la, at: noonUTC), "+1 hr")
        XCTAssertEqual(WorldClock.offsetText(zone: la, local: tz("America/New_York"), at: noonUTC), "-3 hrs")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("Asia/Kolkata"), local: tz("Europe/London"), at: noonUTC), "+4:30 hrs", "London is on BST in October")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("Asia/Kathmandu"), local: tz("UTC"), at: noonUTC), "+5:45 hrs")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/St_Johns"), local: tz("UTC"), at: noonUTC), "-2:30 hrs", "Newfoundland daylight time")
    }

    func testOffsetFollowsDaylightSavingAtThatMoment() {
        // 2026-01-15 12:00 UTC: London on GMT, so New York is -5.
        let january = Date(timeIntervalSince1970: 1_768_478_400)
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/New_York"), local: tz("Europe/London"), at: january), "-5 hrs")
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/New_York"), local: tz("Europe/London"), at: noonUTC), "-5 hrs")
        // Between Europe's and America's switch (2026-03-20 12:00 UTC): the US moved on Mar 8, Europe moves on Mar 29.
        let march = Date(timeIntervalSince1970: 1_774_008_000)
        XCTAssertEqual(WorldClock.offsetText(zone: tz("America/New_York"), local: tz("Europe/London"), at: march), "-4 hrs")
    }

    func testDayLabelsAcrossTheDateLine() {
        // 2026-10-17 20:00 in Los Angeles = 23:00 in New York (same day), 12:00 next day in Tokyo.
        let evening = Date(timeIntervalSince1970: 1_792_292_400)
        let la = tz("America/Los_Angeles")
        XCTAssertEqual(WorldClock.subtitle(zone: tz("America/New_York"), local: la, at: evening), "Today, +3 hrs")
        XCTAssertEqual(WorldClock.subtitle(zone: tz("Asia/Tokyo"), local: la, at: evening), "Tomorrow, +16 hrs")
        // Tokyo at 08:00 on Oct 18 (Oct 17 23:00 UTC): Honolulu is still at 13:00 on Oct 17.
        let tokyoMorning = Date(timeIntervalSince1970: 1_792_278_000)
        XCTAssertEqual(WorldClock.subtitle(zone: tz("Pacific/Honolulu"), local: tz("Asia/Tokyo"), at: tokyoMorning), "Yesterday, -19 hrs")
        // New Year's Eve: across a year boundary.
        let newYear = Date(timeIntervalSince1970: 1_798_768_800)   // 2027-01-01 02:00 UTC
        XCTAssertEqual(WorldClock.dayLabel(zone: tz("Europe/London"), local: tz("America/Los_Angeles"), at: newYear), "Tomorrow")
    }

    func testHourMinuteInZone() {
        let (h, m) = WorldClock.hourMinute(zone: tz("Asia/Kolkata"), at: noonUTC)
        XCTAssertEqual(h, 17)
        XCTAssertEqual(m, 30)
    }

    func testSavedList() {
        var list = WorldClock.adding("Europe/London", to: [])
        list = WorldClock.adding("Asia/Tokyo", to: list)
        list = WorldClock.adding("Europe/London", to: list)
        XCTAssertEqual(list, ["Europe/London", "Asia/Tokyo"], "no duplicates")
        list = WorldClock.adding("America/New_York", to: list)
        XCTAssertEqual(WorldClock.moving(list, from: [2], to: 0), ["America/New_York", "Europe/London", "Asia/Tokyo"])
        XCTAssertEqual(WorldClock.moving(list, from: [0], to: 3), ["Asia/Tokyo", "America/New_York", "Europe/London"])
        XCTAssertEqual(WorldClock.moving(list, from: [0], to: 1), list, "moving onto itself changes nothing")
        XCTAssertEqual(WorldClock.load(["Europe/London", "Mars/Olympus_Mons"], known: Set(TimeZone.knownTimeZoneIdentifiers)), ["Europe/London"])
        XCTAssertEqual(WorldClock.load(nil, known: []), [])
    }
}

final class StopwatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartStopAccumulates() {
        var s = StopwatchState()
        XCTAssertFalse(s.hasTime)
        s.start(at: t0)
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5)), 5, accuracy: 0.0001)
        s.stop(at: t0.addingTimeInterval(5))
        XCTAssertFalse(s.isRunning)
        XCTAssertTrue(s.hasTime, "stopped with time: the left button reads Reset")
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(100)), 5, accuracy: 0.0001, "no time passes while stopped")
        s.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(102.5)), 7.5, accuracy: 0.0001)
        s.start(at: t0.addingTimeInterval(200))   // ignored while running
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(102.5)), 7.5, accuracy: 0.0001)
    }

    func testLapsAndCurrentLap() {
        var s = StopwatchState()
        s.lap(at: t0)
        XCTAssertTrue(s.laps.isEmpty, "Lap does nothing while stopped")
        s.start(at: t0)
        s.lap(at: t0.addingTimeInterval(3))
        s.lap(at: t0.addingTimeInterval(10))
        XCTAssertEqual(s.laps, [3, 7])
        XCTAssertEqual(s.currentLap(at: t0.addingTimeInterval(12)), 2, accuracy: 0.0001)
        s.stop(at: t0.addingTimeInterval(12))
        XCTAssertEqual(s.currentLap(at: t0.addingTimeInterval(50)), 2, accuracy: 0.0001)
        s.reset()
        XCTAssertEqual(s, StopwatchState())
    }

    func testBestAndWorstNeedTwoDifferentLaps() {
        var s = StopwatchState()
        XCTAssertNil(s.bestLapIndex)
        s.laps = [4]
        XCTAssertNil(s.bestLapIndex, "one lap: nothing to compare")
        XCTAssertNil(s.worstLapIndex)
        s.laps = [4, 4]
        XCTAssertNil(s.bestLapIndex, "equal laps are neither best nor worst")
        s.laps = [4, 2.5, 9, 3]
        XCTAssertEqual(s.bestLapIndex, 1)
        XCTAssertEqual(s.worstLapIndex, 2)
    }

    func testFormat() {
        XCTAssertEqual(StopwatchState.format(0), "00:00.00")
        XCTAssertEqual(StopwatchState.format(1.239), "00:01.23", "truncates, never rounds up")
        XCTAssertEqual(StopwatchState.format(65.5), "01:05.50")
        XCTAssertEqual(StopwatchState.format(3599.999), "59:59.99")
        XCTAssertEqual(StopwatchState.format(3723.45), "1:02:03.45")
        XCTAssertEqual(StopwatchState.format(-3), "00:00.00")
    }

    func testPersistenceKeepsRunningAcrossRelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StopwatchTests-\(UUID())"))
        var s = StopwatchState()
        s.start(at: t0)
        s.lap(at: t0.addingTimeInterval(4))
        s.save(to: defaults)
        // "Relaunch": a fresh load an hour later still counts from the saved start date.
        let loaded = StopwatchState.load(from: defaults)
        XCTAssertEqual(loaded, s)
        XCTAssertTrue(loaded.isRunning)
        XCTAssertEqual(loaded.elapsed(at: t0.addingTimeInterval(3600)), 3600, accuracy: 0.0001)
        XCTAssertEqual(loaded.laps, [4])
        // Reset clears the saved state.
        var cleared = loaded
        cleared.reset()
        cleared.save(to: defaults)
        XCTAssertNil(defaults.data(forKey: StopwatchState.defaultsKey))
        XCTAssertEqual(StopwatchState.load(from: defaults), StopwatchState())
    }

    func testCorruptSavedDataStartsClean() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StopwatchTests-\(UUID())"))
        defaults.set(Data("not json".utf8), forKey: StopwatchState.defaultsKey)
        XCTAssertEqual(StopwatchState.load(from: defaults), StopwatchState())
    }
}
