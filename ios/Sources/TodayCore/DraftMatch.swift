import Foundation

/// Existing items whose words all appear in what the user is typing in Chat, so the Chat field doubles as search.
public enum DraftMatch {
  public struct Candidate: Equatable, Sendable {
    public let id: Int
    public let fields: [String]
    public let date: Date?
    public let isDone: Bool

    public init(id: Int, fields: [String], date: Date?, isDone: Bool = false) {
      self.id = id
      self.fields = fields
      self.date = date
      self.isDone = isDone
    }
  }

  /// Shorter drafts match too much to be useful.
  public static let minimumLength = 2

  /// Ids of the open matches: upcoming soonest first, then undated, then the past most recent first.
  public static func pick(_ draft: String, from candidates: [Candidate], now: Date, limit: Int = 3)
    -> [Int]
  {
    let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= minimumLength, limit > 0 else { return [] }
    return
      candidates
      .filter { !$0.isDone && SearchMatch.matches(query, in: $0.fields) }
      .sorted { rank($0, now) < rank($1, now) }
      .prefix(limit)
      .map(\.id)
  }

  private static func rank(_ c: Candidate, _ now: Date) -> (Int, Double, Int) {
    guard let date = c.date else { return (1, 0, c.id) }
    let t = date.timeIntervalSince(now)
    return t >= 0 ? (0, t, c.id) : (2, -t, c.id)
  }
}
