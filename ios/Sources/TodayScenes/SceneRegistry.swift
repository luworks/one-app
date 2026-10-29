import Foundation

/// Stable automation handles. Changing a raw value breaks saved launch configurations.
public enum TodaySceneID: String, CaseIterable, Codable, Sendable, Identifiable {
  case today = "today"
  case calendarTwoDay = "calendar.twoday"
  case calendarMonth = "calendar.month"
  case calendarYear = "calendar.year"
  case calendarKey = "calendar.year.key"
  case calendarSources = "calendar.sources"
  case eventEditor = "calendar.event.editor"
  case reminders = "reminders"
  case remindersToday = "reminders.today"
  case remindersScheduled = "reminders.scheduled"
  case remindersAll = "reminders.all"
  case remindersFlagged = "reminders.flagged"
  case remindersCompleted = "reminders.completed"
  case remindersList = "reminders.list"
  case reminderEditor = "reminders.editor"
  case reminderQuickAdd = "reminders.quickAdd"
  case reminderListEditor = "reminders.listEditor"
  case clockAlarms = "clock.alarms"
  case alarmEditor = "clock.alarm.editor"
  case alarmSound = "clock.alarm.sound"
  case clockWorld = "clock.world"
  case cityPicker = "clock.world.cityPicker"
  case clockStopwatch = "clock.stopwatch"
  case clockTimer = "clock.timer"
  case ask = "ask"
  case askCapture = "ask.card.capture"
  case askStack = "ask.card.stack"
  case askChange = "ask.card.change"
  case askTidy = "ask.card.tidy"
  case activity = "activity"
  case search = "search"
  case settings = "settings"
  case settingsAppearance = "settings.appearance"
  case settingsApple = "settings.apple"
  case settingsToday = "settings.today"
  case settingsCalendar = "settings.calendar"
  case settingsReminders = "settings.reminders"
  case settingsSmartLists = "settings.smartLists"
  case settingsAlarms = "settings.alarms"
  case settingsAI = "settings.ai"
  case settingsActivity = "settings.activity"
  case settingsHolidays = "settings.calendar.holidays"
  case settingsAbout = "settings.about"
  case settingsDelete = "settings.delete"
  case health = "health"
  case healthDetail = "health.detail"
  case healthPicker = "health.picker"

  public var id: String { rawValue }
}

public enum SceneScenario: String, CaseIterable, Codable, Sendable {
  case normal, empty, loading, error, denied, revoked, dense, unavailable
}

public enum SceneCapability: String, Hashable, Codable, Sendable {
  case nativeInteraction, inMemoryModels, injectedClock, isolatedDefaults, mockHealth
  /// Existing app-only services need root assembly isolation before the scene may be opened.
  case legacyEnvironment
}

public struct SceneDescriptor: Identifiable, Equatable, Sendable {
  public let id: TodaySceneID
  public let title: String
  public let scenarios: Set<SceneScenario>
  public let capabilities: Set<SceneCapability>
  /// A private view or state without an injection seam is inventoried, never silently replaced.
  public let integrationBlocker: String?
}

public enum SceneConfigurationError: Error, Equatable, CustomStringConvertible {
  case unknownScene(String)
  case unknownScenario(String)
  case unsupported(TodaySceneID, SceneScenario)
  case invalidTimeZone(String)
  case invalidLocale(String)
  case invalidDate
  case missingValue(String)
  case integrationRequired(TodaySceneID, String)

  public var description: String {
    switch self {
    case .unknownScene(let value): "Unknown scene: \(value)"
    case .unknownScenario(let value): "Unknown scenario: \(value)"
    case .unsupported(let scene, let scenario):
      "\(scene.rawValue) does not support \(scenario.rawValue)."
    case .invalidTimeZone(let value): "Invalid time zone: \(value)"
    case .invalidLocale(let value): "Invalid locale: \(value)"
    case .invalidDate: "The scene clock must be finite."
    case .missingValue(let flag): "Missing value for \(flag)."
    case .integrationRequired(let scene, let reason): "\(scene.rawValue): \(reason)"
    }
  }
}

/// Value data only: safe to use from previews, screenshot tools, host tests and launch parsers.
public struct SceneConfiguration: Equatable, Codable, Sendable {
  public let scene: TodaySceneID
  public let scenario: SceneScenario
  public let now: Date
  public let uuidSeed: UInt64
  public let timeZoneIdentifier: String
  public let localeIdentifier: String

