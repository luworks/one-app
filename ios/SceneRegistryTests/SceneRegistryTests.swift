import Foundation
import Testing

@testable import TodayScenes

struct SceneRegistryTests {
  @Test func persistedAutomationHandlesStayAvailable() throws {
    // External launch contract, grouped by user journeys rather than a tautological case count.
    let journeys = [
      ["today", "today.review"],
      [
        "calendar.week", "calendar.month", "calendar.year", "calendar.year.key",
        "calendar.event.editor",
      ],
      [
        "reminders", "reminders.today", "reminders.scheduled", "reminders.all", "reminders.flagged",
        "reminders.completed", "reminders.list", "reminders.editor", "reminders.quickAdd",
        "reminders.listEditor",
      ],
      [
        "clock.alarms", "clock.alarm.editor", "clock.alarm.sound", "clock.world",
        "clock.world.cityPicker", "clock.stopwatch", "clock.timer",
      ],
      [
        "ask", "ask.card.capture", "ask.card.stack", "ask.card.plan", "ask.card.change",
        "ask.card.tidy",
      ],
      [
        "activity", "settings", "settings.appearance", "settings.apple", "settings.today",
        "settings.calendar",
        "settings.reminders", "settings.smartLists", "settings.alarms", "settings.ai",
        "settings.ai.automaticChanges",
        "settings.activity", "settings.calendar.holidays", "settings.about", "settings.delete",
      ],
      ["health", "health.detail", "health.picker"],
    ]
    for handle in journeys.flatMap({ $0 }) {
      let config = try SceneRegistry.configuration(arguments: ["-scene", handle])
      #expect(config.scene.rawValue == handle)
    }
    let handles = SceneRegistry.all.map(\.id.rawValue)
    #expect(Set(handles).count == handles.count)
    #expect(handles.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
  }

  @Test func everyDeclaredScenarioIsValidatedAndEveryOtherScenarioIsRejected() throws {
    for descriptor in SceneRegistry.all {
      #expect(descriptor.scenarios.contains(.normal))
      #expect(descriptor.capabilities.contains(.nativeInteraction))
      for scenario in SceneScenario.allCases {
        if descriptor.scenarios.contains(scenario) {
          let config = try SceneConfiguration(scene: descriptor.id, scenario: scenario)
          #expect(config.scenario == scenario)
        } else {
          #expect(throws: SceneConfigurationError.unsupported(descriptor.id, scenario)) {
            try SceneConfiguration(scene: descriptor.id, scenario: scenario)
          }
        }
      }
    }
  }

  @Test func nativeFixtureCapabilitiesAreTruthful() {
    #expect(SceneRegistry.descriptor(for: .clockWorld).capabilities.contains(.injectedClock))
    #expect(SceneRegistry.descriptor(for: .clockStopwatch).capabilities.contains(.isolatedDefaults))
    #expect(SceneRegistry.descriptor(for: .healthDetail).capabilities.contains(.mockHealth))
    #expect(!SceneRegistry.descriptor(for: .health).scenarios.contains(.denied))
    #expect(!SceneRegistry.descriptor(for: .reminderEditor).scenarios.contains(.dense))
    #expect(SceneRegistry.descriptor(for: .settingsSmartLists).integrationBlocker == nil)
    #expect(SceneRegistry.descriptor(for: .settingsToday).integrationBlocker == nil)
    #expect(SceneRegistry.descriptor(for: .settingsApple).capabilities.contains(.legacyEnvironment))
    #expect(SceneRegistry.descriptor(for: .health).scenarios.contains(.error))
    #expect(SceneRegistry.descriptor(for: .health).scenarios.contains(.unavailable))
    #expect(!SceneRegistry.descriptor(for: .healthDetail).scenarios.contains(.error))
    #expect(!SceneRegistry.descriptor(for: .healthPicker).scenarios.contains(.unavailable))
    #expect(!SceneRegistry.descriptor(for: .health).scenarios.contains(.loading))
  }

  @Test func configurationRoundTripPreservesClockCalendarAndIdentity() throws {
    let config = try SceneConfiguration(
      scene: .calendarWeek, scenario: .dense,
      now: Date(timeIntervalSince1970: 1_794_123_456), uuidSeed: 73,
      timeZoneIdentifier: "Asia/Shanghai", localeIdentifier: "zh_CN")
    let decoded = try JSONDecoder().decode(
      SceneConfiguration.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
    #expect(decoded.calendar.timeZone.identifier == "Asia/Shanghai")
    #expect(decoded.calendar.locale?.identifier == "zh_CN")
    #expect(decoded.uuid(at: 5) == config.uuid(at: 5))
    #expect(decoded.uuid(at: 5) != config.uuid(at: 6))
    let anotherSeed = try SceneConfiguration(scene: .calendarWeek, uuidSeed: 74)
    #expect(anotherSeed.uuid(at: 5) != config.uuid(at: 5))
    #expect(Set((0..<1_000).map { config.uuid(at: UInt64($0)) }).count == 1_000)
  }

  @Test func uuidAlgorithmPreservesSavedFixtureIdentities() throws {
    let config = try SceneConfiguration(scene: .today)
    #expect(config.uuid(at: 0).uuidString == "EDA5A53F-AC19-422D-BC7B-112DC4E4596B")
  }

  @Test func invalidDecodedConfigurationCannotBypassValidation() throws {
    let config = try SceneConfiguration(scene: .reminderEditor)
    let data = try JSONEncoder().encode(config)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["scenario"] = "loading"
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: SceneConfigurationError.unsupported(.reminderEditor, .loading)) {
      try JSONDecoder().decode(SceneConfiguration.self, from: invalid)
    }
    #expect(throws: SceneConfigurationError.invalidTimeZone("Unknown/Zone")) {
      try SceneConfiguration(scene: .today, timeZoneIdentifier: "Unknown/Zone")
    }
    #expect(throws: SceneConfigurationError.invalidLocale("invalid_locale_123")) {
      try SceneConfiguration(scene: .today, localeIdentifier: "invalid_locale_123")
    }
    #expect(throws: SceneConfigurationError.invalidDate) {
      try SceneConfiguration(scene: .today, now: Date(timeIntervalSince1970: .infinity))
    }
  }

  @Test func malformedLaunchArgumentsDoNotSilentlySelectDefaultScene() {
    #expect(throws: SceneConfigurationError.unknownScene("clock.typographicalError")) {
      try SceneRegistry.configuration(arguments: ["-scene", "clock.typographicalError"])
    }
    #expect(throws: SceneConfigurationError.unknownScenario("failed")) {
      try SceneRegistry.configuration(arguments: ["-scenario", "failed"])
    }
    #expect(throws: SceneConfigurationError.missingValue("-scene")) {
      try SceneRegistry.configuration(arguments: ["-scene", "-scenario", "empty"])
    }
    #expect(throws: SceneConfigurationError.unsupported(.clockWorld, .revoked)) {
      try SceneRegistry.configuration(arguments: ["-scene", "clock.world", "-scenario", "revoked"])
    }
  }
}
