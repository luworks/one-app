#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import Foundation
import SwiftData

/// Retired: habits were removed from the product. The model stays in the store schema only so that
/// existing installs migrate without losing data. Nothing reads or writes it any more.
@Model
package final class Habit {
    package var title: String
    package var icon: String
    package var createdAt: Date
    package var checkins: [Date] = []
    package var targetPerWeek: Int = 7
    package var reminderHour: Int? = nil
    package var reminderMinute: Int = 0

    package init(title: String, icon: String = "circle.dashed") {
        self.title = title
        self.icon = icon
        self.createdAt = .now
    }
}
#endif
