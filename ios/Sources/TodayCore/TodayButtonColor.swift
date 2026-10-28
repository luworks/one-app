import Foundation

/// An opaque sRGB identity color, independent of calendar and reminder colors.
public struct TodayButtonColor: Equatable, Sendable {
  public static let storageKey = "today.buttonColor"
  public static let green = TodayButtonColor(rgb: 0x168449)
  public static let presets: [(name: String, color: TodayButtonColor)] = [
    ("Green", .green), ("Blue", TodayButtonColor(rgb: 0x246BCE)),
    ("Purple", TodayButtonColor(rgb: 0x8054BE)), ("Orange", TodayButtonColor(rgb: 0xBA5918)),
  ]
  public let rgb: UInt32
  public init(rgb: UInt32) { self.rgb = rgb & 0xFFFFFF }
  public init(stored: String?) {
    guard let stored, stored.count == 6, stored.allSatisfy({ $0.isHexDigit }),
      let rgb = UInt32(stored, radix: 16)
    else {
      self = .green
      return
    }
    self.init(rgb: rgb)
  }
  public var stored: String { String(format: "%06X", rgb) }
  public var red: Double { Double((rgb >> 16) & 255) / 255 }
  public var green: Double { Double((rgb >> 8) & 255) / 255 }
  public var blue: Double { Double(rgb & 255) / 255 }
}
