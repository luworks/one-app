import Foundation

/// Commits at most once per touch, without using predicted velocity.
public struct WeekStripSwipe {
  public private(set) var hasCommitted = false
  public init() {}

  public mutating func update(x: CGFloat, y: CGFloat) -> Int? {
    guard !hasCommitted, abs(x) >= 36, abs(x) > abs(y) else { return nil }
    hasCommitted = true
    return x < 0 ? 1 : -1
  }

  public mutating func reset() { hasCommitted = false }
}
