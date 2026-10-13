import SwiftUI
import SwiftData

@main
struct OneApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: OneTask.self, OneEvent.self, Habit.self)
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
