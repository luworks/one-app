#if os(iOS)
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import One

/// Reads the finished baseline fixture using the actual production model module.
/// This target must use the Swift package identity ios to access package model members.
@MainActor
struct StoreUpgradeTests {
    @Test
    func baselineStorePreservesAllFieldsAcrossReopenAndMutation() throws {
        let fixture = try #require(Bundle.module.resourceURL)
            .appendingPathComponent("swiftdata-upgrade", isDirectory: true)
        let source = fixture.appendingPathComponent("old.store")
        let expectedFile = fixture.appendingPathComponent("expected.json")
        let frozenStore = try Data(contentsOf: source) // Missing resources fail; never create a fresh fixture.
        let frozenExpected = try Data(contentsOf: expectedFile)
        try #require(SHA256.hash(data: frozenStore).map { String(format: "%02x", $0) }.joined()
            == "c7ff329418508d67f1c7acd6d4eac44c45daec80a39282433cf049d2eeba751b")
        try #require(SHA256.hash(data: frozenExpected).map { String(format: "%02x", $0) }.joined()
            == "81c687e1bb70aed37f93bd85f809799db5ad37c87a647ecf99da317629c5b64a")
        let expected = try Self.bytes(JSONSerialization.jsonObject(with: frozenExpected))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("One-StoreUpgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        // Retain the entire candidate family and diagnostic snapshots, including on failure.
        // The test runner must collect this printed path into canonical tests/results evidence.
        print("StoreUpgradeTests retained candidate: \(directory.path)")
        let store = directory.appendingPathComponent("old.store")
        try FileManager.default.copyItem(at: source, to: store)
        try frozenExpected.write(to: directory.appendingPathComponent("baseline-expected.json"))

        try assertSnapshot(at: store, equals: expected, evidence: "first-open.json")
        try assertSnapshot(at: store, equals: expected, evidence: "second-open.json")
        let mutated = try mutate(at: store, expected: expected)
        try mutated.write(to: directory.appendingPathComponent("mutation-expected.json"))
        try assertSnapshot(at: store, equals: mutated, evidence: "mutation-reopened.json")
        try assertSnapshot(at: store, equals: mutated, evidence: "mutation-second-reopen.json")
        let unchangedStore = try Data(contentsOf: source)
        let unchangedExpected = try Data(contentsOf: expectedFile)
        try #require(unchangedStore == frozenStore)
        try #require(unchangedExpected == frozenExpected)
    }

    private static var schema: Schema {
        Schema([OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self,
                ChatThread.self, LedgerEntry.self, AIGrant.self, ShareImportReceipt.self])
    }

    private func open(_ store: URL) throws -> ModelContainer {
        // Check existence before SwiftData can silently create an empty database.
        try #require(FileManager.default.fileExists(atPath: store.path))
        let schema = Self.schema
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: store, allowsSave: true, cloudKitDatabase: .none)
        ])
    }

    private func assertSnapshot(at store: URL, equals expected: Data, evidence: String) throws {
        // No model, context or container escapes this scope into a later open.
        try autoreleasepool {
            let container = try open(store)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let actual = try Self.bytes(Self.snapshot(context))
            try actual.write(to: store.deletingLastPathComponent().appendingPathComponent(evidence))
            try #require(actual == expected, "Complete persisted snapshot mismatch; candidate and JSON evidence retained.")
        }
    }

    private func mutate(at store: URL, expected: Data) throws -> Data {
        try autoreleasepool {
            let container = try open(store)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let tasks = try context.fetch(FetchDescriptor<OneTask>())
            let task = try #require(tasks.first { $0.title == "Synthetic recurring work" })
            let planned = try #require(task.plannedStart)
            let deadline = task.due
            task.note = "Synthetic candidate edit"
            task.plannedStart = planned.addingTimeInterval(900)
            try #require(task.due == deadline, "Planned time changes must preserve the deadline.")
            try context.save()

            // Change only the two approved expected fields; all other old values/IDs must remain exact.
            let decodedDocument = try JSONSerialization.jsonObject(with: expected)
            var document = try #require(decodedDocument as? [String: Any])
            var rows = try #require(document["OneTask"] as? [[String: Any]])
            let index = try #require(rows.firstIndex { $0["title"] as? String == "Synthetic recurring work" })
            rows[index]["note"] = "Synthetic candidate edit"
            rows[index]["plannedStart"] = Self.json(planned.addingTimeInterval(900))
            document["OneTask"] = Self.sorted(rows)
            let changed = try Self.bytes(document)
            let actual = try Self.bytes(Self.snapshot(context))
            try actual.write(to: store.deletingLastPathComponent().appendingPathComponent("mutation-saved.json"))
            try #require(actual == changed, "Mutation changed additional baseline fields.")
            return changed
        }
    }

    static func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    static func json<T: Encodable>(_ value: T) -> Any {
        try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
    static func bytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    }
    static func sameID(_ a: PersistentIdentifier, _ b: PersistentIdentifier) -> Bool {
        // Compare the complete encoded identity, independently of SwiftData's backing representation.
        try! bytes(json(a)) == bytes(json(b))
    }
    static func points(_ id: PersistentIdentifier, to model: any PersistentModel) -> Bool {
        guard sameID(id, model.persistentModelID), let context = model.modelContext else { return false }
        return sameID(context.model(for: id).persistentModelID, model.persistentModelID)
    }
    static func points(_ reference: String?, to model: any PersistentModel) -> Bool {
        guard let reference, let data = reference.data(using: .utf8),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) else { return false }
        return points(id, to: model)
    }
    static func row(_ model: any PersistentModel, _ fields: [String: Any]) -> [String: Any] {
        fields.merging(["persistentID": json(model.persistentModelID)]) { a, _ in a }
    }
    static func sorted(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.sorted { String(data: try! bytes($0), encoding: .utf8)! < String(data: try! bytes($1), encoding: .utf8)! }
    }
    @MainActor
    static func snapshot(_ c: ModelContext) throws -> [String: Any] {
        let tasks = try c.fetch(FetchDescriptor<OneTask>())
        let events = try c.fetch(FetchDescriptor<OneEvent>())
        let alarms = try c.fetch(FetchDescriptor<OneAlarm>())
        let lists = try c.fetch(FetchDescriptor<OneList>())
        let habits = try c.fetch(FetchDescriptor<Habit>())
        let threads = try c.fetch(FetchDescriptor<ChatThread>())
        let ledger = try c.fetch(FetchDescriptor<LedgerEntry>())
        let grants = try c.fetch(FetchDescriptor<AIGrant>())
        let receipts = try c.fetch(FetchDescriptor<ShareImportReceipt>())
        let counts = [tasks.count, events.count, alarms.count, lists.count, habits.count, threads.count, ledger.count, grants.count, receipts.count]
        guard counts == [3, 2, 2, 2, 1, 1, 2, 2, 1] else { throw Failure("Unexpected counts: \(counts)") }
        let task = try #require(tasks.first { $0.title == "Synthetic recurring work" })
        let thread = try #require(threads.first)
        let meeting = try #require(events.first { $0.title == "Synthetic meeting" })
        let wake = try #require(alarms.first { $0.label == "Synthetic wake" })
        let checks: [(String, Bool)] = [
            ("list membership", task.listName == lists.first(where: { $0.name == "Synthetic Work" })?.name),
            ("thread item IDs", thread.items.count == 3 && zip(thread.items, [task as any PersistentModel, meeting, wake]).allSatisfy { points($0, to: $1) }),
            ("decoded messages", thread.messages.count == 2 && thread.messages.map(\.id) == [uid(60), uid(61)]),
            ("one decided card", thread.cards.count == 1),
            ("card item reference", thread.cards.first.map { points($0.itemRef, to: task) } ?? false),
            ("card ledger reference", thread.cards.first?.entryID == uid(30)),
            ("card message anchor", thread.cards.first?.anchor == thread.messages.last?.id),
            ("ledger item reference", points(ledger.first(where: { $0.id == uid(30) })?.itemRef, to: task)),
            ("ledger undo reference", ledger.first(where: { $0.id == uid(31) })?.undoOf == uid(30)),
            ("checklist IDs", task.checklist.map(\.id) == [uid(10), uid(11)]),
            ("share receipt ID", receipts[0].sharedID == uid(50))
        ]
        // Baseline decoded PersistentIdentifier Set equality is unreliable; compare full encoded IDs.
        print("PersistentIdentifier native equality: \(thread.items.first == task.persistentModelID); complete encoded equality: \(thread.items.first.map { sameID($0, task.persistentModelID) } ?? false)")
        for (name, passed) in checks where !passed { throw Failure("Broken semantic relationship: \(name)") }
        return [
            "moduleTypes": [String(reflecting: OneTask.self), String(reflecting: OneEvent.self), String(reflecting: OneAlarm.self), String(reflecting: OneList.self), String(reflecting: Habit.self), String(reflecting: ChatThread.self), String(reflecting: LedgerEntry.self), String(reflecting: AIGrant.self), String(reflecting: ShareImportReceipt.self)],
            "counts": counts,
            "OneTask": sorted(tasks.map { t in row(t, ["title": t.title, "note": t.note, "isDone": t.isDone, "doneAt": json(t.doneAt), "plannedStart": json(t.plannedStart), "durationMinutes": t.durationMinutes, "due": json(t.due), "createdAt": json(t.createdAt), "reminderOffsetMinutes": json(t.reminderOffsetMinutes), "listName": t.listName, "tags": t.tags, "flagged": t.flagged, "repeatRule": json(t.repeatRule), "checklist": json(t.checklist), "ringsAsAlarm": t.ringsAsAlarm, "externalID": json(t.externalID)]) }),
            "OneEvent": sorted(events.map { e in row(e, ["title": e.title, "note": e.note, "start": json(e.start), "durationMinutes": e.durationMinutes, "calendarName": e.calendarName, "reminderOffsetMinutes": json(e.reminderOffsetMinutes), "isAllDay": e.isAllDay, "ringsAsAlarm": e.ringsAsAlarm, "externalID": json(e.externalID), "repeatRule": json(e.repeatRule)]) }),
            "OneAlarm": sorted(alarms.map { a in row(a, ["hour": a.hour, "minute": a.minute, "label": a.label, "note": a.note, "weekdays": a.weekdays, "isOn": a.isOn, "createdAt": json(a.createdAt), "snooze": a.snooze, "sound": a.sound, "snoozeMinutes": a.snoozeMinutes, "alarmKitID": json(a.alarmKitID), "alarmKitSignature": json(a.alarmKitSignature)]) }),
            "OneList": sorted(lists.map { l in row(l, ["name": l.name, "colorIndex": l.colorIndex, "symbol": l.symbol, "order": l.order, "externalID": json(l.externalID), "createdAt": json(l.createdAt), "pinned": l.pinned]) }),
            "Habit": sorted(habits.map { h in row(h, ["title": h.title, "icon": h.icon, "createdAt": json(h.createdAt), "checkins": json(h.checkins), "targetPerWeek": h.targetPerWeek, "reminderHour": json(h.reminderHour), "reminderMinute": h.reminderMinute]) }),
            "ChatThread": sorted(threads.map { t in row(t, ["id": json(t.id), "title": t.title, "createdAt": json(t.createdAt), "updatedAt": json(t.updatedAt), "messagesData": json(t.messagesData), "archived": t.archived, "itemsData": json(t.itemsData), "cardsData": json(t.cardsData)]) }),
            "LedgerEntry": sorted(ledger.map { l in row(l, ["id": json(l.id), "date": json(l.date), "actor": l.actor, "channel": l.channel, "action": l.action, "itemKind": l.itemKind, "itemRef": json(l.itemRef), "title": l.title, "before": l.before, "after": l.after, "approval": l.approval, "beforeDate": json(l.beforeDate), "afterDate": json(l.afterDate), "snapshot": json(l.snapshot), "undoOf": json(l.undoOf)]) }),
            "AIGrant": sorted(grants.map { g in row(g, ["id": json(g.id), "scope": g.scope, "granted": json(g.granted), "expires": json(g.expires), "revoked": json(g.revoked)]) }),
            "ShareImportReceipt": sorted(receipts.map { r in row(r, ["sharedID": json(r.sharedID)]) })
        ]
    }
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
#endif
