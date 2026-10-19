#if os(iOS)
  import SwiftUI
  import TodayCore

  package struct CircleButton: View {
    package init(
      systemImage: String, label: String, size: CGFloat = 50, action: @escaping () -> Void
    ) {
      self.systemImage = systemImage
      self.label = label
      self.size = size
      self.action = action
    }
    package let systemImage: String
    package let label: String
    package var size: CGFloat = 50
    package var action: () -> Void

    package var body: some View {
      Button(action: action) {
        Image(systemName: systemImage)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .frame(width: size, height: size)
          .glassCircle()
      }
      .buttonStyle(PressScale())
      .accessibilityLabel(label)
    }
  }

  /// 0.97 press scale with a light haptic.

  extension View {
    /// Liquid Glass on iOS 26+, material on older systems.
    @ViewBuilder
    package func glassCapsule() -> some View {
      if #available(iOS 26, *) {
        glassEffect(.regular.interactive(), in: Capsule())
      } else {
        background(.regularMaterial, in: Capsule())
      }
    }

    @ViewBuilder
    package func glassCircle() -> some View {
      if #available(iOS 26, *) {
        glassEffect(.regular.interactive(), in: Circle())
      } else {
        background(.regularMaterial, in: Circle())
      }
    }
  }

#endif
