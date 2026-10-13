import SwiftUI
import SwiftData

@main
struct OneApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [OneTask.self, OneEvent.self])
    }
}
