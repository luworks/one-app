#if os(iOS)
  import TodayCore
  import TodayData
  import AppIntents
  import SwiftData

  // Alarms by voice, Spotlight and Shortcuts. Asking is the user's own decision, so these set the alarm directly
  // (AI prepares, the user decides: here the user decided). Every alarm is a real AlarmKit alarm, made like one from
  // Add Alarm or the chat: same parser (`IntentAlarm`), same defaults (`OneAlarm.new`, Settings → Alarms).
  // They run in the app's process on the app's store; phrases in Chinese: AppShortcuts.xcstrings.
  //
  // What iOS allows: Today can't read or change the Clock app's alarms. The schema intents at the bottom are the iOS 27
  // way for Siri to hand "set an alarm" to a third-party clock app; whether Siri picks Today needs a real phone.

  /// "Set an alarm in Today": asks "What time?" and reads the answer like the chat ("7am tomorrow", "weekdays at 6:30",
  /// "in 20 minutes", "明早7点").
  public struct SetAlarmIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "Set Alarm"
    public static let description = IntentDescription(
      "Sets an alarm in Today. Say the time like “7am tomorrow”, “weekdays at 6:30” or “in 20 minutes”. It rings even on Silent."
    )
    public static let openAppWhenRun = false

    @Parameter(title: "Time", requestValueDialog: "What time?")
    public var time: String

    @Parameter(title: "Label")
    public var label: String?

    public static var parameterSummary: some ParameterSummary {
      Summary("Set an alarm for \(\.$time)") { \.$label }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
      let session = OneStore.session
      guard
        let capture = IntentAlarm.capture(
          text: time, label: label, now: session.runtime.now(), calendar: session.runtime.calendar)
      else {
        throw $time.needsValueError("What time? For example, 7am tomorrow.")
      }
      guard
        let alarm = capture.makeAlarm(
          now: session.runtime.now(), calendar: session.runtime.calendar,
          defaults: AlarmPlan.newAlarmDefaults(session.defaults))
      else {
        throw IntentMessage(
          "An alarm rings within the next day or repeats. For a later date, add a reminder.")
      }
      try await AlarmIntentSupport.create(alarm, name: "set_alarm")
      return .result(dialog: "\(AlarmIntentSupport.confirmation(alarm))")
    }
  }

  @MainActor
  enum AlarmIntentSupport {
    /// Schedules a new alarm in AlarmKit and saves it, then records it in Activity as made by Siri.
    static func create(_ alarm: OneAlarm, name: String) async throws {
      let session = OneStore.session
      let context = OneStore.start().mainContext
      do {
        try await session.alarms.commit(alarm, context: context)
      } catch {
        session.activity.record(ActivityEvents.intentRun(name: name, outcome: "failed"))
        throw IntentMessage(
          "Couldn’t set the alarm. Check that Today may set alarms in Settings, then try again.")
      }
      AlarmActions.recordCreated(
        alarm, title: title(alarm), after: confirmation(alarm), ledger: session.ledger,
        runtime: session.runtime, context: context, actor: .siri, channel: .intent)
      session.activity.record(ActivityEvents.intentRun(name: name, outcome: "ok"))
      IntentSupport.refreshWidgets(context)
    }

    static func confirmation(_ alarm: OneAlarm) -> String {
      IntentAlarm.confirmation(
        label: alarm.label, hour: alarm.hour, minute: alarm.minute, weekdays: alarm.weekdays,
        now: OneStore.session.runtime.now(), calendar: OneStore.session.runtime.calendar,
        locale: OneStore.session.runtime.locale)
    }

    static func title(_ alarm: OneAlarm) -> String {
      alarm.label.isEmpty ? AlarmPlan.defaultLabel : alarm.label
    }

    /// Today's alarms Siri can name: the ones AlarmKit knows (every alarm gets its id when first scheduled).
    static func alarms() -> [OneAlarm] {
      let context = OneStore.start().mainContext
      return ((try? context.fetch(FetchDescriptor<OneAlarm>())) ?? []).filter {
        $0.alarmKitID != nil
      }
    }

    static func alarm(_ id: UUID) -> OneAlarm? { alarms().first { $0.alarmKitID == id } }
  }

  // MARK: iOS 27 Clock schema: lets Siri hand "set an alarm" to Today

  /// An alarm as Siri sees it ("turn off my 7am alarm", "stop the alarm"). Its id is the AlarmKit id, which the
  /// scheduled alarm also carries (`appEntityIdentifier`), so Siri can tell which ringing alarm is which.
  @AppEntity(schema: .clock.alarm)
  struct AlarmEntity {
    static let defaultQuery = AlarmEntityQuery()

    let id: UUID
    var time: DateComponents
    var isEnabled: Bool
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var canSnooze: Bool
    var triggerState: AlarmTriggerStateEnum

    var displayRepresentation: DisplayRepresentation {
      let parts = AlarmPlan.timeParts(hour: time.hour ?? 0, minute: time.minute ?? 0)
      return DisplayRepresentation(
        title: "\([parts.time, parts.suffix].compactMap { $0 }.joined(separator: " "))",
        subtitle: "\(label ?? AlarmPlan.defaultLabel)")
    }

    @MainActor
    init?(_ alarm: OneAlarm) {
      guard let id = alarm.alarmKitID else { return nil }
      self.id = id
      time = DateComponents(hour: alarm.hour, minute: alarm.minute)
      isEnabled = alarm.isOn
      label = alarm.label.isEmpty ? nil : alarm.label
      recurrenceDays = AlarmPlan.recurrenceRule(
        weekdays: alarm.weekdays, calendar: OneStore.session.runtime.calendar)
      canSnooze = alarm.snooze
      triggerState =
        switch OneStore.session.alarms.state(of: alarm) {
        case .ringing: .firing
        case .snoozing: .snoozed
        default: .none
        }
    }
  }

  @AppEnum(schema: .clock.alarmTriggerState)
  enum AlarmTriggerStateEnum: String {
    case firing, snoozed, none

    static let caseDisplayRepresentations: [AlarmTriggerStateEnum: DisplayRepresentation] = [
      .firing: "Ringing", .snoozed: "Snoozed", .none: "None",
    ]
  }

  struct AlarmEntityQuery: EntityStringQuery {
    @MainActor
    func entities(matching string: String) async throws -> [AlarmEntity] {
      let needle = string.lowercased()
      return AlarmIntentSupport.alarms()
        .filter { AlarmIntentSupport.title($0).lowercased().contains(needle) }
        .compactMap { AlarmEntity($0) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AlarmEntity] {
      AlarmIntentSupport.alarms()
        .filter { $0.alarmKitID.map(identifiers.contains) ?? false }
        .compactMap { AlarmEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AlarmEntity] {
      AlarmIntentSupport.alarms().compactMap { AlarmEntity($0) }
    }
  }

  @AppIntent(schema: .clock.createAlarm)
  struct CreateAlarmIntent {
    var time: DateComponents
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var canSnooze: Bool

    @MainActor
    func perform() async throws -> some ReturnsValue<AlarmEntity> {
      guard let hour = time.hour, (0...23).contains(hour) else {
        throw IntentMessage("What time? For example, 7am.")
      }
      let session = OneStore.session
      let alarm = OneAlarm.new(
        hour: hour, minute: time.minute ?? 0,
        label: label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        weekdays: AlarmPlan.weekdays(from: recurrenceDays),
        defaults: AlarmPlan.newAlarmDefaults(session.defaults), now: session.runtime.now())
      alarm.snooze = canSnooze
      try await AlarmIntentSupport.create(alarm, name: "create_alarm")
      guard let entity = AlarmEntity(alarm) else { throw IntentMessage("Couldn’t set the alarm.") }
      return .result(value: entity)
    }
  }

  /// "Turn off my 7am alarm", "change it to 6:30", "make it weekdays".
  @AppIntent(schema: .clock.updateAlarm)
  struct UpdateAlarmIntent {
    var alarm: AlarmEntity
    var isEnabled: Bool?
    var time: DateComponents?
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var allowsSnooze: Bool?

    @MainActor
    func perform() async throws -> some ReturnsValue<AlarmEntity> {
      let session = OneStore.session
      guard let target = AlarmIntentSupport.alarm(alarm.id) else {
        throw IntentMessage("That alarm is no longer in Today.")
      }
      let before = target.activitySnapshot
      if let hour = time?.hour, (0...23).contains(hour) {
        target.hour = hour
        target.minute = time?.minute ?? 0
      }
      if let label { target.label = label.trimmingCharacters(in: .whitespacesAndNewlines) }
      if let recurrenceDays { target.weekdays = AlarmPlan.weekdays(from: recurrenceDays) }
      if let allowsSnooze { target.snooze = allowsSnooze }
      if let isEnabled { target.isOn = isEnabled }
      // Like a save in Edit Alarm: a one-time alarm counts from now, and AlarmKit gets exactly this alarm again.
      target.createdAt = session.runtime.now()
      target.alarmKitSignature = nil
      let context = OneStore.start().mainContext
      do {
        try await session.alarms.commit(target, context: context)
      } catch {
        throw IntentMessage("Couldn’t change the alarm. Try again in Today.")
      }
      session.ledger.record(
        .moved, item: target, kind: "alarm", title: AlarmIntentSupport.title(target),
        after: AlarmIntentSupport.confirmation(target), actor: .siri, channel: .intent,
        snapshot: AlarmChange(before: before, after: target.activitySnapshot), context: context)
      session.activity.record(ActivityEvents.intentRun(name: "update_alarm", outcome: "ok"))
      IntentSupport.refreshWidgets(context)
      guard let entity = AlarmEntity(target) else {
        throw IntentMessage("Couldn’t change the alarm.")
      }
      return .result(value: entity)
    }
  }

  /// "Stop the alarm": stops it ringing (or snoozing). Never completes a task.
  @AppIntent(schema: .clock.dismissAlarm)
  struct DismissAlarmIntent {
    var alarm: AlarmEntity

    @MainActor
    func perform() async throws -> some ReturnsValue<AlarmEntity> {
      OneStore.session.alarms.stop(alarm.id)
      OneStore.session.activity.record(
        ActivityEvents.intentRun(name: "dismiss_alarm", outcome: "ok"))
      let updated = AlarmIntentSupport.alarm(alarm.id).flatMap { AlarmEntity($0) } ?? alarm
      return .result(value: updated)
    }
  }
#endif
