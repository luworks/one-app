#if os(iOS)
  import SwiftUI

  extension Color {
    /// Choose the higher-contrast text color for an opaque colored fill.
    package func contrastForeground(for scheme: ColorScheme) -> Color {
      let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
      let fill = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      guard fill.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .primary }
      func linear(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
      return luminance > 0.179 ? .black : .white
    }
  }
#endif
