import Foundation

/// The alarm wheel lab (a Debug-only page): three time pickers compared on the same set-a-time tasks. Nothing here
/// creates an alarm; trials are only recorded on this iPhone and exported by hand.
public enum WheelLabVariant: String, Codable, CaseIterable, Sendable {
  /// Today's real alarm picker: the system wheel `DatePicker`, configured as in the alarm editor.
  case a = "A"
  /// The custom wheel with fixed spacing.
  case b = "B"
  /// The same custom wheel; only the minute column's spacing follows the finger speed.
  case c = "C"

  public var title: String {
    switch self {
    case .a: "A · System"
    case .b: "B · Fixed"
    case .c: "C · Speed"
    }
  }
}

public enum WheelLabCategory: String, Codable, CaseIterable, Sendable {
  case near, far, exact, boundary
}

/// One set-a-time task: the wheel starts at `start` and the user sets `target` (minutes of the day). The target is
/// shown to the user and used for scoring only; the wheel never sees it.
public struct WheelLabTask: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let category: WheelLabCategory
  public let start: Int
  public let target: Int

  public init(_ id: String, _ category: WheelLabCategory, start: Int, target: Int) {
    self.id = id
    self.category = category
    self.start = start
    self.target = target
  }

  public static let all: [WheelLabTask] = [
    WheelLabTask("0730-0731", .near, start: 7 * 60 + 30, target: 7 * 60 + 31),
    WheelLabTask("0732-0729", .near, start: 7 * 60 + 32, target: 7 * 60 + 29),
    WheelLabTask("0735-0732", .near, start: 7 * 60 + 35, target: 7 * 60 + 32),
    WheelLabTask("0710-0747", .far, start: 7 * 60 + 10, target: 7 * 60 + 47),
    WheelLabTask("0700-0717", .exact, start: 7 * 60, target: 7 * 60 + 17),
    WheelLabTask("0750-0732", .exact, start: 7 * 60 + 50, target: 7 * 60 + 32),
    WheelLabTask("0700-0847", .exact, start: 7 * 60, target: 8 * 60 + 47),
    WheelLabTask("0758-0801", .boundary, start: 7 * 60 + 58, target: 8 * 60 + 1),
    WheelLabTask("1150-1210", .boundary, start: 11 * 60 + 50, target: 12 * 60 + 10),
  ]
}

/// One trial in a session's plan.
public struct WheelLabStep: Equatable, Sendable {
  public let variant: WheelLabVariant
  /// 1, 2 or 3: where this variant's block sits in the session.
  public let block: Int
  public let task: WheelLabTask
}

public enum WheelLabPlan {
  /// All six orders of A, B and C, so sessions 1-6 counterbalance which version comes first, second and last.
  public static let orders: [[WheelLabVariant]] = [
    [.a, .b, .c], [.b, .c, .a], [.c, .a, .b], [.a, .c, .b], [.c, .b, .a], [.b, .a, .c],
  ]

  /// Session `session` (1-based): three blocks, each with every task once in a shuffled order. The same session
  /// number always gives the same plan.
  public static func steps(session: Int) -> [WheelLabStep] {
    let order = orders[(max(session, 1) - 1) % orders.count]
    var rng = SplitMix64(seed: UInt64(max(session, 1)) &* 0x9E37_79B9_7F4A_7C15)
    var steps: [WheelLabStep] = []
    for (index, variant) in order.enumerated() {
      for task in WheelLabTask.all.shuffled(using: &rng) {
        steps.append(WheelLabStep(variant: variant, block: index + 1, task: task))
      }
    }
    return steps
  }
}

/// A small seeded generator so a session's task order is reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64
  public init(seed: UInt64) { state = seed }
  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// Counts what happened during one trial, fed by the page as it happens. Times are seconds on one monotonic clock.
public struct WheelLabCounter: Equatable, Sendable {
  public let task: WheelLabTask
  public let shownAt: Double
  public private(set) var firstTouchAt: Double?
  public private(set) var touches = 0
  public private(set) var reversals = 0
  public private(set) var wrongConfirms = 0
  public private(set) var overshoots = 0
  /// Time spent waiting with no finger down while the wheel was still moving.
  public private(set) var inertiaWait: Double = 0
  private var liftedAt: Double?
  private var farSide = false

  public init(task: WheelLabTask, shownAt: Double) {
    self.task = task
    self.shownAt = shownAt
  }

