import Foundation
import SwiftData

/// Takes back exactly what a card's Add wrote, and finds it again for Open. The card keeps the created item's id
/// (`Ledger.ref` JSON) and the Activity entry of its creation (`StoredCard.itemRef` / `entryID`).
@MainActor
enum CaptureUndo {
    enum Item {
        case task(OneTask)
        case event(OneEvent)
        case alarm(OneAlarm)
    }

    static func decode(_ ref: String) -> PersistentIdentifier? {
        ref.data(using: .utf8).flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }

    /// The item an Add wrote, or nil when it is gone (deleted since).
    static func resolve(_ ref: String?, in context: ModelContext) -> Item? {
        guard let ref, let id = decode(ref) else { return nil }
        switch id.entityName {
        case "OneTask":
            var d = FetchDescriptor<OneTask>(predicate: #Predicate { $0.persistentModelID == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first.map(Item.task)
        case "OneEvent":
            var d = FetchDescriptor<OneEvent>(predicate: #Predicate { $0.persistentModelID == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first.map(Item.event)
        case "OneAlarm":
            var d = FetchDescriptor<OneAlarm>(predicate: #Predicate { $0.persistentModelID == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first.map(Item.alarm)
        default:
            return nil
        }
    }

    private static func entry(_ id: UUID?, in context: ModelContext) -> LedgerEntry? {
        guard let id else { return nil }
        var d = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Removes the created item and records the undo in Activity. An item that is already gone counts as taken back.
    /// False only when it could not be removed (an event in a read-only calendar).
    static func undo(itemRef: String?, entryID: UUID?, title: String, context: ModelContext) -> Bool {
        let created = entry(entryID, in: context)
        switch resolve(itemRef, in: context) {
        case nil:
            return true
        case .task(let task):
            // The Activity undo of a creation: removes the reminder (and its Apple Reminders copy) and records "undone".
            if let created, Ledger.undo(created, context: context) { return true }
            TaskActions.delete(task, context: context, toast: nil, actor: .you, channel: .ask)
            return true
        case .alarm(let alarm):
            context.delete(alarm)
            try? context.save()
            record(created, kind: "alarm", title: title, context: context)
            Task { await Ringer.sync(context) }
            return true
        case .event(let event):
            guard CalendarSync.shared.delete(event, span: .thisEvent) else { return false }
            context.delete(event)
            try? context.save()
            record(created, kind: "event", title: title, context: context)
            return true
        }
    }

    private static func record(_ created: LedgerEntry?, kind: String, title: String, context: ModelContext) {
        if let created {
            Ledger.recordUndo(of: created, channel: .ask, context: context)
        } else {
            Ledger.record(.deleted, kind: kind, title: title, channel: .ask, context: context)
        }
    }
}
