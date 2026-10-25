import Foundation

/// Tuning for the experimental custom time wheel (Settings → Developer → Alarm wheel lab, variants B and C).
///
/// EXPERIMENTAL: every number here is a starting guess that still has to be validated by hand on an iPhone. None are
/// copied from the HTML prototype. Times are in seconds, distances in points, speeds in points per second (finger or
/// on-screen) or units per second (minutes or hours on the wheel), as each name says.
public struct TimeWheelTuning: Equatable, Sendable {
  /// Spacing between two values at rest: the row height of the wheel. B always, C when slow.
  public var finePointsPerUnit: Double = 34
  /// Spacing between two minutes at full speed in C, so a 5-minute step is about one row.
  public var coarsePointsPerUnit: Double = 7

  /// Touch samples newer than this feed the release velocity (least squares over their real timestamps).
  public var velocityWindow: Double = 0.08
  /// A move this long after the previous one means the finger had stopped: older samples are dropped.
  public var pauseGap: Double = 0.06
  /// Lifting the finger this long after its last move releases with no velocity.
  public var releaseStaleAfter: Double = 0.05
  /// Releases slower than this snap to the nearest value instead of coasting.
  public var minFlickSpeed: Double = 250
  /// A release only coasts after the finger moved this far since the touch began, its last pause or its last reversal.
  public var minFlickTravel: Double = 10
  /// Movement against the current direction must exceed this before it counts as a reversal (filters finger tremor).
  public var reversalTravel: Double = 6

  /// Exponential deceleration time constant of a coast (UIScrollView's normal rate, 0.998 per ms, is about 0.5 s;
  /// shorter here so a picker stops sooner).
  public var decelerationTau: Double = 0.4
  /// The fastest a coast may start, in units per second.
  public var maxCoastSpeed: Double = 80
  /// Time constant of the short snap to the nearest value after a slow release or a cancel.
  public var snapTau: Double = 0.06
  /// A coast hands over to the short snap this close to its target, so it does not crawl for seconds.
  public var snapHandoff: Double = 0.3
  /// A settle ends when the position is this close to its target.
  public var settleEpsilon: Double = 0.01

  /// Smoothing time constant of the finger speed that drives the spacing in C.
  public var speedSmoothingTau: Double = 0.1
  /// C keeps fine spacing below this smoothed speed (pt/s) ...
  public var coarseFrom: Double = 500
  /// ... and reaches full coarse spacing at this speed.
  public var coarseAt: Double = 1800
  /// How fast the spacing compresses when speed rises, and how slowly it opens again when speed drops (s).
  public var scaleRiseTau: Double = 0.08
  public var scaleFallTau: Double = 0.22

  /// At most one selection tick in this interval; faster crossings are merged, never queued.
  public var minTickInterval: Double = 0.03
  /// Above this many units per second only major values (multiples of `majorStep`) tick.
  public var majorOnlyAbove: Double = 20
  public var majorStep: Int = 5

  public init() {}

  public static let standard = TimeWheelTuning()
}

/// What a call into `TimeWheelColumn` caused, for the view (haptics, trial counters, accessibility).
public struct TimeWheelOutput: OptionSet, Equatable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  /// A selection tick should play now: the value changed and the haptic gate let it through.
  public static let tick = TimeWheelOutput(rawValue: 1 << 0)
  /// The finger turned back by more than the tremor threshold.
  public static let reversal = TimeWheelOutput(rawValue: 1 << 1)
  /// A touch stopped a coasting wheel where it was.
  public static let grab = TimeWheelOutput(rawValue: 1 << 2)
  /// The wheel came to rest on a whole value.
  public static let settled = TimeWheelOutput(rawValue: 1 << 3)
}

