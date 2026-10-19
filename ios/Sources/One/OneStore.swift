#if os(iOS)
import Foundation
import SwiftData

/// The one data store. The app and its App Intents (Siri, Shortcuts, Spotlight run them in this process) share it,
/// whichever of them asks first.
@MainActor
public enum OneStore {
    private static var started = false

    /// Opens the store and hooks up notifications and Apple Reminders sync, once per process.
    @discardableResult
    public static func start() -> ModelContainer {
        if !started {
            started = true
            Reminders.shared.configure(container)
            RemindersSync.shared.configure(container)
            WidgetFeed.configure(container)
        }
        return container
    }

    public static let container: ModelContainer = {
        do {
            // UI tests launch with -uiTesting: a fresh in-memory store with the sample data.
            // -dataset <path> (with -uiTesting) loads tests/fixtures/today-dataset.json instead of the sample data.
            // -uiTestingStore <name> keeps the test store in a file, so a second launch can see what the first one saved.
            let args = ProcessInfo.processInfo.arguments
            let testing = args.contains("-uiTesting")
            let inMemory = testing
            let configuration: ModelConfiguration
            if testing, let i = args.firstIndex(of: "-uiTestingStore"), i + 1 < args.count {
                configuration = ModelConfiguration(url: FileManager.default.temporaryDirectory.appending(path: "\(args[i + 1]).store"))
            } else {
                configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            }
            return try ModelContainer(for: OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self, ChatThread.self,
                                      LedgerEntry.self, AIGrant.self, ShareImportReceipt.self,
                                      configurations: configuration)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }()
}
#endif
