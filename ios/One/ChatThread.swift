import Foundation
import SwiftData

/// A saved conversation with the AI. Only the text is kept: role + text per message. The preview cards for
/// captures and plans are not restored; reopening a chat shows what was said and lets you continue it.
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
        return c
    }
}
