#if os(iOS)
  import SwiftUI
  import TodayCore
  import TodayDesignSystem

  package struct TodayButtonColorRow: View {
    @AppStorage(TodayButtonColor.storageKey) private var stored = TodayButtonColor.green.stored
    @State private var showsPicker = false
    package init() {}
    package var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Button {
          showsPicker = true
        } label: {
          HStack {
            Text("Today button color").foregroundStyle(.primary)
            Spacer()
            Circle().fill(TodayButtonColor(stored: stored).color).frame(width: 28, height: 28)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.todayButtonColor.custom")
        .accessibilityValue(stored)
        .sheet(isPresented: $showsPicker) {
          NavigationStack {
            NativeTodayColorPicker(stored: $stored)
              .navigationTitle("Today button color")
              .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                  Button("Done") { showsPicker = false }
                    .accessibilityIdentifier("todayColorPicker.done")
                }
              }
          }
        }
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
  private struct NativeTodayColorPicker: UIViewControllerRepresentable {
    @Binding var stored: String
    func makeCoordinator() -> Coordinator { Coordinator(stored: $stored) }
    func makeUIViewController(context: Context) -> UIColorPickerViewController {
      let picker = UIColorPickerViewController()
      picker.supportsAlpha = false
      picker.selectedColor = UIColor(TodayButtonColor(stored: stored).color)
      picker.delegate = context.coordinator
      return picker
    }
    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
      var stored: Binding<String>
      init(stored: Binding<String>) { self.stored = stored }
      func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        stored.wrappedValue =
          TodayButtonColor(color: Color(uiColor: viewController.selectedColor)).stored
      }
    }
  }
#endif
