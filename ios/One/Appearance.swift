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

/// Settings → Appearance: System / Light / Dark as pills (the app's shared `PillSwitcher`).
struct AppearanceSection: View {
    @AppStorage(Appearance.storageKey) private var stored = Appearance.default.rawValue

    var body: some View {
        Section {
            PillSwitcher(items: Appearance.displayOrder,
                         selection: Binding(get: { Appearance(stored: stored) }, set: { stored = $0.rawValue }),
                         distribution: .equal,
                         title: { $0.title },
                         identifier: { "settings.appearance.\($0.rawValue)" })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your iPhone's Light or Dark setting. Widgets and Lock Screen follow the system.")
        }
    }
}
