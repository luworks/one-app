import Foundation

/// Commits at most once per touch, without using predicted velocity.
public struct WeekStripSwipe {
  private var committed = false
  public init() {}

  public mutating func update(x: CGFloat, y: CGFloat) -> Int? {
    guard !committed, abs(x) >= 36, abs(x) > abs(y) else { return nil }
    committed = true
    return x < 0 ? 1 : -1
  }

  public mutating func reset() { committed = false }
}
