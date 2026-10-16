import Foundation
import SwiftData

/// Retired: habits were removed from the product. The model stays in the store schema only so that
/// existing installs migrate without losing data. Nothing reads or writes it any more.
@Model
final class Habit {
    var title: String
    var icon: String
    var createdAt: Date
    var checkins: [Date] = []
    var targetPerWeek: Int = 7
    var reminderHour: Int? = nil
    var reminderMinute: Int = 0

    init(title: String, icon: String = "circle.dashed") {
        self.title = title
        self.icon = icon
        self.createdAt = .now
    }
}
