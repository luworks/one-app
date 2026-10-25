#if os(iOS)
  import TodayCore
  import TodayData
  import AppIntents

  /// One step of the one-time "Import Clock alarms" Shortcut the user builds: Clock's "Get All Alarms", then this for
  /// each alarm. No app can read the Clock app's alarms, so the user's Shortcut hands them over. This only stages the
  /// alarm: the Clock tab shows it as a card to Add (or Skip), so nothing is set without the user's tap.
  public struct ImportAlarmIntent: AppIntent {
    public init() {}
    public static let title: LocalizedStringResource = "Import Alarm"
    public static let description = IntentDescription(
      "Brings one alarm from the Clock app into Today, to add from the Clock tab. Use it after “Get All Alarms”, once."
    )
    public static let openAppWhenRun = false

    @Parameter(title: "Time")
    public var time: Date

    @Parameter(title: "Label")
    public var label: String?

    @Parameter(title: "Repeat")
    public var repeats: String?

    @Parameter(title: "Is On", default: true)
    public var isOn: Bool

    public static var parameterSummary: some ParameterSummary {
      Summary("Import the alarm at \(\.$time)") {
        \.$label
        \.$repeats
        \.$isOn
      }
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
      let session = OneStore.session
      let c = session.runtime.calendar.dateComponents([.hour, .minute], from: time)
      let name = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      AlarmImport.stage(
        AlarmImport.Staged(
          hour: c.hour ?? 0, minute: c.minute ?? 0,
          label: name == AlarmPlan.defaultLabel ? "" : name,
          weekdays: AlarmImport.weekdays(fromRepeat: repeats), isOn: isOn),
        session.defaults)
      session.activity.record(ActivityEvents.intentRun(name: "import_alarm", outcome: "ok"))
      return .result()
    }
  }
#endif