  /// A wait longer than this was not spent watching the wheel (A reports no motion, only the value it lands on).
  public static let maxInertiaWait = 3.0

  /// A finger touched the wheel; if it was still coasting after the last lift, the wait so far counts.
  public mutating func touchDown(at time: Double) {
    if firstTouchAt == nil { firstTouchAt = time }
    touches += 1
    endWait(at: time)
  }

  /// The finger lifted while the wheel may keep moving; the wait ends at `settled` or the next touch.
  public mutating func lifted(at time: Double) { liftedAt = time }

  public mutating func reversal() { reversals += 1 }

  /// The wheel came to rest on `minutes` (minutes of the day). Going past the target counts as an overshoot once
  /// each time the time lands on the far side.
  public mutating func settled(minutes: Int, at time: Double) {
    endWait(at: time)
    let far = WheelLabCounter.isPastTarget(minutes, start: task.start, target: task.target)
    if far && !farSide { overshoots += 1 }
    farSide = far
  }

  public mutating func wrongConfirm() { wrongConfirms += 1 }

  private mutating func endWait(at time: Double) {
    if let liftedAt, time - liftedAt <= Self.maxInertiaWait {
      inertiaWait += max(time - liftedAt, 0)
    }
    liftedAt = nil
  }

  /// Whether `minutes` lies beyond `target` as seen from `start`, going the short way round the day.
  public static func isPastTarget(_ minutes: Int, start: Int, target: Int) -> Bool {
    let toTarget = signedDelta(from: start, to: target)
    let toValue = signedDelta(from: target, to: minutes)
    return toTarget != 0 && toValue != 0 && (toTarget > 0) == (toValue > 0)
  }

  /// The shortest signed distance between two minutes of the day, in -719...720.
  public static func signedDelta(from a: Int, to b: Int) -> Int {
    let d = ((b - a) % 1440 + 1440) % 1440
    return d > 720 ? d - 1440 : d
  }
}

/// A finished trial (the right time was confirmed), as saved and exported.
public struct WheelLabTrial: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var date: Date
  public var session: Int
  public var block: Int
  public var variant: WheelLabVariant
  public var taskID: String
  public var category: WheelLabCategory
  public var start: Int
  public var target: Int
  /// From the task appearing to the right time confirmed.
  public var shownToConfirm: Double
  /// From the first touch on the wheel to the right time confirmed; nil if the wheel was never touched.
  public var firstTouchToConfirm: Double?
  public var wrongConfirms: Int
  public var overshoots: Int
  /// In-gesture reversals, from the custom wheel only (nil for A: the system wheel does not report them).
  public var reversals: Int?
  public var touches: Int
  public var inertiaWait: Double
  public var reduceMotion: Bool
  public var voiceOver: Bool
  public var device: String
  public var system: String
  public var build: String

  public init(
    id: UUID, date: Date, session: Int, block: Int, variant: WheelLabVariant,
    counter: WheelLabCounter, confirmedAt: Double, reduceMotion: Bool, voiceOver: Bool,
    device: String, system: String, build: String
  ) {
    self.id = id
    self.date = date
    self.session = session
    self.block = block
    self.variant = variant
    taskID = counter.task.id
    category = counter.task.category
    start = counter.task.start
    target = counter.task.target
    shownToConfirm = max(confirmedAt - counter.shownAt, 0)
    firstTouchToConfirm = counter.firstTouchAt.map { max(confirmedAt - $0, 0) }
    wrongConfirms = counter.wrongConfirms
    overshoots = counter.overshoots
    reversals = variant == .a ? nil : counter.reversals
    touches = counter.touches
    inertiaWait = counter.inertiaWait
    self.reduceMotion = reduceMotion
    self.voiceOver = voiceOver
    self.device = device
    self.system = system
    self.build = build
  }
}

/// How a version felt, asked after each block: 1 (no) to 5 (yes).
public struct WheelLabRating: Codable, Equatable, Sendable {
  public var date: Date
  public var session: Int
  public var variant: WheelLabVariant
  public var easyToStop: Int
  public var inControl: Int

  public init(date: Date, session: Int, variant: WheelLabVariant, easyToStop: Int, inControl: Int) {
    self.date = date
    self.session = session
    self.variant = variant
    self.easyToStop = easyToStop
    self.inControl = inControl
  }
}

/// Everything the lab saved, in one small JSON file.
public struct WheelLabLog: Codable, Equatable, Sendable {
  public var trials: [WheelLabTrial] = []
  public var ratings: [WheelLabRating] = []

