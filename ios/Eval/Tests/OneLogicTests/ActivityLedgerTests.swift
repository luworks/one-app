import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

/// The changes ledger on the Activity store: mapping, the one-time import of the old SwiftData rows, and the queries the
/// Activity screen, Undo and the autonomy policy use.
final class ActivityLedgerTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func legacy(_ n: Int, action: LedgerAction = .planned, actor: LedgerActor = .todayAI, ago: TimeInterval? = nil,
                        undoOf: UUID? = nil, snapshot: Data? = nil, id: UUID = UUID()) -> LegacyLedgerRow {
        LegacyLedgerRow(id: id, date: now.addingTimeInterval(-(ago ?? Double(n) * 60)), actor: actor.raw, channel: LedgerChannel.ask.rawValue,
                        action: action.rawValue, itemKind: "task", itemRef: "ref\(n)", title: "Task \(n)", before: "Not planned",
                        after: "Today 10:00", approval: LedgerApproval.asked.rawValue,
                        beforeDate: nil, afterDate: now.addingTimeInterval(3600), snapshot: snapshot, undoOf: undoOf)
    }

    func testItemRoundTripsThroughAnEvent() {
        var item = LedgerItem(date: now, actor: .todayAI, channel: .automatic, action: .moved, itemKind: "task", title: "買牛奶",
                              before: "Today 09:00", after: "Today 11:00", approval: .autoUnderGrant)
        item.itemRef = "{\"id\":1}"
        item.beforeDate = now
        item.afterDate = now.addingTimeInterval(7200)
        item.undoOf = UUID()
        let event = item.event(snapshot: Data([1, 2]), calendar: cal)
        XCTAssertEqual(event.kind, "change.moved")
        XCTAssertEqual(event.tier, 1)
        XCTAssertEqual(event.channel, "automatic", "the store keeps a slug, not the display name")
        XCTAssertEqual(event.approval, "auto")
        XCTAssertEqual(event.uid, item.id.uuidString)
        var back = LedgerItem(event: event)
        XCTAssertFalse(back.hasSnapshot, "hasSnapshot is a read-side flag set by the store")
        back.hasSnapshot = false
        XCTAssertEqual(back, item)
    }

    func testGrantsUseTheGrantKindAndEveryActionRoundTrips() {
        for action in [LedgerAction.created, .completed, .reopened, .deleted, .planned, .moved, .unscheduled, .redated, .undone, .granted, .revoked] {
            let item = LedgerItem(date: now, actor: .you, channel: .app, action: action, itemKind: action == .granted ? "grant" : "task",
                                  title: "x", approval: .userMade)
            let e = item.event()
            XCTAssertEqual(e.kind.hasPrefix(action == .granted || action == .revoked ? "grant." : "change."), true, e.kind)
            XCTAssertEqual(LedgerItem(event: e).actionValue, action)
        }
        for c in LedgerChannel.allCases { XCTAssertEqual(LedgerChannel(slug: c.slug), c) }
    }

    func testImportCopiesEverythingOnceAndNeverTwice() throws {
        let store = try ActivityStore(location: .memory)
        let snapshot = Data("{\"title\":\"x\"}".utf8)
        let rows = (0..<1_203).map { legacy($0, snapshot: $0 == 7 ? snapshot : nil) }
        let fetch: (Int, Int) -> [LegacyLedgerRow] = { o, l in Array(rows[min(o, rows.count)..<min(o + l, rows.count)]) }

        let first = try LedgerImport.run(into: store, total: rows.count, session: "S1", fetch: fetch)
        XCTAssertEqual(first, LedgerImport.Outcome(legacyTotal: 1_203, imported: 1_203, alreadyThere: 0, verified: true))
        XCTAssertTrue(LedgerImport.isMigrated(store))
        XCTAssertEqual(try store.count(), 1_203)
        XCTAssertEqual(try store.snapshot(uid: rows[7].id.uuidString), snapshot, "deleted reminders keep their Undo snapshot")

        let second = try LedgerImport.run(into: store, total: rows.count, session: "S2", fetch: fetch)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.alreadyThere, 1_203)
        XCTAssertEqual(try store.count(), 1_203, "idempotent")
    }

    func testDryRunWritesNothingAndSaysWhatWouldHappen() throws {
        let store = try ActivityStore(location: .memory)
        let rows = (0..<10).map { legacy($0) }
        try store.insert(Array(rows.prefix(4)).map(\.event))
        let out = try LedgerImport.run(into: store, total: rows.count, session: "S1", dryRun: true) { o, l in Array(rows[min(o, 10)..<min(o + l, 10)]) }
        XCTAssertEqual(out.imported, 6, "six are new")
        XCTAssertEqual(out.alreadyThere, 4)
        XCTAssertFalse(out.verified)
        XCTAssertEqual(try store.count(), 4, "nothing was written")
        XCTAssertFalse(LedgerImport.isMigrated(store))
    }

    func testAnInterruptedImportResumesWithoutDuplicates() throws {
        let store = try ActivityStore(location: .memory)
        let rows = (0..<900).map { legacy($0) }
        try store.insert(Array(rows.prefix(500)).map(\.event))   // a first run that stopped after one batch
        let out = try LedgerImport.run(into: store, total: rows.count, session: "S1") { o, l in Array(rows[min(o, 900)..<min(o + l, 900)]) }
        XCTAssertEqual(out.imported, 400)
        XCTAssertTrue(out.verified)
        XCTAssertEqual(try store.count(), 900)
    }

    func testAShortFetchDoesNotMarkTheImportDone() throws {
        let store = try ActivityStore(location: .memory)
        let rows = (0..<10).map { legacy($0) }
        // The old store claims 10 rows but only returns 6: not verified, so the next launch tries again.
        let out = try LedgerImport.run(into: store, total: 10, session: "S1") { o, l in Array(rows[min(o, 6)..<min(o + l, 6)]) }
        XCTAssertFalse(out.verified)
        XCTAssertFalse(LedgerImport.isMigrated(store))
    }

    func testOldRowsMayBeRemovedOnlyInALaterLaunchAfterAVerifiedCopy() throws {
        let store = try ActivityStore(location: .memory)
        XCTAssertFalse(LedgerImport.mayRemoveLegacy(store, session: "S1"), "nothing imported yet")
        _ = try LedgerImport.run(into: store, total: 0, session: "S1") { _, _ in [] }
        XCTAssertTrue(LedgerImport.isMigrated(store))
        XCTAssertFalse(LedgerImport.mayRemoveLegacy(store, session: "S1"), "not in the launch that made the copy")
        XCTAssertTrue(LedgerImport.mayRemoveLegacy(store, session: "S2"))
        try store.setMeta(LedgerImport.legacyRemovedKey, "1")
        XCTAssertFalse(LedgerImport.mayRemoveLegacy(store, session: "S3"), "only once")
    }

    func testImportedRowsReadBackAsTheOriginalLedgerLines() throws {
        let store = try ActivityStore(location: .memory)
        let original = UUID()
        let rows = [legacy(1, action: .planned, id: original), legacy(2, action: .undone, actor: .you, undoOf: original),
                    legacy(3, action: .deleted, actor: .you, snapshot: Data("s".utf8))]
        _ = try LedgerImport.run(into: store, total: 3, session: "S") { o, l in Array(rows[min(o, 3)..<min(o + l, 3)]) }
        let items = try store.page(ActivityQuery(tiers: [.changes]), limit: 10).map { LedgerItem(event: $0) }
        let undo = try XCTUnwrap(items.first { $0.actionValue == .undone })
        XCTAssertEqual(undo.undoOf, original)
        XCTAssertEqual(try store.undone(among: [original.uuidString]), [original.uuidString], "the Undone label survives the import")
        let deleted = try XCTUnwrap(items.first { $0.actionValue == .deleted })
        XCTAssertTrue(deleted.hasSnapshot)
        let planned = try XCTUnwrap(items.first { $0.id == original })
        XCTAssertEqual(planned.before, "Not planned")
        XCTAssertEqual(planned.channel, LedgerChannel.ask.rawValue)
        XCTAssertEqual(planned.approvalValue, .asked)
        XCTAssertEqual(planned.actorValue, .todayAI)
        XCTAssertEqual(planned.itemRef, "ref1")
        XCTAssertEqual(planned.afterDate, rows[0].afterDate, "the planned time Undo restores survives (to the millisecond)")
    }

    func testUnknownLegacyStringsAreKeptAsTheyAre() {
        var row = legacy(1)
        row.action = "someFutureAction"
        row.channel = "Some channel"
        row.approval = "weird"
        let item = row.item
        XCTAssertEqual(item.action, "someFutureAction")
        XCTAssertEqual(item.channel, "Some channel")
        XCTAssertEqual(item.approval, "weird")
        XCTAssertEqual(LedgerItem(event: row.event).action, "someFutureAction")
    }
}
