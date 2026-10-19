import Foundation
import TodayCore

/// Developer executable launch compatibility; excluded from the production dependency graph.
@MainActor
public enum HealthTestSelection {
    public static func make(defaults: UserDefaults, arguments: [String]) -> HealthSelectionStore {
        if arguments.contains("-uiTesting"), !arguments.contains("-uiTestingKeepHealthMetrics") {
            defaults.removeObject(forKey: HealthSelectionStore.defaultsKey)
            if let index = arguments.firstIndex(of: "-uiTestingHealthMetrics"), index + 1 < arguments.count {
                let selection = HealthSelection(shown: arguments[index + 1].split(separator: ",").compactMap {
                    HealthMetric(rawValue: String($0))
                })
                defaults.set(selection.encoded(), forKey: HealthSelectionStore.defaultsKey)
            }
        }
        return HealthSelectionStore(defaults: defaults)
    }
}
