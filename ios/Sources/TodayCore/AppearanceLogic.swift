import Foundation

/// The Appearance choice in Settings: follow the system (the default), always light, or always dark.
/// Plain Swift (no SwiftUI/UIKit) so the mapping runs under `swift test`; `Appearance.swift` turns it into
/// `ColorScheme` and `UIUserInterfaceStyle`.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    /// `@AppStorage` key. Not part of "Delete All Data".
    public static let storageKey = "today.appearance"
    public static let `default`: Appearance = .system

    /// A stored raw value (nil or unknown, e.g. from an older build) falls back to the default.
    public init(stored: String?) { self = stored.flatMap(Appearance.init(rawValue:)) ?? Appearance.default }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The order shown in Settings.
    public static let displayOrder: [Appearance] = [.system, .light, .dark]

    /// nil = follow the system, otherwise whether the app is forced dark.
    public var forcesDark: Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        }
    }

    /// `UIUserInterfaceStyle` raw values: 0 unspecified (follow the system), 1 light, 2 dark.
    public var userInterfaceStyleRawValue: Int {
        switch self {
        case .system: 0
        case .light: 1
        case .dark: 2
        }
    }

    /// UI tests: `-appearance light|dark|system` sets the choice at launch; without it a `-uiTesting` run starts on System,
    /// unless `-uiTestingKeepAppearance` is passed (the relaunch check of the saved choice). Returns the value to store, if any.
    public static func launchOverride(arguments: [String]) -> Appearance? {
        guard arguments.contains("-uiTesting") else { return nil }
        if let i = arguments.firstIndex(of: "-appearance"), i + 1 < arguments.count, let a = Appearance(rawValue: arguments[i + 1]) { return a }
        return arguments.contains("-uiTestingKeepAppearance") ? nil : .system
    }
}