  public init(trials: [WheelLabTrial] = [], ratings: [WheelLabRating] = []) {
    self.trials = trials
    self.ratings = ratings
  }

  /// The next session number (sessions are numbered from 1).
  public var nextSession: Int { (trials.map(\.session).max() ?? 0) + 1 }

  public static func load(from url: URL) -> WheelLabLog {
    guard let data = try? Data(contentsOf: url) else { return WheelLabLog() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(WheelLabLog.self, from: data)) ?? WheelLabLog()
  }

  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }

  /// One row per trial, for a spreadsheet.
  public var trialsCSV: String {
    let header =
      "date,session,block,variant,task,category,start,target,shown_to_confirm_s,"
      + "first_touch_to_confirm_s,wrong_confirms,overshoots,reversals,touches,inertia_wait_s,"
      + "reduce_motion,voiceover,device,system,build"
    let formatter = ISO8601DateFormatter()
    let rows = trials.map { t in
      [
        formatter.string(from: t.date), "\(t.session)", "\(t.block)", t.variant.rawValue, t.taskID,
        t.category.rawValue, Self.clock(t.start), Self.clock(t.target),
        Self.seconds(t.shownToConfirm), t.firstTouchToConfirm.map(Self.seconds) ?? "",
        "\(t.wrongConfirms)", "\(t.overshoots)", t.reversals.map { "\($0)" } ?? "", "\(t.touches)",
        Self.seconds(t.inertiaWait), t.reduceMotion ? "1" : "0", t.voiceOver ? "1" : "0",
        Self.csvField(t.device), Self.csvField(t.system), Self.csvField(t.build),
      ].joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n") + "\n"
  }

  public var ratingsCSV: String {
    let formatter = ISO8601DateFormatter()
    let rows = ratings.map {
      [
        formatter.string(from: $0.date), "\($0.session)", $0.variant.rawValue, "\($0.easyToStop)",
        "\($0.inControl)",
      ].joined(separator: ",")
    }
    return (["date,session,variant,easy_to_stop,in_control"] + rows).joined(separator: "\n") + "\n"
  }

  static func clock(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  static func seconds(_ value: Double) -> String { String(format: "%.3f", value) }

  static func csvField(_ text: String) -> String {
    text.contains(",") || text.contains("\"")
      ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
  }
}

/// Medians and slow tails per version and task kind, split into the first session (first use) and later ones.
public struct WheelLabSummary: Equatable, Sendable {
  public struct Row: Equatable, Sendable, Identifiable {
    public var id: String { "\(variant.rawValue)-\(category?.rawValue ?? "all")-\(familiar)" }
    public let variant: WheelLabVariant
    /// nil = every category.
    public let category: WheelLabCategory?
    /// false = session 1, true = sessions 2 and later.
    public let familiar: Bool
    public let count: Int
    /// First touch (or task shown, if never touched) to the right time confirmed.
    public let medianTime: Double
    /// The 90th percentile (nearest rank): how the slower trials went.
    public let slowTime: Double
    public let wrongConfirms: Int
    public let overshoots: Int
    public let medianTouches: Double
    public let medianInertiaWait: Double
  }

  public let rows: [Row]

  static let categories: [WheelLabCategory?] = [nil] + WheelLabCategory.allCases.map { $0 }

  public init(_ trials: [WheelLabTrial]) {
    var rows: [Row] = []
    for familiar in [false, true] {
      for variant in WheelLabVariant.allCases {
        for category in Self.categories {
          let group = trials.filter {
            $0.variant == variant && ($0.session > 1) == familiar
              && (category == nil || $0.category == category)
          }
          guard !group.isEmpty else { continue }
          let times = group.map { $0.firstTouchToConfirm ?? $0.shownToConfirm }
          rows.append(
            Row(
              variant: variant, category: category, familiar: familiar, count: group.count,
              medianTime: Self.median(times), slowTime: Self.percentile(times, 0.9),
              wrongConfirms: group.reduce(0) { $0 + $1.wrongConfirms },
              overshoots: group.reduce(0) { $0 + $1.overshoots },
              medianTouches: Self.median(group.map { Double($0.touches) }),
              medianInertiaWait: Self.median(group.map(\.inertiaWait))))
        }
      }
    }
    self.rows = rows
  }

  public static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  }

  /// Nearest-rank percentile (`p` in 0...1).
  public static func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let rank = Int((p * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank, 1), sorted.count) - 1]
  }
}
