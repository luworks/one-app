import SwiftUI
import SwiftData

@main
struct OneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        do {
            // UI tests launch with -uiTesting: a fresh in-memory store with the sample data.
            let testing = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            if testing { SampleData.resetFlags() }
            container = try ModelContainer(for: OneTask.self, OneEvent.self, Habit.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: testing))
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
        Reminders.shared.configure(container)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }
}
