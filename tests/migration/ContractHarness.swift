import Foundation
import SQLite3

// Compiled beside unmodified sources extracted from the specified Git commit.
// This executable never opens the app container or the QA journal.
struct ContractFailure: Error, CustomStringConvertible {
    let description: String
}
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw ContractFailure(description: message) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let instant = Date(timeIntervalSince1970: 1792339200.125)
let shareID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
let undoID = "20000000-0000-0000-0000-000000000002"
func url(_ name: String) -> URL { root.appendingPathComponent(name) }
func json(_ value: Any, to name: String) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url(name))
}
func sample() throws -> ActivityEvent {
    var e = ActivityEvent(persistedUID: shareID.uuidString, ts: 1792339200125, tz: -420,
                          day: 20261018, tier: .changes, kind: "change.deleted", actor: "you")
    e.device = "synthetic-install"
    e.session = "synthetic-launch"
    e.thread = "30000000-0000-0000-0000-000000000003"
    // A deliberately opaque reference; this is NOT a SwiftData PersistentIdentifier.
    e.subjectKind = "task"; e.subjectRef = "synthetic-task-reference"
    e.channel = "app"; e.approval = "user"
    e.title = "Synthetic migration reminder"
    e.beforeText = "Before, \"quoted\"\nsecond line"; e.afterText = "After"
    e.beforeTs = e.ts - 60_000; e.afterTs = e.ts + 60_000
    e.props = ActivityProps.json(["count": 1, "enabled": true])
    var snapshot = TaskSnapshot(title: e.title!)
    snapshot.createdAt = instant
    snapshot.plannedStart = instant.addingTimeInterval(3600)
    snapshot.due = instant.addingTimeInterval(7200)
    snapshot.repeatRule = "weekly:2,4"
    snapshot.listName = "Synthetic list"
    snapshot.tags = ["synthetic"]
    var check = ChecklistItem(title: "Synthetic checklist")
    check.id = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    snapshot.checklist = [check]
    e.snapshot = try JSONEncoder().encode(snapshot) // Production TaskSnapshot uses default Date encoding.
    e.content = [ActivityContent(field: "title", before: "Synthetic original", after: e.title)]
    return e
}
func write() throws {
    let e = try sample()
    try e.snapshot!.write(to: url("task-snapshot.json"))
    do {
        let store = try ActivityStore(location: .file(url("activity.sqlite")))
        try require(try store.insert([e]) == 1, "insert original")
        var undo = e
        undo.uid = undoID; undo.undoOf = e.uid; undo.kind = "change.undone"
        undo.snapshot = nil; undo.content = []; undo.ts += 1
        try require(try store.insert([undo]) == 1, "insert undo relationship")
        try require(try store.insert([e, undo]) == 0, "UID replay must be idempotent")
        try ActivityExport.write(.jsonl, from: store, to: url("activity.jsonl"))
        try ActivityExport.write(.csv, from: store, to: url("activity.csv"))
    }
    let shared = SharedReminder(id: shareID, title: "Synthetic share", note: "https://example.invalid/synthetic",
                               due: Date(timeIntervalSince1970: 1792368000), sharedAt: instant)
    try require(ShareInbox.append(shared, at: url("share-inbox.json")), "write share inbox")
    try require(ActivityOutbox.append(kind: "sys.share.add", actor: "share", channel: "share",
                                     props: ["count": 1], at: instant, in: url("activity-outbox")), "write extension JSONL")
    let widget = WidgetSnapshot(generatedAt: instant, items: [WidgetItem(id: "synthetic-widget", title: "Synthetic widget",
                                            start: instant, kind: .reminder)])
    try widget.encoded().write(to: url("widget-snapshot.json"))
    try json(["task_reference": "synthetic-task-reference", "event_uid": e.uid, "undo_uid": undoID,
              "share_id": shareID.uuidString, "timestamp_ms": e.ts, "timezone_minutes": e.tz, "local_day": e.day,
              "snapshot_date_encoding": "seconds since 2001-01-01", "share_widget_date_encoding": "ISO8601 whole seconds",
              "repeat_raw": "weekly:2,4"], to: "expected.json")
    print("PASS baseline writer: disk SQLite, JSONL/CSV, share inbox, extension outbox, widget")
}
func verify() throws {
    let expected = try sample()
    let store = try ActivityStore(location: .file(url("activity.sqlite")))
    try require(try store.count() == 2, "disk event count")
    let rows = try store.page(ActivityQuery(), limit: 10)
    try require(rows.map(\.uid) == [undoID, shareID.uuidString], "cursor order and stable event IDs")
    let e = rows[1]
    try require(e.ts == expected.ts && e.tz == -420 && e.day == 20261018, "stored date/timezone/day")
    try require(e.subjectRef == expected.subjectRef && rows[0].undoOf == e.uid, "logical relationships")
    try require(e.title == expected.title && e.beforeText == expected.beforeText && e.props == expected.props, "text and nested props")
    try require(try store.snapshot(uid: e.uid) == Data(contentsOf: url("task-snapshot.json")), "snapshot bytes")
    try require(try store.content(uid: e.uid) == expected.content, "content relationship")
    let snapshot = try JSONDecoder().decode(TaskSnapshot.self, from: store.snapshot(uid: e.uid)!)
    try require(snapshot.createdAt == instant && snapshot.due == instant.addingTimeInterval(7200), "snapshot dates")
    try require(snapshot.repeatRule == "weekly:2,4" && snapshot.listName == "Synthetic list", "recurrence and list reference")
    try require(snapshot.checklist.first?.id.uuidString == "40000000-0000-0000-0000-000000000004", "checklist ID")
    try require(RepeatRule(rawValue: snapshot.repeatRule!)?.rawValue == snapshot.repeatRule, "repeat raw format")
    let exported = ActivityJSONL.events(from: try String(contentsOf: url("activity.jsonl"), encoding: .utf8))
    try require(exported.count == 2 && exported[0].snapshot == (try Data(contentsOf: url("task-snapshot.json"))) && exported[1].undoOf == e.uid, "export relationships")
    try require(try store.insert(exported) == 0, "export replay after reopening")
    let inbox = try ShareInbox.read(at: url("share-inbox.json"))
    try require(inbox.count == 1 && inbox[0].id == shareID, "share stable UUID")
    try require(inbox[0].sharedAt == Date(timeIntervalSince1970: floor(instant.timeIntervalSince1970)), "ISO8601 fractional truncation")
    let widget = WidgetSnapshot.decode(try Data(contentsOf: url("widget-snapshot.json")))
    try require(widget?.items.first?.id == "synthetic-widget", "widget format")
    let files = ActivityOutbox.pendingFiles(in: url("activity-outbox"))
    let outbox = try files.flatMap { ActivityJSONL.events(from: try String(contentsOf: $0, encoding: .utf8)) }
    try require(outbox.count == 1 && outbox[0].ts == expected.ts && outbox[0].actor == "share", "outbox format")
    try require(try store.insert(outbox) == 1, "outbox commit before acknowledgment")
    // Simulate interruption before removal: same retained file is read again, UID rejects the replay.
    try require(try store.insert(outbox) == 0 && files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "outbox replay")
    try verifyShareInterruption(inbox)
    try verifyLegacyResume()
    // A newer-schema database must fail closed, with the row retained and no replacement.
    let newer = url("newer.sqlite")
    var handle: OpaquePointer?
    try require(sqlite3_open(newer.path, &handle) == SQLITE_OK, "create newer synthetic store")
    try require(sqlite3_exec(handle, "CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES ('retain'); PRAGMA user_version=999;", nil, nil, nil) == SQLITE_OK, "newer sentinel")
    sqlite3_close(handle)
    do {
        _ = try ActivityStore(location: .file(newer))
        throw ContractFailure(description: "newer schema was accepted")
    } catch ActivityStoreError.newerSchema(999) { }
    try require(FileManager.default.fileExists(atPath: newer.path), "never delete newer database")
    try require(sqlite3_open_v2(newer.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, "reopen rejected database")
    var statement: OpaquePointer?
    try require(sqlite3_prepare_v2(handle, "SELECT value FROM sentinel", -1, &statement, nil) == SQLITE_OK, "retained sentinel schema")
    try require(sqlite3_step(statement) == SQLITE_ROW && String(cString: sqlite3_column_text(statement, 0)) == "retain", "retained sentinel value")
    sqlite3_finalize(statement); sqlite3_close(handle)
    print("PASS reader: IDs, dates, recurrence, relationships, export, outbox replay, share interruption/interleaved append, legacy partial import/reopen, newer-schema refusal")
}
func verifyShareInterruption(_ items: [SharedReminder]) throws {
    // Test-only SQLite receipt adapter, NOT the production SwiftData task+receipt transaction.
    // Existing ShareImportDurabilityTests cover save/ack/corrupt/Undo branches; this retains old-writer artifacts.
    let receiptURL = url("share-receipts.sqlite")
    func receipts() throws -> Set<UUID> {
        let db = try ActivityStore(location: .file(receiptURL))
        return Set((try db.meta("synthetic_receipts") ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }
    var persistCalls = 0
    func persist(_ drafts: [SharedReminder]) throws -> [UUID] {
        let db = try ActivityStore(location: .file(receiptURL))
        try db.setMeta("synthetic_receipts", drafts.map { $0.id.uuidString }.joined(separator: ","))
        persistCalls += 1
        return drafts.map(\.id)
    }
    let first = try ShareImport.run(at: url("share-inbox.json"), committedIDs: receipts, persist: persist, acknowledge: { _ in false })
    try require(first.added == [shareID] && !first.acknowledged, "share commit/ack interruption")
    let later = SharedReminder(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, title: "Synthetic concurrent arrival", due: nil, sharedAt: instant.addingTimeInterval(1))
    let retry = try ShareImport.run(at: url("share-inbox.json"), committedIDs: receipts, persist: persist, acknowledge: { ids in
        guard ShareInbox.append(later, at: url("share-inbox.json")) else { return false }
        return ShareInbox.acknowledge(ids, at: url("share-inbox.json"))
    })
    try require(retry.added.isEmpty && retry.acknowledged && persistCalls == 1, "share reload receipt deduplication")
    try require(try ShareInbox.read(at: url("share-inbox.json")).map(\.id) == [later.id], "append during acknowledgment survives")
}
func verifyLegacyResume() throws {
    let rows = (1...3).map { i in
        LegacyLedgerRow(id: UUID(uuidString: String(format: "50000000-0000-0000-0000-%012d", i))!, date: instant,
                        actor: "you", channel: "app", action: "created", itemKind: "task", itemRef: "synthetic-task-reference",
                        title: "Synthetic legacy \(i)", before: "", after: "Added", approval: "user")
    }
    let path = url("legacy-import.sqlite")
    do {
        let db = try ActivityStore(location: .file(path))
        let partial = try LedgerImport.run(into: db, total: 3, session: "old-launch", batch: 1) { offset, _ in offset == 0 ? [rows[0]] : [] }
        try require(!partial.verified && !LedgerImport.isMigrated(db), "partial import must not set completion")
    }
    let db = try ActivityStore(location: .file(path))
    let resumed = try LedgerImport.run(into: db, total: 3, session: "new-launch", batch: 1) { offset, count in Array(rows.dropFirst(offset).prefix(count)) }
    try require(resumed.verified && resumed.alreadyThere == 1 && resumed.imported == 2, "resume from disk without duplicates")
    try require(!LedgerImport.mayRemoveLegacy(db, session: "new-launch"), "same launch cannot remove legacy rows")
    try require(LedgerImport.mayRemoveLegacy(db, session: "later-launch"), "later launch gate")
}
do {
    if CommandLine.arguments[1] == "write" { try write() }
    else if CommandLine.arguments[1] == "verify" { try verify() }
    else { throw ContractFailure(description: "Expected write or verify") }
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
