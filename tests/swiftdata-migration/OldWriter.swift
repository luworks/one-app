import Foundation
import SwiftData

/// Synthetic fixture only. Model declarations are extracted unchanged from the locked baseline.
@main
struct OldWriter {
    static let epoch = Date(timeIntervalSince1970: 1_792_281_600)
    static func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    static func json<T: Encodable>(_ value: T) -> Any {
        try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
    static func bytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    }
    static func ref(_ model: any PersistentModel) -> String {
        String(data: try! JSONEncoder().encode(model.persistentModelID), encoding: .utf8)!
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
        let task = tasks.first { $0.title == "Synthetic recurring work" }!
        let thread = threads[0]
        let checks: [(String, Bool)] = [
            ("list membership", task.listName == lists.first(where: { $0.name == "Synthetic Work" })?.name),
            ("thread item IDs", thread.items.count == 3 && zip(thread.items, [task as any PersistentModel, events.first { $0.title == "Synthetic meeting" }!, alarms.first { $0.label == "Synthetic wake" }!]).allSatisfy { points($0, to: $1) }),
            ("one decided card", thread.cards.count == 1),
            ("card item reference", thread.cards.first.map { points($0.itemRef, to: task) } ?? false),
            ("card ledger reference", thread.cards.first?.entryID == uid(30)),
            ("card message anchor", thread.cards.first?.anchor == thread.messages.last?.id),
            ("ledger item reference", points(ledger.first(where: { $0.id == uid(30) })?.itemRef, to: task)),
            ("ledger undo reference", ledger.first(where: { $0.id == uid(31) })?.undoOf == uid(30)),
            ("checklist IDs", task.checklist.map(\.id) == [uid(10), uid(11)]),
            ("share receipt ID", receipts[0].sharedID == uid(50))
        ]
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
    @MainActor
    static func seed(_ c: ModelContext) throws {
        let list = OneList(name: "Synthetic Work", colorIndex: 4, symbol: "briefcase", order: 1)
        list.externalID = "synthetic-list-1"; list.createdAt = epoch; list.pinned = true
        let empty = OneList(name: "Synthetic Empty", colorIndex: 2, order: 2); empty.createdAt = epoch
        c.insert(list); c.insert(empty)
        let t = OneTask(title: "Synthetic recurring work", note: "Synthetic only\nUnicode: 测试", plannedStart: epoch.addingTimeInterval(3600), durationMinutes: 45, due: epoch.addingTimeInterval(7200))
        t.createdAt = epoch; t.listName = list.name; t.tags = ["synthetic", "work"]; t.flagged = true
        t.repeatRule = RepeatRule.weekdays.rawValue; t.reminderOffsetMinutes = 15; t.ringsAsAlarm = true; t.externalID = "synthetic-reminder-1"
        t.checklist = [ChecklistItem(id: uid(10), title: "Synthetic first", done: true), ChecklistItem(id: uid(11), title: "Synthetic second", done: false)]
        let done = OneTask(title: "Synthetic completed", due: epoch.addingTimeInterval(-86400))
        done.createdAt = epoch; done.isDone = true; done.doneAt = epoch; done.reminderOffsetMinutes = nil
        let inbox = OneTask(title: "Synthetic inbox"); inbox.createdAt = epoch
        c.insert(t); c.insert(done); c.insert(inbox)
        let e = OneEvent(title: "Synthetic meeting", start: epoch.addingTimeInterval(10800), durationMinutes: 60, calendarName: "Synthetic Calendar")
        e.note = "Synthetic fixed event"; e.repeatRule = RepeatRule.weekly.rawValue; e.externalID = "synthetic-event-1"; e.ringsAsAlarm = true
        let allDay = OneEvent(title: "Synthetic all day", start: epoch, durationMinutes: 1440)
        allDay.isAllDay = true; allDay.reminderOffsetMinutes = nil
        c.insert(e); c.insert(allDay)
        let a = OneAlarm(hour: 7, minute: 15, label: "Synthetic wake", weekdays: [2, 4, 6], snooze: false)
        a.createdAt = epoch; a.note = "Synthetic alarm"; a.sound = "radial"; a.snoozeMinutes = 5; a.alarmKitID = uid(20); a.alarmKitSignature = "synthetic-signature"
        let off = OneAlarm(hour: 23, minute: 59, label: "Synthetic off"); off.createdAt = epoch; off.isOn = false
        c.insert(a); c.insert(off)
        let h = Habit(title: "Synthetic retired habit", icon: "leaf")
        h.createdAt = epoch; h.checkins = [epoch, epoch.addingTimeInterval(-86400)]; h.targetPerWeek = 3; h.reminderHour = 8; h.reminderMinute = 20
        c.insert(h)
        let grant = AIGrant(scope: .planFreeTime, granted: epoch); grant.id = uid(40); grant.expires = epoch.addingTimeInterval(604800)
        let revoked = AIGrant(scope: .planFreeTime, granted: epoch); revoked.id = uid(41); revoked.expires = epoch.addingTimeInterval(604800); revoked.revoked = epoch.addingTimeInterval(100)
        c.insert(grant); c.insert(revoked); c.insert(ShareImportReceipt(sharedID: uid(50)))
        // Save first: string/JSON references must use final on-disk identifiers.
        try c.save()
        let entry = LedgerEntry(date: epoch, actor: .you, channel: .app, action: .created, itemKind: "task", title: t.title, before: "Synthetic before", after: "Synthetic after", approval: .asked)
        entry.id = uid(30); entry.itemRef = ref(t); entry.beforeDate = epoch; entry.afterDate = t.plannedStart; entry.snapshot = Data("synthetic-legacy-snapshot".utf8)
        let undo = LedgerEntry(date: epoch.addingTimeInterval(60), actor: .you, channel: .app, action: .undone, itemKind: "task", title: t.title, approval: .userMade)
        undo.id = uid(31); undo.undoOf = entry.id
        c.insert(entry); c.insert(undo)
        let user = ChatMessage(id: uid(60), role: .user, text: "Synthetic request", timestamp: epoch)
        let ai = ChatMessage(id: uid(61), role: .ai, text: "Synthetic approved preview", timestamp: epoch)
        let thread = ChatThread(title: "Synthetic chat", messages: [user, ai], createdAt: epoch, updatedAt: epoch, id: uid(62))
        thread.archived = true; thread.items = [t.persistentModelID, e.persistentModelID, a.persistentModelID]
        let capture = Capture(title: t.title, day: epoch, hasDay: true, hour: 1, listName: list.name)
        thread.cards = [StoredCard(id: uid(63), anchor: ai.id, batch: uid(64), batchSize: 1, capture: capture, status: .added, itemRef: ref(t), entryID: entry.id)]
        c.insert(thread); try c.save()
    }
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, ["write", "verify"].contains(args[1]) else { throw Failure("Usage: old-writer write|verify STORE EXPECTED.json") }
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "write", FileManager.default.fileExists(atPath: url.path) { throw Failure("Refusing to overwrite existing store") }
        if args[1] == "verify", !FileManager.default.fileExists(atPath: url.path) { throw Failure("Missing old store; refusing to create one") }
        let schema = Schema([OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self, ChatThread.self, LedgerEntry.self, AIGrant.self, ShareImportReceipt.self])
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: args[1] == "write", cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container); context.autosaveEnabled = false
        if args[1] == "write" { try seed(context) }
        let actual = try bytes(snapshot(context))
        let expected = URL(fileURLWithPath: args[3])
        if args[1] == "write" {
            guard !FileManager.default.fileExists(atPath: expected.path) else { throw Failure("Refusing to overwrite expected snapshot") }
            try actual.write(to: expected, options: .withoutOverwriting)
        } else {
            try actual.write(to: expected.deletingLastPathComponent().appendingPathComponent("reopened.json"))
            guard actual == (try Data(contentsOf: expected)) else { throw Failure("Full persisted snapshot differs after process reopen") }
        }
        print("PASS \(args[1]): module One; 9 types; 16 rows; counts [3,2,2,2,1,1,2,2,1]; all persisted fields and references")
    }
}
