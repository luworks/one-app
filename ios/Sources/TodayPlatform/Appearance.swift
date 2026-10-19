#if os(iOS)
import TodayCore
import TodayShared
import SwiftUI
import UIKit

public extension Appearance {
    /// nil = follow the system.
    var colorScheme: ColorScheme? {
        forcesDark.map { $0 ? .dark : .light }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        UIUserInterfaceStyle(rawValue: userInterfaceStyleRawValue) ?? .unspecified
    }

    /// Composition may explicitly supply an initial choice before creating views.
    /// A nil choice preserves the value already stored in these defaults.
    static func applyConfiguration(_ appearance: Appearance?, defaults: UserDefaults) {
        if let appearance { defaults.set(appearance.rawValue, forKey: storageKey) }
    }

    /// Update only windows owned by the caller. System appearance uses `.unspecified`.
    @MainActor
    func applyToWindows(_ windows: [UIWindow]) {
        for window in windows where window.overrideUserInterfaceStyle != userInterfaceStyle {
            window.overrideUserInterfaceStyle = userInterfaceStyle
        }
    }
}

/// The root supplies its defaults and window ownership, including newly created windows.
@MainActor
private struct AppearanceRoot: ViewModifier {
    @AppStorage private var stored: String
    private let windows: @MainActor () -> [UIWindow]

    init(defaults: UserDefaults, windows: @escaping @MainActor () -> [UIWindow]) {
        _stored = AppStorage(wrappedValue: Appearance.default.rawValue, Appearance.storageKey, store: defaults)
        self.windows = windows
    }

    private var appearance: Appearance { Appearance(stored: stored) }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear { appearance.applyToWindows(windows()) }
            .onChange(of: stored) { _, _ in appearance.applyToWindows(windows()) }
            // Global notifications only trigger a refresh of the caller's owned windows.
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
                appearance.applyToWindows(windows())
            }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in
                appearance.applyToWindows(windows())
            }
    }
}

public extension View {
    /// Production supplies its app windows; each Workbench session supplies only its own window.
    @MainActor
    func appearanceRoot(defaults: UserDefaults, windows: @escaping @MainActor () -> [UIWindow]) -> some View {
        modifier(AppearanceRoot(defaults: defaults, windows: windows))
    }
}
#endif
