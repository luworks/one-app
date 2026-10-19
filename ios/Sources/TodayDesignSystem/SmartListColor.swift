#if os(iOS)
import SwiftUI
import TodayCore

package extension SmartList {
    package var color: Color {
        switch self {
        case .today: Color(.systemBlue)
        case .scheduled: Color(.systemRed)
        case .all: Color(UIColor { $0.userInterfaceStyle == .dark ? .systemGray2 : .darkGray })
        case .flagged: Color(.systemOrange)
        case .completed: Color(.systemGray)
        }
    }

}
#endif
