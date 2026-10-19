import Foundation

/// The five smart lists at the top of Apple Reminders.
public enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case today, scheduled, all, flagged, completed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .all: "All"
        case .flagged: "Flagged"
        case .completed: "Completed"
        }
    }

    public var symbol: String {
        switch self {
        case .today: "calendar"
        case .scheduled: "calendar.badge.clock"
        case .all: "tray.fill"
        case .flagged: "flag.fill"
        case .completed: "checkmark"
        }
    }

}
