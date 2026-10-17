import Foundation
import SwiftData

/// Archives conversations that are finished (rule: `ConversationHistory.shouldAutoArchive`). Runs when the sidebar opens.
/// Off in Settings ("Archive finished chats").
@MainActor
enum ChatAutoArchive {
    static func run(_ context: ModelContext, now: Date = .now) {
        guard UserDefaults.standard.object(forKey: SettingsKey.autoArchiveChats) as? Bool ?? true else { return }
        let open = (try? context.fetch(FetchDescriptor<ChatThread>(predicate: #Predicate { !$0.archived }))) ?? []
        var changed = false
        for thread in open {
            let settled = thread.items.map { isSettled($0, in: context, now: now) }
            if ConversationHistory.shouldAutoArchive(updatedAt: thread.updatedAt, settled: settled, now: now) {
                thread.archived = true
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Done with: a reminder completed or deleted, an event over (a repeating one never is), an alarm rung or switched off.
    private static func isSettled(_ id: PersistentIdentifier, in context: ModelContext, now: Date) -> Bool {
        switch id.entityName {
        case "OneTask":
            let found = try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.persistentModelID == id }))
            return found?.first.map(\.isDone) ?? true
        case "OneEvent":
            let found = try? context.fetch(FetchDescriptor<OneEvent>(predicate: #Predicate { $0.persistentModelID == id }))
            guard let e = found?.first else { return true }
            return e.repeatRule == nil && e.start.addingTimeInterval(e.duration) < now
        case "OneAlarm":
            let found = try? context.fetch(FetchDescriptor<OneAlarm>(predicate: #Predicate { $0.persistentModelID == id }))
            return found?.first.map { !$0.isOn } ?? true
        default:
            return false
        }
    }
}
