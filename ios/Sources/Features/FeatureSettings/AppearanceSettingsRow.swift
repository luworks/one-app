import SwiftUI
import TodayCore
import TodayDesignSystem

/// Settings → Appearance uses the same compact native menu as other preference rows.
package struct AppearanceSettingsRow: View {
    package init() {}
    @AppStorage(Appearance.storageKey) private var stored = Appearance.default.rawValue

    package var body: some View {
        MenuChoiceRow(title: "Appearance",
                      selection: Binding(get: { Appearance(stored: stored) }, set: { stored = $0.rawValue }),
                      identifier: "settings.appearance") {
            ForEach(Appearance.displayOrder, id: \.self) { appearance in
                Text(appearance.title)
                    .tag(appearance)
                    .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
            }
        }
        .pickerStyle(.menu)
    }
}
