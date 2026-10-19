import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import Foundation
import SwiftData
import EventKit

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

    private static func entry(_ id: UUID?, in context: ModelContext) -> LedgerItem? {
        guard let id else { return nil }
        Ledger.flush(context)   // the creation may still be waiting to be written to the Activity store
        guard let store = ActivityCenter.shared.store, let event = try? store.event(uid: id.uuidString) else { return nil }
        return LedgerItem(event: event)
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

    private static func record(_ created: LedgerItem?, kind: String, title: String, context: ModelContext) {
        if let created {
            Ledger.recordUndo(of: created, channel: .ask, context: context)
        } else {
            Ledger.record(.deleted, kind: kind, title: title, channel: .ask, context: context)
        }
    }
}


/// A title-only edit never copies a stale Capture back over dates, recurrence or alarm state.
extension CaptureUndo {
    static func title(_ ref: String?, in context: ModelContext) -> String? {
        switch resolve(ref, in: context) {
        case .task(let task): return task.title
        case .alarm(let alarm): return alarm.label
        case .event(let event):
            if let externalID = event.externalID {
                return CalendarSync.shared.nativeEvent(identifier: externalID)?.0.title
            }
            return event.title
        case nil: return nil
        }
    }

    /// Resolving again at commit time prevents a deleted item from being resurrected by an open sheet or Undo toast.
    @discardableResult
    static func rename(_ ref: String?, to title: String, in context: ModelContext) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch resolve(ref, in: context) {
        case .alarm(let alarm):
            let old = alarm.label
            alarm.label = title
            do { try context.save() } catch { alarm.label = old; return false }
            Task { await Ringer.sync(context) }
        case .task(let task):
            let old = task.title
            task.title = title
            do { try context.save() } catch { task.title = old; return false }
            RemindersSync.shared.scheduleReconcile()
        case .event(let event):
            let old = event.title
            // Local events stay local. For linked events, edit the existing EventKit object only:
            // the general save path also writes dates/repeats and can create a replacement.
            var linked: (EKEvent, EKEventStore)?
            var oldLinkedTitle: String?
            if let externalID = event.externalID {
                guard let existing = CalendarSync.shared.nativeEvent(identifier: externalID),
                      existing.0.calendar.allowsContentModifications else { return false }
                linked = existing
                oldLinkedTitle = existing.0.title
                existing.0.title = title
                do { try existing.1.save(existing.0, span: .thisEvent) }
                catch { existing.0.title = oldLinkedTitle; return false }
            }
            event.title = title
            do { try context.save() } catch {
                event.title = old
                if let linked {
                    linked.0.title = oldLinkedTitle
                    try? linked.1.save(linked.0, span: .thisEvent)
                }
                return false
            }
        case nil: return false
        }
        return true
    }
}
