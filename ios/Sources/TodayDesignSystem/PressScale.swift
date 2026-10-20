#if os(iOS)
  import SwiftUI

  /// Shared interaction tokens. Family-specific appearance stays in PillStyle and native row actions.
  public enum ButtonConfiguration {
    public static let minimumHitSize: CGFloat = 44
    public static let pressedScale: CGFloat = 0.97
    public static let responseDuration: TimeInterval = 0.15
    public static let responseAnimation = Animation.easeOut(duration: responseDuration)

    public enum Icon {
      public static let font = Font.system(size: 20, weight: .medium)
      public static let actionFont = Font.body.weight(.semibold)
      public static let size: CGFloat = 50
      public static let selectedFill = Color(.tertiarySystemFill)
      public static let background = Color(.secondarySystemBackground)
    }
  }

  public struct PressScale: ButtonStyle {
    public init() {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(
          configuration.isPressed && !reduceMotion ? ButtonConfiguration.pressedScale : 1
        )
        .animation(
          reduceMotion ? nil : ButtonConfiguration.responseAnimation,
          value: configuration.isPressed
        )
        .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in
          pressed
        }
    }
  }
#endif
