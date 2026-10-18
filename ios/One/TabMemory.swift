import Foundation

/// The remembered tab (`today.last.tab`) is saved as the tab's raw value. When a tab is renamed, old values must
/// still land on it, so nobody loses their place.
enum TabMemory {
    /// Raw values saved by earlier versions, and the tab they became.
    static let renamed: [String: String] = ["alarms": "clock"]

    /// The raw value to restore: the new name for a renamed tab, anything else unchanged.
    static func migrated(_ raw: String) -> String { renamed[raw] ?? raw }
}
