import Foundation

// The changes ledger (tier 1) on top of the Activity store. Pure: no SwiftData. `Ledger.swift` records through these types and
// reads the Activity screen's rows back as `LedgerItem`s. See docs/research/activity-data-store.md §3.6 for the migration plan.

/// One line of the Activity ledger as the app sees it (what `LedgerEntry` used to hold): who changed what, how, when,
/// before → after, and how it was approved. Immutable once stored; Undo adds an `undone` item pointing at the original.
struct LedgerItem: Identifiable, Equatable {
    var id: UUID
    var date: Date
    /// `LedgerActor.raw`.
    var actor: String
    /// `LedgerChannel.rawValue`.
    var channel: String
    /// `LedgerAction.rawValue`.
    var action: String
    /// "task", "event", "alarm" or "grant".
    var itemKind: String
    /// The reminder's `PersistentIdentifier` (JSON), filled in once it is saved. nil for events, alarms and deletes.
    var itemRef: String?
    var title: String
    var before: String
    var after: String
    /// `LedgerApproval.rawValue`.
    var approval: String
    var beforeDate: Date?
    var afterDate: Date?
    /// A deleted reminder is stored (`TaskSnapshot`), so Activity can put it back.
    var hasSnapshot = false
    var undoOf: UUID?

    init(id: UUID = UUID(), date: Date = .now, actor: LedgerActor, channel: LedgerChannel, action: LedgerAction, itemKind: String,
         title: String, before: String = "", after: String = "", approval: LedgerApproval) {
        self.id = id
        self.date = date
        self.actor = actor.raw
        self.channel = channel.rawValue
        self.action = action.rawValue
        self.itemKind = itemKind
        self.title = title
        self.before = before
        self.after = after
        self.approval = approval.rawValue
    }

    var actorValue: LedgerActor { LedgerActor(raw: actor) }
    var actionValue: LedgerAction { LedgerAction(rawValue: action) ?? .moved }
    var approvalValue: LedgerApproval { LedgerApproval(rawValue: approval) ?? .userMade }
}

extension LedgerItem {
    /// The event that stores this item. `snapshot` goes to its own table.
    func event(snapshot: Data? = nil, calendar: Calendar = .current) -> ActivityEvent {
        let isGrant = actionValue == .granted || actionValue == .revoked
        let kind = (isGrant ? ActivityKind.grantPrefix : ActivityKind.changePrefix) + action
        var e = ActivityEvent(kind: kind, tier: .changes, actor: actor, channel: (LedgerChannel(rawValue: channel) ?? .app).slug,
                              at: date, calendar: calendar)
        e.uid = id.uuidString
        e.subjectKind = itemKind
        e.subjectRef = itemRef
        e.approval = approval
        e.undoOf = undoOf?.uuidString
        e.title = title
        e.beforeText = before
        e.afterText = after
        e.beforeTs = beforeDate.map(ActivityClock.ms)
        e.afterTs = afterDate.map(ActivityClock.ms)
        e.snapshot = snapshot
        return e
    }

    /// A stored tier-1 event back as a ledger item.
    init(event e: ActivityEvent) {
        let name = e.kind.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? e.kind
        self.id = UUID(uuidString: e.uid) ?? UUID()
        self.date = e.date
        self.actor = e.actor
        self.channel = e.channel.flatMap(LedgerChannel.init(slug:))?.rawValue ?? LedgerChannel.app.rawValue
        self.action = name
        self.itemKind = e.subjectKind ?? "task"
        self.itemRef = e.subjectRef
        self.title = e.title ?? ""
        self.before = e.beforeText ?? ""
        self.after = e.afterText ?? ""
        self.approval = e.approval ?? LedgerApproval.userMade.rawValue
        self.beforeDate = e.beforeTs.map(ActivityClock.date(ms:))
        self.afterDate = e.afterTs.map(ActivityClock.date(ms:))
        self.hasSnapshot = e.hasSnapshot
        self.undoOf = e.undoOf.flatMap(UUID.init(uuidString:))
    }
}

/// An old SwiftData `LedgerEntry` as plain values, so the import can be tested without SwiftData.
struct LegacyLedgerRow: Equatable {
    var id: UUID
    var date: Date
    var actor: String
    var channel: String
    var action: String
    var itemKind: String
    var itemRef: String?
    var title: String
    var before: String
    var after: String
    var approval: String
    var beforeDate: Date?
    var afterDate: Date?
    var snapshot: Data?
    var undoOf: UUID?

    var item: LedgerItem {
        var i = LedgerItem(id: id, date: date, actor: LedgerActor(raw: actor), channel: LedgerChannel(rawValue: channel) ?? .app,
                           action: LedgerAction(rawValue: action) ?? .moved, itemKind: itemKind, title: title, before: before,
                           after: after, approval: LedgerApproval(rawValue: approval) ?? .userMade)
        // Keep the stored strings exactly (an unknown action or channel is not rewritten).
        i.action = action
        i.channel = channel
        i.approval = approval
        i.actor = actor
        i.itemRef = itemRef
        i.beforeDate = beforeDate
        i.afterDate = afterDate
        i.undoOf = undoOf
        i.hasSnapshot = snapshot != nil
        return i
    }

    var event: ActivityEvent { item.event(snapshot: snapshot) }
}

/// The one-time copy of the old ledger into the store (document §3.6 step 2). Idempotent: keyed on the entry's UUID, so running
/// it twice, or after a crash half way, adds nothing twice. Nothing in SwiftData is deleted here.
enum LedgerImport {
    static let migratedKey = "ledger_migrated"
    /// The launch session in which the copy was verified; the old rows are removed only in a later session.
    static let migratedSessionKey = "ledger_migrated_session"
    static let legacyRemovedKey = "ledger_legacy_removed"

    struct Outcome: Equatable {
        /// Rows in the old ledger.
        var legacyTotal = 0
        /// New events added (or, in a dry run, that would be added).
        var imported = 0
        /// Rows that were already in the store.
        var alreadyThere = 0
        /// Every old row is now in the store.
        var verified = false
    }

    /// Copies the old rows in batches, one transaction each. `fetch(offset, limit)` returns old rows in a stable order.
    /// With `dryRun` nothing is written: the outcome says what would happen.
    static func run(into store: ActivityStore, total: Int, session: String, batch: Int = 500, dryRun: Bool = false,
                    fetch: (_ offset: Int, _ limit: Int) -> [LegacyLedgerRow]) throws -> Outcome {
        var out = Outcome(legacyTotal: total)
        var offset = 0
        while offset < total {
            let rows = fetch(offset, batch)
            if rows.isEmpty { break }
            offset += rows.count
            let there = try store.existingCount(uids: rows.map { $0.id.uuidString })
            out.alreadyThere += there
            if dryRun {
                out.imported += rows.count - there
            } else {
                out.imported += try store.insert(rows.map(\.event))
            }
        }
        out.verified = !dryRun && out.imported + out.alreadyThere == total
        if out.verified {
            try store.setMeta(migratedKey, "1")
            try store.setMeta(migratedSessionKey, session)
        }
        return out
    }

    static func isMigrated(_ store: ActivityStore) -> Bool { (try? store.meta(migratedKey)) == "1" }

    /// The old rows may be deleted: the copy was verified in an earlier launch than this one, and that has not happened yet.
    static func mayRemoveLegacy(_ store: ActivityStore, session: String) -> Bool {
        guard isMigrated(store), (try? store.meta(legacyRemovedKey)) != "1" else { return false }
        guard let at = try? store.meta(migratedSessionKey) else { return false }
        return at != session
    }
}