/// One column of the custom time wheel (minutes or hours), as plain arithmetic so it runs in `./dev test unit`.
///
/// Three things are kept apart: the continuous `position` (value units, unbounded so the wheel can wrap), the display
/// spacing (`pointsPerUnit`, which only C changes) and the whole `value` the user sees, confirms and hears. A finger
/// move of `dy` points moves `position` by `dy / pointsPerUnit`; the spacing is drawn around `position`, so changing it
/// never changes `value`. The wheel is never told a target: it only follows the finger.
///
/// Times are seconds on one monotonic clock (`UITouch.timestamp` and `CADisplayLink.timestamp` share it); y grows
/// downward and dragging up moves to later values, like Apple's wheels.
public struct TimeWheelColumn: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle, dragging, settling
  }

  struct Sample: Equatable, Sendable {
    var time: Double
    var y: Double
  }

  /// Values on the wheel: 60 minutes or 24 hours. They wrap; a minute wrap does not change the hour, as in Apple's
  /// time picker.
  public let count: Int
  /// Speed-sensitive spacing (variant C's minute column). Off: fixed spacing.
  public let adaptive: Bool
  public var tuning: TimeWheelTuning

  public private(set) var position: Double
  /// 0 = fine spacing, 1 = fully compressed. Always 0 when not adaptive.
  public private(set) var scale: Double = 0
  public private(set) var phase: Phase = .idle
  /// Smoothed finger speed (pt/s) while dragging; equivalent on-screen speed while coasting.
  public private(set) var speed: Double = 0

  private var samples: [Sample] = []
  private var lastY: Double = 0
  private var lastMoveTime: Double = 0
  private var lastStepTime: Double?
  private var travel: Double = 0
  private var direction: Double = 0
  private var extremeY: Double = 0
  /// This gesture grabbed a coasting wheel: it stays at fine spacing until the finger lifts and the wheel settles.
  private var fineLock = false
  private var settleFrom: Double = 0
  private var settleTarget: Double = 0
  private var settleTau: Double = 0
  private var settleStart: Double = 0
  /// Spacing when the coast began, to turn its unit speed into an on-screen speed without a feedback loop.
  private var settlePointsPerUnit: Double = 0
  private var lastRounded: Int
  private var lastTickTime = -Double.infinity

  public init(
    count: Int, value: Int, adaptive: Bool = false, tuning: TimeWheelTuning = .standard
  ) {
    self.count = count
    self.adaptive = adaptive
    self.tuning = tuning
    position = Double(Self.wrap(value, count))
    lastRounded = Self.wrap(value, count)
  }

  // MARK: Reading

  /// The whole value under the selection band: what is shown, confirmed and read by VoiceOver.
  public var value: Int { Self.wrap(rounded, count) }

  /// The unwrapped whole step nearest `position` (31.49 → 31, 31.5 → 32, -0.5 → 0).
  public var rounded: Int { Int((position + 0.5).rounded(.down)) }

  public var pointsPerUnit: Double {
    tuning.finePointsPerUnit + (tuning.coarsePointsPerUnit - tuning.finePointsPerUnit) * scale
  }

  public var isMoving: Bool { phase != .idle }

  /// Whether the view still needs display frames: moving, or the spacing still opening after a stop.
  public var needsFrames: Bool { phase != .idle || scale > 0 }

  /// The value a coast or snap will come to rest on.
  public var restingValue: Int {
    phase == .settling ? Self.wrap(Int(settleTarget), count) : value
  }

  // MARK: Touch

  /// A finger touched the column. A coasting wheel stops exactly where it is now and this gesture stays fine.
  public mutating func touchDown(y: Double, at time: Double) -> TimeWheelOutput {
    var out = TimeWheelOutput()
    if phase == .settling {
      out.formUnion(step(at: time))
      if phase == .settling {
        out.insert(.grab)
        fineLock = true
        scale = 0
      }
    } else {
      fineLock = false
    }
    phase = .dragging
    samples = [Sample(time: time, y: y)]
    lastY = y
    lastMoveTime = time
    lastStepTime = time
    travel = 0
    direction = 0
    extremeY = y
    speed = 0
    return out
  }

  /// The finger moved. Feed every coalesced touch, in order.
  public mutating func touchMove(y: Double, at time: Double) -> TimeWheelOutput {
    guard phase == .dragging else { return [] }
    var out = TimeWheelOutput()
    let dt = max(time - lastMoveTime, 0.001)
    let dy = y - lastY
    if time - lastMoveTime > tuning.pauseGap {
      // The finger had stopped: nothing before the pause may count towards a fling.
      samples.removeAll()
      travel = 0
      speed = 0
    }
    position -= dy / pointsPerUnit
    travel += abs(dy)
    samples.append(Sample(time: time, y: y))
    samples.removeAll { $0.time < time - tuning.velocityWindow }

    if direction == 0 {
      if abs(y - extremeY) >= tuning.reversalTravel {
        direction = y > extremeY ? 1 : -1
        extremeY = y
      }
    } else if (y - extremeY) * direction > 0 {
      extremeY = y
    } else if abs(y - extremeY) >= tuning.reversalTravel {
      // Turned back: forget the old speed and go fine again.
      out.insert(.reversal)
      direction = -direction
      travel = abs(y - extremeY)
      extremeY = y
      samples = [Sample(time: time, y: y)]
      speed = 0
      scale = 0
    }

    let instant = abs(dy) / dt
    speed += (instant - speed) * (1 - exp(-dt / tuning.speedSmoothingTau))
    lastY = y
    lastMoveTime = time
    updateScale(at: time)
    if noteValue(at: time, unitSpeed: speed / pointsPerUnit) { out.insert(.tick) }
    return out
  }

  /// The finger lifted. A quick release coasts and comes to rest on a whole value; a slow one snaps to the nearest.
  public mutating func touchUp(y: Double, at time: Double) -> TimeWheelOutput {
    guard phase == .dragging else { return [] }
    var out = TimeWheelOutput()
    if y != lastY { out.formUnion(touchMove(y: y, at: time)) }
    let velocity = releaseVelocity(at: time)
    let ppu = pointsPerUnit
    if abs(velocity) < tuning.minFlickSpeed || travel < tuning.minFlickTravel {
      beginSettle(to: Double(rounded), tau: tuning.snapTau, at: time)
    } else {
      let units = max(min(-velocity / ppu, tuning.maxCoastSpeed), -tuning.maxCoastSpeed)
      let target = ((position + units * tuning.decelerationTau) + 0.5).rounded(.down)
      // Match the start speed of the exponential approach to the release speed.
      let matched = (target - position) / units
      var tau = tuning.snapTau
      if matched.isFinite && matched > 0 {
        tau = min(max(matched, tuning.snapTau), 2 * tuning.decelerationTau)
      }
      beginSettle(to: target, tau: tau, at: time)
    }
    settlePointsPerUnit = ppu
    if phase == .idle { out.insert(.settled) }
    return out
  }

  /// The system cancelled the touch (a call, a system gesture): no fling, just snap to the nearest value.
  public mutating func touchCancel(at time: Double) -> TimeWheelOutput {
    guard phase == .dragging else { return [] }
    beginSettle(to: Double(rounded), tau: tuning.snapTau, at: time)
    settlePointsPerUnit = pointsPerUnit
    return phase == .idle ? .settled : []
  }

  // MARK: Frames

  /// Advances a coast or snap and the spacing to `time`. Call once per display frame while `isMoving`.
  public mutating func step(at time: Double) -> TimeWheelOutput {
    var out = TimeWheelOutput()
    switch phase {
    case .idle:
      speed = 0
      updateScale(at: time)
    case .dragging:
      if time - lastMoveTime > tuning.pauseGap, let last = lastStepTime {
        // A finger held still sends no events; let its speed die away so the spacing opens.
        speed *= exp(-max(time - last, 0) / tuning.speedSmoothingTau)
      }
      updateScale(at: time)
    case .settling:
      let t = max(time - settleStart, 0)
      position = settleTarget + (settleFrom - settleTarget) * exp(-t / settleTau)
      if settleTau > tuning.snapTau && abs(settleTarget - position) < tuning.snapHandoff {
        settleFrom = position
        settleStart = time
        settleTau = tuning.snapTau
      }
      let unitSpeed = abs(settleTarget - position) / settleTau
      speed = unitSpeed * settlePointsPerUnit
      if abs(settleTarget - position) < tuning.settleEpsilon {
        position = settleTarget
        speed = 0
        phase = .idle
        fineLock = false
        out.insert(.settled)
      }
      updateScale(at: time)
      if noteValue(at: time, unitSpeed: unitSpeed) { out.insert(.tick) }
    }
    return out
  }

  // MARK: Direct changes

  /// Ends any drag or coast on the nearest whole value at once (version switch, leaving the page, Save while moving).
  public mutating func stop() {
    position = Double(rounded)
    lastRounded = rounded
    phase = .idle
    scale = 0
    speed = 0
    samples.removeAll()
    fineLock = false
  }

  /// Shows `value` (a new trial's start time). Stops any motion; plays no tick.
  public mutating func set(value: Int) {
    stop()
    position = Double(Self.wrap(value, count))
    lastRounded = rounded
  }

  /// One step up or down (VoiceOver increment / decrement, the AM/PM switch with 12). Stops any motion.
  public mutating func nudge(by steps: Int) {
    stop()
    position += Double(steps)
    lastRounded = rounded
  }

  // MARK: Private

  private mutating func beginSettle(to target: Double, tau: Double, at time: Double) {
    samples.removeAll()
    if abs(target - position) < tuning.settleEpsilon {
      position = target
      phase = .idle
      speed = 0
      fineLock = false
      lastStepTime = time
      return
    }
    phase = .settling
    settleFrom = position
    settleTarget = target
    settleTau = tau
    settleStart = time
    lastStepTime = time
  }

  /// Least-squares slope of y over time for the recent samples, in pt/s; 0 if the finger has not moved lately.
  private func releaseVelocity(at time: Double) -> Double {
    guard time - lastMoveTime <= tuning.releaseStaleAfter else { return 0 }
    let recent = samples.filter { $0.time >= time - tuning.velocityWindow }
    guard recent.count >= 2 else { return 0 }
    let n = Double(recent.count)
    let meanT = recent.reduce(0) { $0 + $1.time } / n
    let meanY = recent.reduce(0) { $0 + $1.y } / n
    var num = 0.0
    var den = 0.0
    for s in recent {
      num += (s.time - meanT) * (s.y - meanY)
      den += (s.time - meanT) * (s.time - meanT)
    }
    return den > 0 ? num / den : 0
  }

  private mutating func updateScale(at time: Double) {
    let dt = max(time - (lastStepTime ?? time), 0)
    lastStepTime = time
    guard adaptive else {
      scale = 0
      return
    }
    let ramp = (speed - tuning.coarseFrom) / (tuning.coarseAt - tuning.coarseFrom)
    let goal = fineLock ? 0 : Self.smoothstep(ramp)
    let tau = goal > scale ? tuning.scaleRiseTau : tuning.scaleFallTau
    scale += (goal - scale) * (1 - exp(-dt / tau))
    if abs(goal - scale) < 0.0005 { scale = goal }
  }

  /// Whether a value change at `time` plays a tick: only real changes of the whole value, at most one per interval,
  /// and only major values when fast. A spacing change never moves `position`, so it can never tick.
  private mutating func noteValue(at time: Double, unitSpeed: Double) -> Bool {
    let now = rounded
    guard now != lastRounded else { return false }
    let from = lastRounded
    lastRounded = now
    guard time - lastTickTime >= tuning.minTickInterval else { return false }
    if unitSpeed > tuning.majorOnlyAbove {
      let low = min(from, now) + 1
      let high = max(from, now)
      let step = max(tuning.majorStep, 1)
      guard (low...high).contains(where: { Self.wrap($0, step) == 0 }) else { return false }
    }
    lastTickTime = time
    return true
  }

  static func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
  }

  public static func wrap(_ value: Int, _ count: Int) -> Int {
    ((value % count) + count) % count
  }
}