  public init(
    scene: TodaySceneID, scenario: SceneScenario = .normal,
    now: Date = Date(timeIntervalSince1970: 1_792_339_200), uuidSeed: UInt64 = 42,
    timeZoneIdentifier: String = "America/Los_Angeles", localeIdentifier: String = "en_US"
  ) throws {
    guard now.timeIntervalSince1970.isFinite else { throw SceneConfigurationError.invalidDate }
    guard TimeZone(identifier: timeZoneIdentifier) != nil else {
      throw SceneConfigurationError.invalidTimeZone(timeZoneIdentifier)
    }
    // Foundation may inventory zh_Hans_CN while saved launch configurations use zh_CN.
    // Compare maximized language identities to accept the same supported regional locale.
    let language = Locale.Language(identifier: localeIdentifier).maximalIdentifier
    guard
      Locale.availableIdentifiers.contains(localeIdentifier)
        || Locale.availableIdentifiers.contains(where: {
          Locale.Language(identifier: $0).maximalIdentifier == language
        })
    else {
      throw SceneConfigurationError.invalidLocale(localeIdentifier)
    }
    guard SceneRegistry.descriptor(for: scene).scenarios.contains(scenario) else {
      throw SceneConfigurationError.unsupported(scene, scenario)
    }
    self.scene = scene
    self.scenario = scenario
    self.now = now
    self.uuidSeed = uuidSeed
    self.timeZoneIdentifier = timeZoneIdentifier
    self.localeIdentifier = localeIdentifier
  }

  public var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: timeZoneIdentifier)!
    value.locale = Locale(identifier: localeIdentifier)
    return value
  }

  /// Stable byte algorithm, independent of Swift's randomized Hasher or platform endianness.
  public func uuid(at index: UInt64) -> UUID {
    var state = uuidSeed &+ index &* 0x9e37_79b9_7f4a_7c15
    func next() -> UInt8 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return UInt8(truncatingIfNeeded: state >> 32)
    }
    var bytes = (0..<16).map { _ in next() }
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  /// Decoding also enforces validation; synthesized decoding would bypass the initializer.
  private enum CodingKeys: String, CodingKey {
    case scene, scenario, now, uuidSeed, timeZoneIdentifier, localeIdentifier
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      scene: c.decode(TodaySceneID.self, forKey: .scene),
      scenario: c.decode(SceneScenario.self, forKey: .scenario),
      now: c.decode(Date.self, forKey: .now), uuidSeed: c.decode(UInt64.self, forKey: .uuidSeed),
      timeZoneIdentifier: c.decode(String.self, forKey: .timeZoneIdentifier),
      localeIdentifier: c.decode(String.self, forKey: .localeIdentifier))
  }
}

public enum SceneRegistry {
  public static var all: [SceneDescriptor] { TodaySceneID.allCases.map(descriptor) }

  public static func descriptor(for id: TodaySceneID) -> SceneDescriptor {
    var states: Set<SceneScenario> = [.normal]
    var capabilities: Set<SceneCapability> = [
      .nativeInteraction, .isolatedDefaults, .legacyEnvironment,
    ]

    switch id {
    case .today, .calendarTwoDay, .calendarMonth, .calendarYear,
      .reminders, .remindersToday, .remindersScheduled, .remindersAll, .remindersFlagged,
      .remindersCompleted, .remindersList:
      states.formUnion([.empty, .dense])
      capabilities.insert(.inMemoryModels)
    case .clockWorld, .cityPicker:
      states.formUnion([.empty, .dense])
      capabilities.remove(.legacyEnvironment)
      capabilities.insert(.injectedClock)
    case .clockStopwatch:
      states.formUnion([.empty, .dense])
      capabilities.remove(.legacyEnvironment)
      capabilities.insert(.injectedClock)
    case .health, .healthDetail:
      states.insert(.empty)
      if id == .health {
        // HealthSource availability and stalled queries feed real HealthView/HealthModel states.
        states.formUnion([.error, .unavailable])
      }
      capabilities.insert(.mockHealth)
      // HealthModel.row and HealthView's pushed detail still read TodayClock.now.
      // Detail itself accepts a clock and is already independent.
      if id == .healthDetail {
        capabilities.remove(.legacyEnvironment)
        capabilities.insert(.injectedClock)
      }
    case .healthPicker:
      capabilities.remove(.legacyEnvironment)
      capabilities.insert(.mockHealth)
    default: break
    }
    // Loading is transient; HealthKit cannot distinguish read denial from an empty answer.
    return SceneDescriptor(
      id: id, title: id.rawValue, scenarios: states,
      capabilities: capabilities, integrationBlocker: nil)
  }

  public static func configuration(arguments: [String]) throws -> SceneConfiguration {
    func value(_ flag: String) throws -> String? {
      guard let index = arguments.firstIndex(of: flag) else { return nil }
      guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
        throw SceneConfigurationError.missingValue(flag)
      }
      return arguments[index + 1]
    }
    let rawID = try value("-scene") ?? TodaySceneID.today.rawValue
    guard let id = TodaySceneID(rawValue: rawID) else {
      throw SceneConfigurationError.unknownScene(rawID)
    }
    let rawScenario = try value("-scenario") ?? SceneScenario.normal.rawValue
    guard let scenario = SceneScenario(rawValue: rawScenario) else {
      throw SceneConfigurationError.unknownScenario(rawScenario)
    }
    return try SceneConfiguration(
      scene: id, scenario: scenario,
      timeZoneIdentifier: value("-sceneTimeZone") ?? "America/Los_Angeles",
      localeIdentifier: value("-sceneLocale") ?? "en_US")
  }
}
