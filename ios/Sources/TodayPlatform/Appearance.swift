#if os(iOS)
import TodayCore
import TodayShared
import TodayPlatform
import SwiftUI
import UIKit

extension Appearance {
    /// nil = follow the system.
    var colorScheme: ColorScheme? {
        forcesDark.map { $0 ? .dark : .light }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        UIUserInterfaceStyle(rawValue: userInterfaceStyleRawValue) ?? .unspecified
    }

    /// Sets the style on every window of the app, so what UIKit presents (Apple's event editor, system alerts, share
    /// sheets, menus) matches. `.unspecified` hands control back to the system.
    /// Before the first view: UI test launch arguments may set (or reset) the saved choice, see `launchOverride`.
    static func applyLaunchOverride() {
        if let forced = launchOverride(arguments: ProcessInfo.processInfo.arguments) {
            UserDefaults.standard.set(forced.rawValue, forKey: storageKey)
        }
    }

    @MainActor
    func applyToWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != userInterfaceStyle {
                window.overrideUserInterfaceStyle = userInterfaceStyle
            }
        }
    }
}

/// Applies the saved Appearance to the whole app: SwiftUI (sheets, alerts and menus included) through
/// `preferredColorScheme`, UIKit-presented screens through the window override.
private struct AppearanceRoot: ViewModifier {
    @AppStorage(Appearance.storageKey) private var stored = Appearance.default.rawValue

    private var appearance: Appearance { Appearance(stored: stored) }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear {
                appearance.applyToWindows()
            }
            .onChange(of: stored) { _, _ in appearance.applyToWindows() }
            // A new window or scene (a second iPad window, a window created later) gets the choice too.
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in appearance.applyToWindows() }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in appearance.applyToWindows() }
    }
}

extension View {
    /// Put once at the root of the app.
    func appearanceRoot() -> some View { modifier(AppearanceRoot()) }
}


#endif
