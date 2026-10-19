import Foundation

/// The remembered tab (`today.last.tab`) is saved as the tab's raw value. When a tab is renamed, old values must
/// still land on it, so nobody loses their place.
public enum TabMemory {
    /// Raw values saved by earlier versions, and the tab they became.
    public static let renamed: [String: String] = ["alarms": "clock"]

    /// The raw value to restore: the new name for a renamed tab, anything else unchanged.
    public static func migrated(_ raw: String) -> String { renamed[raw] ?? raw }
}
