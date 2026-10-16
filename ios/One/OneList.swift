import SwiftUI
import SwiftData

/// A reminder list (Apple Reminders calls these "My Lists"). Tasks belong to a list by name
/// (`OneTask.listName == OneList.name`; "" is the default list). When Apple Reminders is connected
/// each list mirrors an EKCalendar (`externalID`), so names and colors match what the user sees there.
@Model
final class OneList {
    var name: String
    /// Index into `ReminderPalette.colors`.
    var colorIndex: Int
    /// SF Symbol shown in the list's circle.
    var symbol: String
    var order: Int
    /// EKCalendar.calendarIdentifier when this list is mirrored from / to Apple Reminders.
    var externalID: String? = nil
    var createdAt: Date = Date.now

    init(name: String, colorIndex: Int = 6, symbol: String = "list.bullet", order: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
        self.symbol = symbol
        self.order = order
    }

    var color: Color { ReminderPalette.color(colorIndex) }
}

/// The colors and glyphs Apple Reminders offers for a list.
enum ReminderPalette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.23, blue: 0.19),   // red
        Color(red: 1.00, green: 0.58, blue: 0.00),   // orange
        Color(red: 1.00, green: 0.80, blue: 0.00),   // yellow
        Color(red: 0.20, green: 0.78, blue: 0.35),   // green
        Color(red: 0.00, green: 0.78, blue: 0.75),   // mint
        Color(red: 0.35, green: 0.78, blue: 0.98),   // sky
        Color(red: 0.00, green: 0.48, blue: 1.00),   // blue
        Color(red: 0.35, green: 0.34, blue: 0.84),   // indigo
        Color(red: 0.69, green: 0.32, blue: 0.87),   // purple
        Color(red: 1.00, green: 0.18, blue: 0.33),   // pink
        Color(red: 0.64, green: 0.52, blue: 0.37),   // brown
        Color(red: 0.56, green: 0.56, blue: 0.58),   // gray
    ]

    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }

    static let symbols: [String] = [
        "list.bullet", "bookmark.fill", "mappin", "gift.fill", "birthday.cake.fill", "graduationcap.fill",
        "backpack.fill", "pencil", "doc.fill", "book.fill", "creditcard.fill", "dumbbell.fill",
        "fork.knife", "pills.fill", "drop.fill", "leaf.fill", "pawprint.fill", "house.fill",
        "cart.fill", "airplane", "car.fill", "bed.double.fill", "gamecontroller.fill", "tv.fill",
        "music.note", "camera.fill", "phone.fill", "star.fill",
    ]
}
