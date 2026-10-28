#if os(iOS)
  import SwiftUI
  import TodayCore

  extension TodayButtonColor {
    package var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    package init(color: Color) {
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        self = .green
        return
      }
      self.init(
        rgb: UInt32((red * 255).rounded()) << 16
          | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded()))
    }
  }
#endif
