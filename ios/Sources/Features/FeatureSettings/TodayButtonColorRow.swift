#if os(iOS)
  import SwiftUI
  import TodayCore
  import TodayDesignSystem

  package struct TodayButtonColorRow: View {
    @AppStorage(TodayButtonColor.storageKey) private var stored = TodayButtonColor.green.stored
    package init() {}
    package var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        ColorPicker(
          "Today button color",
          selection: Binding(
            get: { TodayButtonColor(stored: stored).color },
            set: { stored = TodayButtonColor(color: $0).stored }
          ), supportsOpacity: false
        )
        .accessibilityIdentifier("settings.todayButtonColor.custom")
        .accessibilityValue(stored)
        HStack {
          ForEach(TodayButtonColor.presets, id: \.name) { preset in
            Button {
              stored = preset.color.stored
            } label: {
              Image(
                systemName: stored == preset.color.stored ? "checkmark.circle.fill" : "circle.fill"
              )
              .foregroundStyle(preset.color.color)
              .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preset.name)
            .accessibilityIdentifier("settings.todayButtonColor.\(preset.name)")
          }
        }
      }
    }
  }
#endif
