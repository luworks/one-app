import SwiftUI
import UIKit

/// Home Screen quick actions (long-press the app icon): Ask AI, New task, New event.
@MainActor
@Observable
final class QuickAction {
    static let shared = QuickAction()
    /// The shortcut type waiting to be handled by HomeView.
    var pending: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WidgetFeed.registerBackgroundRefresh()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            let type = item.type
            Task { @MainActor in QuickAction.shared.pending = type }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in QuickAction.shared.pending = type }
        completionHandler(true)
    }
}
