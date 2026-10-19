import Foundation

/// The numbers behind the stopwatch's analog face, with no SwiftUI: which tick is which, where the hands point, and the
/// measurements of the face. Lengths are points on a dial `referenceDiameter` wide; the view scales them to fit.
/// The face is modeled on Apple's Clock Stopwatch (measured from a 3x screenshot of it) and drawn from scratch.
public enum StopwatchDial {
  public static let referenceDiameter: Double = 305

  // MARK: Main ring: seconds

  /// Four ticks a second.
  public static let tickCount = 240

  public enum Tick: Equatable {
    /// Every 5 seconds: white, at the numerals.
    case major
    /// Every second: grey and long.
    case second
    /// Every quarter second: grey and short.
    case quarter
  }

  public static func tick(at index: Int) -> Tick {
    switch index % tickCount {
    case let i where i % 20 == 0: .major
    case let i where i % 4 == 0: .second
    default: .quarter
    }
  }

  /// Degrees clockwise from 12 o'clock.
  public static func angle(ofTick index: Int) -> Double { Double(index) * 360 / Double(tickCount) }

  /// The numerals 5, 10 … 60 around the ring.
  public static let numerals: [Int] = Array(stride(from: 5, through: 60, by: 5))

  /// 60 sits at the top, 5 at 30 degrees, 30 at the bottom.
  public static func numeralAngle(_ numeral: Int) -> Double { Double(numeral % 60) * 6 }

  /// The long orange hand: one turn a minute, moving smoothly (not in steps).
  public static func secondsHandAngle(elapsed: TimeInterval) -> Double {
    wrapped(max(0, elapsed), period: 60) * 360
  }

  // MARK: Sub-dial: the 30-minute counter

  /// One tick per 30 seconds.
  public static let subTickCount = 60

  public enum SubTick: Equatable {
    /// Every 5 minutes: white.
    case major
    /// Every minute: grey, longer.
    case minute
    /// The half minutes between: grey, shorter.
    case half
  }

  public static func subTick(at index: Int) -> SubTick {
    switch index % subTickCount {
    case let i where i % 10 == 0: .major
    case let i where i % 2 == 0: .minute
    default: .half
    }
  }

  public static func angle(ofSubTick index: Int) -> Double {
    Double(index) * 360 / Double(subTickCount)
  }

  /// The numerals 5, 10 … 30 of the counter.
  public static let subNumerals: [Int] = [5, 10, 15, 20, 25, 30]

  /// 30 sits at the top, 5 at 60 degrees, 15 at the bottom.
  public static func subNumeralAngle(_ numeral: Int) -> Double { Double(numeral % 30) * 12 }

  /// The short hand in the counter: one turn in 30 minutes.
  public static func minutesHandAngle(elapsed: TimeInterval) -> Double {
    wrapped(max(0, elapsed), period: 1800) * 360
  }

  private static func wrapped(_ value: TimeInterval, period: TimeInterval) -> Double {
    value.truncatingRemainder(dividingBy: period) / period
  }

  // MARK: Measurements (points on the reference dial; measured from the Clock app at 3x)

  public enum Metrics {
    public static let outerRadius = 152.3
    public static let tickWidth = 1.9
    public static let longTickLength = 12.7
    public static let shortTickLength = 6.9
    /// Grey ticks are the label color at this strength (white 27% on black).
    public static let greyTickOpacity = 0.27
    public static let numeralRadius = 119.0
    public static let numeralSize = 24.5
    /// The digital readout, below the middle of the dial.
    public static let readoutSize = 20.0
    public static let readoutOffset = 60.0

    public static let subCenterOffset = -54.7
    public static let subOuterRadius = 42.3
    public static let subMajorLength = 7.3
    public static let subMinuteLength = 4.0
    public static let subHalfLength = 2.4
    public static let subMajorWidth = 1.7
    public static let subTickWidth = 1.3
    public static let subNumeralRadius = 23.5
    public static let subNumeralSize = 13.0

    public static let secondsHandTip = 151.7
    public static let secondsHandTail = 30.2
    public static let handWidth = 1.8
    /// The hollow hub of the seconds hand: a ring of this outer radius and stroke.
    public static let hubOuterRadius = 4.0
    public static let hubStroke = 2.0
    public static let minutesHandLength = 42.7
    public static let minutesHubRadius = 2.9
  }
}

// MARK: - Laps, wording and the big digits

/// Which colour a finished lap gets once there are two to compare.
public enum LapMark: Equatable { case fastest, slowest }

extension StopwatchState {
  /// The mark for the finished lap at `index` (into `laps`): nil until there are two different laps.
  public func mark(forLap index: Int) -> LapMark? {
    if index == bestLapIndex { return .fastest }
    if index == worstLapIndex { return .slowest }
    return nil
  }

  /// The big digital page: minutes, seconds and hundredths with the language's own decimal mark ("00:05.75", "00:05,75").
  public static func digital(
    _ t: TimeInterval, decimalSeparator: String = Locale.current.decimalSeparator ?? "."
  ) -> String {
    let text = format(t)
    guard decimalSeparator != ".", let dot = text.lastIndex(of: ".") else { return text }
    return text.replacingCharacters(in: dot...dot, with: decimalSeparator)
  }

  /// What VoiceOver says. Stopped: exact to the hundredth ("Stopwatch, 5.75 seconds"). Running: whole seconds, so the
  /// label changes once a second instead of sixty times ("Stopwatch, 5 seconds, running").
  public static func spoken(_ t: TimeInterval, running: Bool) -> String {
    // 5.75 - 4.2 - 6.5 must not read 5.74
    let hundredths = Int((max(0, t) * 100 + 1e-6).rounded(.down))
    let shown = running ? hundredths / 100 * 100 : hundredths
    let h = shown / 360_000
    let m = shown / 6000 % 60
    let secondsPart = shown % 6000  // hundredths
    var parts: [String] = []
    if h > 0 { parts.append("\(h) " + (h == 1 ? "hour" : "hours")) }
    if m > 0 { parts.append("\(m) " + (m == 1 ? "minute" : "minutes")) }
    // Seconds are said when there are some, or when nothing else is.
    if secondsPart > 0 || parts.isEmpty {
      let whole = secondsPart / 100
      let cs = secondsPart % 100
      var number = "\(whole)"
      if cs > 0 { number += "." + (cs % 10 == 0 ? String(cs / 10) : String(format: "%02d", cs)) }
      parts.append(number + " " + (whole == 1 && cs == 0 ? "second" : "seconds"))
    }
    return "Stopwatch, " + parts.joined(separator: " ") + (running ? ", running" : "")
  }

  /// "Lap 2, 00:05.75, fastest".
  public static func spokenLap(number: Int, time: TimeInterval, mark: LapMark?) -> String {
    "Lap \(number), \(format(time))"
      + (mark == .fastest ? ", fastest" : mark == .slowest ? ", slowest" : "")
  }
}

/// Which face the Stopwatch shows; the dots between the buttons. Digital is the left dot, analog the right, as in Clock.
public enum StopwatchPage: String, CaseIterable {
  case digital, analog

  public static let defaultsKey = "today.stopwatch.page"

  public static func load(from defaults: UserDefaults) -> StopwatchPage {
    defaults.string(forKey: defaultsKey).flatMap(StopwatchPage.init(rawValue:)) ?? .analog
  }
}
