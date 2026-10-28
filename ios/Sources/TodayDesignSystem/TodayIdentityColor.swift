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
      // Native picker colors may be outside sRGB; store an opaque, bounded sRGB choice.
      func byte(_ component: CGFloat) -> UInt32 {
        UInt32((min(1, max(0, component)) * 255).rounded())
      }
      self.init(rgb: byte(red) << 16 | byte(green) << 8 | byte(blue))
    }
  }
#endif
