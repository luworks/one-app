import Foundation

/// Picks the Reminders list a new task most likely belongs to, on the device, from the list names and the titles
/// already in each list. Conservative on purpose: when the evidence is weak or two lists look equally likely, the
/// task stays in the Inbox. A walk must never be filed under Finance just because Finance is the default list.
public enum ListGuess {
  /// Below this confidence (0...1) the task goes to the Inbox.
  public static let threshold = 0.6
  /// The best list must beat the runner-up by at least this much, or the guess counts as ambiguous.
  public static let margin = 0.15

  public struct Candidate {
    public let name: String
    /// Titles of tasks already in the list.
    public let titles: [String]

    public init(name: String, titles: [String]) {
      self.name = name
      self.titles = titles
    }
  }

  public struct Result: Equatable {
    /// The chosen list, or nil for the Inbox.
    public let list: String?
    public let confidence: Double

    public init(list: String? = nil, confidence: Double) {
      self.list = list
      self.confidence = confidence
    }
  }

  /// The list that plays the Inbox ("00 收件箱", "Inbox"), if the user has one.
  public static func inbox(in names: [String]) -> String? {
    names.first { n in
      let l = n.lowercased()
      return l.contains("inbox") || n.contains("收件箱")
    }
  }

  /// The list for `title`, or nil (Inbox) when no list is a confident, unambiguous match.
  public static func guess(_ title: String, lists: [Candidate]) -> Result {
    let words = tokens(title)
    let inboxName = inbox(in: lists.map(\.name))
    guard !words.isEmpty else { return Result(list: nil, confidence: 0) }
    let scored = lists.filter { $0.name != inboxName }
      .map { ($0.name, score(words, $0)) }
      .sorted { $0.1 > $1.1 }
    guard let best = scored.first, best.1 > 0 else { return Result(list: nil, confidence: 0) }
    let second = scored.dropFirst().first?.1 ?? 0
    let confidence = best.1 - second < margin ? 0 : best.1
    return Result(list: confidence >= threshold ? best.0 : nil, confidence: confidence)
  }

  /// 0...1. A word of the list's name in the title is a strong sign; a near-copy of a task already in the list is another.
  /// Each one alone can pass the threshold; together they reinforce each other.
  static func score(_ words: Set<String>, _ list: Candidate) -> Double {
    let nameHit = !tokens(list.name).isDisjoint(with: words) ? 0.7 : 0
    let best =
      list.titles.map { t -> Double in
        let shared = words.intersection(tokens(t)).count
        // One shared word is too easily chance ("call", "买"); a one-word title has to match exactly.
        guard shared >= 2 || (shared == 1 && words.count == 1) else { return 0 }
        return Double(shared) / Double(words.count)
      }.max() ?? 0
    let titleHit = best * 0.85
    return 1 - (1 - nameHit) * (1 - titleHit)
  }

  /// Lowercased Latin words (3+ letters, light plural stemming) and Chinese character pairs, without filler words.
  public static func tokens(_ text: String) -> Set<String> {
    var out = Set<String>()
    let lower = text.lowercased()
    var word = ""
    var run: [Character] = []
    func flushWord() {
      if word.count >= 3, !word.allSatisfy(\.isNumber), !stopWords.contains(word) {
        out.insert(word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word)
      }
      word = ""
    }
    func flushRun() {
      if run.count >= 2 {
        for i in 0..<(run.count - 1) {
          let pair = String(run[i...i + 1])
          if !stopPairs.contains(pair) { out.insert(pair) }
        }
      }
      run = []
    }
    for ch in lower {
      if isCJK(ch) {
        flushWord()
        run.append(ch)
      } else if ch.isLetter || ch.isNumber {
        flushRun()
        word.append(ch)
      } else {
        flushWord()
        flushRun()
      }
    }
    flushWord()
    flushRun()
    return out
  }

  private static func isCJK(_ ch: Character) -> Bool {
    ch.unicodeScalars.contains {
      (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
    }
  }

  private static let stopWords: Set<String> = [
    "the", "and", "for", "with", "from", "this", "that", "today", "tomorrow", "tonight", "remind",
    "reminder",
    "need", "please", "about", "into", "your", "every", "day", "week", "morning", "evening",
    "afternoon",
  ]

  private static let stopPairs: Set<String> = [
    "今天", "明天", "后天", "昨天", "晚上", "下午", "上午", "早上", "中午", "一下", "提醒", "记得", "一定", "一个",
    "我们", "自己", "什么", "时候", "可以", "需要", "给我", "帮我", "添加", "每天", "这个", "那个",
  ]
}
