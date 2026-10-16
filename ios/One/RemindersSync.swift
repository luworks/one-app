import Foundation

/// Bridge between the app's reminders and Apple Reminders (EventKit). Placeholder API; the real
/// implementation lands next. `connect()` asks for access and starts syncing.
@MainActor
@Observable
final class RemindersSync {
    static let shared = RemindersSync()
    private init() {}

    /// True once the user allowed access to Apple Reminders and sync is on.
    private(set) var isConnected = false

    func connect() async {}
}
