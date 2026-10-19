import Foundation

/// The time Today reasons about. UI tests can pin it with `-uiTestingNow HH:mm` (today's date, that time).
public enum TodayClock {
    public static var now: Date {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingNow"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, let pinned = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) {
                return pinned
            }
        }
        #endif
        return .now
    }
}

