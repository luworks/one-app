import Foundation

/// How an Apple Calendar event is found again by its time, not only by its identifier. Foundation only (tested by `swift test`).
/// A repeating event's identifier is shared by every occurrence (looking it up alone gives the FIRST one), and iCloud /
/// Exchange sync can re-key an event Today created; both are matched by start time, within a minute.
public enum EventMatch {
  /// Starts this close count as the same time (EventKit rounds and sync can shift seconds).
  public static let tolerance: TimeInterval = 60

  public static func sameStart(_ a: Date, _ b: Date) -> Bool {
    abs(a.timeIntervalSince(b)) < tolerance
  }

  /// The occurrence of event `id` that starts at `start`, among `candidates` (identifier, start).
  public static func occurrence(
    _ id: String, at start: Date, in candidates: [(id: String?, start: Date)]
  ) -> Int? {
    candidates.firstIndex { $0.id == id && sameStart($0.start, start) }
  }

  /// The re-keyed copy of an event titled `title` starting at `start`: same title, same start.
  public static func copy(
    titled title: String, at start: Date, in candidates: [(title: String?, start: Date)]
  ) -> Int? {
    candidates.firstIndex { $0.title == title && sameStart($0.start, start) }
  }
}
