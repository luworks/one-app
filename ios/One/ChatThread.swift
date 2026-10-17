import Foundation
import SwiftData

/// A saved conversation with the AI: role + text per message, and the preview cards that were decided (added, dropped,
/// undone; see `StoredCard`) under the message they belong to. A card still waiting for Add is not restored; plan and
/// change cards are not kept. Reopening a chat shows what was said and lets you continue it.
@Model
final class ChatThread {
    var id: UUID = UUID()
    /// The first user message, tidied (see `ConversationHistory.title`).
    var title: String = ""
    var createdAt: Date = Date.now
    /// When the last message was added; the sidebar sorts and groups by this.
    var updatedAt: Date = Date.now
    /// JSON of `[ChatMessage]`. Kept as plain data so the stored shape never depends on a Swift type.
    var messagesData: Data = Data()
    /// Archived conversations leave the main list and wait under "Archived" in the sidebar.
    var archived: Bool = false
    /// The reminders, events and alarms this conversation added (JSON of their ids), so it can archive itself once they
    /// are all done (see `ChatAutoArchive`). Additive field: older stores get none.
    var itemsData: Data = Data()

    /// JSON of `[StoredCard]`: the decided cards. Additive field: older conversations have none and show none.
    var cardsData: Data = Data()

    var cards: [StoredCard] {
        get { StoredCard.restore(cardsData) }
        set { cardsData = StoredCard.encode(newValue) }
    }

    var items: [PersistentIdentifier] {
        get { (try? JSONDecoder().decode([PersistentIdentifier].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(title: String, messages: [ChatMessage], createdAt: Date = .now, updatedAt: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messagesData = Self.encode(messages)
    }

    var messages: [ChatMessage] {
        get { (try? JSONDecoder().decode([ChatMessage].self, from: messagesData)) ?? [] }
        set { messagesData = Self.encode(newValue) }
    }

    private static func encode(_ messages: [ChatMessage]) -> Data {
        (try? JSONEncoder().encode(messages)) ?? Data()
    }

    /// An unsaved copy with the same content, used to put a deleted conversation back (Undo).
    func copy() -> ChatThread {
        let c = ChatThread(title: title, messages: [], createdAt: createdAt, updatedAt: updatedAt, id: id)
        c.messagesData = messagesData
        c.archived = archived
        c.itemsData = itemsData
        c.cardsData = cardsData
        return c
    }
}
