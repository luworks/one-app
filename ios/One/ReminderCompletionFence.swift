import Foundation

/// Invalidates asynchronous reminder snapshots only after a durable explicit completion write.
/// A failed write leaves the previous snapshot usable and the caller's local state unchanged.
struct ReminderCompletionFence {
    private(set) var revision: UInt64 = 0

    mutating func commit(_ write: () throws -> Void) rethrows {
        try write()
        revision &+= 1
    }

    /// Only the fields actually committed to Apple become agreed; pending note/list/repeat edits
    /// must remain different from the baseline so reconciliation can still upload them.
    static func baseline(_ agreed: String, done: Bool, restoredDue: String? = nil) -> String {
        var fields = agreed.components(separatedBy: "\u{1F}")
        guard fields.count == 7 else { return agreed }
        fields[2] = done ? "1" : "0"
        if let restoredDue { fields[3] = restoredDue }
        return fields.joined(separator: "\u{1F}")
    }

    func accepts(snapshot revision: UInt64) -> Bool { self.revision == revision }
}
