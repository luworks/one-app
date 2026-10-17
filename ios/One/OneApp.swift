import SwiftUI
import SwiftData

@main
struct OneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        LaunchTimer.mark("app init")
        do {
            // UI tests launch with -uiTesting: a fresh in-memory store with the sample data.
            // -dataset <path> (with -uiTesting) loads tests/fixtures/today-dataset.json instead of the sample data.
            // -uiTestingStore <name> keeps the test store in a file, so a second launch can see what the first one saved.
            let args = ProcessInfo.processInfo.arguments
            let testing = args.contains("-uiTesting")
            let inMemory = testing
            if inMemory { SampleData.resetFlags() }
            let configuration: ModelConfiguration
            if testing, let i = args.firstIndex(of: "-uiTestingStore"), i + 1 < args.count {
                configuration = ModelConfiguration(url: FileManager.default.temporaryDirectory.appending(path: "\(args[i + 1]).store"))
            } else {
                configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            }
            container = try ModelContainer(for: OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self, ChatThread.self,
                                           configurations: configuration)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
        LaunchTimer.mark("container ready")
        Reminders.shared.configure(container)
        RemindersSync.shared.configure(container)
        WidgetFeed.configure(container)
        LaunchTimer.mark("reminders configured")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }
}
