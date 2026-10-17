import AppIntents
import SwiftUI

// Timers by voice. Every timer starts the same way (`TimerController.start(source: .voice)`): a real AlarmKit
// countdown that rings full-screen, shows as a Live Activity, and appears on the Today tab and the Timer tab.
// Asking Siri is the user's own decision, so these act directly (AI prepares, the user decides: here the user decided).
// Several timers may run at once. They run in the app's process; phrases in Chinese: AppShortcuts.xcstrings.
//
// What iOS allows: Today can only show timers it started. Siri's built-in "set a timer" goes to the Clock app, whose
// timers no other app can read (docs/research/timer-siri-sync.md). The schema intents at the bottom are the iOS 27
// way for Siri to hand "set a timer" to a third-party clock app.

/// "Start a timer in Today": asks "How long?" and reads the answer ("ten minutes", "an hour and a half", "十分钟").
struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a countdown timer. Say how long, like “10 minutes” or “an hour and a half”. It rings like an alarm, even on Silent, and shows on the Today tab.")
    static let openAppWhenRun = false

    @Parameter(title: "Length", requestValueDialog: "How long?")
    var length: String

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$length) timer") { \.$name }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let asked = TimerPhrase.seconds(from: length) else {
            throw $length.needsValueError("How long? For example, 10 minutes.")
        }
        guard let seconds = IntentTimer.seconds(seconds: asked) else {
            throw IntentMessage("Timers can run from 1 second to \(IntentTimer.maxMinutes) minutes.")
        }
        return .result(dialog: "\(try await TimerIntentSupport.start(seconds: seconds, name: name))")
    }
}

/// The lengths Siri can hear inside the phrase "Start a timer in Today for 10 minutes".
enum TimerLength: String, AppEnum {
    case m1, m2, m3, m5, m10, m15, m20, m25, m30, m45, m60, m90

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Length")
    static let caseDisplayRepresentations: [TimerLength: DisplayRepresentation] = [
        .m1: "1 minute", .m2: "2 minutes", .m3: "3 minutes", .m5: "5 minutes", .m10: "10 minutes", .m15: "15 minutes",
        .m20: "20 minutes", .m25: "25 minutes", .m30: "30 minutes", .m45: "45 minutes", .m60: "1 hour", .m90: "90 minutes",
    ]

    var seconds: Int {
        switch self {
        case .m1: 60
        case .m2: 120
        case .m3: 180
        case .m5: 300
        case .m10: 600
        case .m15: 900
        case .m20: 1200
        case .m25: 1500
        case .m30: 1800
        case .m45: 2700
        case .m60: 3600
        case .m90: 5400
        }
    }
}

struct StartTimerForIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer for…"
    static let description = IntentDescription("Starts a countdown timer for one of the usual lengths.")
    static let openAppWhenRun = false

    @Parameter(title: "Length", requestValueDialog: "How long?")
    var length: TimerLength

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$length) timer") { \.$name }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await TimerIntentSupport.start(seconds: length.seconds, name: name))")
    }
}

@MainActor
enum TimerIntentSupport {
    /// Tells Siri the user just did "start a timer" by hand, so it can suggest the phrase.
    static func donate(seconds: Int) {
        var intent = StartTimerIntent()
        intent.length = IntentTimer.spoken(seconds: seconds)
        Task { _ = try? await IntentDonationManager.shared.donate(intent: intent) }
    }

    /// Starts a voice timer and returns what Siri says. Throws what went wrong (alarms not allowed, ...).
    static func start(seconds: Int, name: String?) async throws -> String {
        let controller = TimerController.shared
        controller.refresh()
        guard let timer = await controller.start(seconds: seconds, label: name, source: .voice) else {
            throw IntentMessage(controller.message ?? "Couldn't start the timer.")
        }
        let label = TimerList.title(timer)
        return timer.label == nil ? "Timer started for \(IntentTimer.spoken(seconds: seconds))."
                                  : "\(label) started for \(IntentTimer.spoken(seconds: seconds))."
    }
}

// MARK: iOS 27 Clock schema: lets Siri hand "set a timer" to Today

/// A timer as Siri sees it ("pause the timer", "add 5 minutes to the timer").
@AppEntity(schema: .clock.timer)
struct TimerEntity {
    static let defaultQuery = TimerEntityQuery()

    let id: UUID
    var label: String?
    var duration: Duration
    var durationRemaining: Duration
    var isSleepTimer: Bool
    var state: TimerStateEnum

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label ?? "Timer")", subtitle: "\(TimerList.totalText(Int(duration.components.seconds)))")
    }

    @MainActor
    init(_ timer: RunningTimer, ringing: Bool) {
        id = timer.id
        label = IntentTimer.label(timer.label)
        duration = .seconds(timer.total)
        durationRemaining = .seconds(Int(timer.remaining(now: .now).rounded(.up)))
        isSleepTimer = false
        state = ringing ? .firing : (timer.isPaused ? .paused : .running)
    }
}

@AppEnum(schema: .clock.timerState)
enum TimerStateEnum: String {
    case running, paused, firing, undefined

    static let caseDisplayRepresentations: [TimerStateEnum: DisplayRepresentation] = [
        .running: "Running", .paused: "Paused", .firing: "Ringing", .undefined: "Unknown",
    ]
}

struct TimerEntityQuery: EntityStringQuery {
    @MainActor
    func entities(matching string: String) async throws -> [TimerEntity] {
        let controller = TimerController.shared
        controller.refresh()
        let needle = string.lowercased()
        return controller.timers.filter { TimerList.title($0).lowercased().contains(needle) }
            .map { TimerEntity($0, ringing: controller.ringing.contains($0.id)) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TimerEntity] {
        let controller = TimerController.shared
        controller.refresh()
        return controller.timers.filter { identifiers.contains($0.id) }.map { TimerEntity($0, ringing: controller.ringing.contains($0.id)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TimerEntity] {
        let controller = TimerController.shared
        controller.refresh()
        return controller.timers.map { TimerEntity($0, ringing: controller.ringing.contains($0.id)) }
    }
}

@AppIntent(schema: .clock.createTimer)
struct CreateTimerIntent {
    var duration: Duration
    var label: String?
    var isSleepTimer: Bool

    @MainActor
    func perform() async throws -> some ReturnsValue<TimerEntity> {
        guard let seconds = IntentTimer.seconds(seconds: Int(duration.components.seconds)) else {
            throw IntentMessage("Timers can run from 1 second to \(IntentTimer.maxMinutes) minutes.")
        }
        let controller = TimerController.shared
        controller.refresh()
        guard let timer = await controller.start(seconds: seconds, label: label, source: .voice) else {
            throw IntentMessage(controller.message ?? "Couldn't start the timer.")
        }
        return .result(value: TimerEntity(timer, ringing: false))
    }
}

@AppIntent(schema: .clock.pauseTimer)
struct PauseTimerIntent {
    var timer: TimerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerController.shared.pause(timer.id)
        return .result()
    }
}

@AppIntent(schema: .clock.resumeTimer)
struct ResumeTimerIntent {
    var timer: TimerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerController.shared.resume(timer.id)
        return .result()
    }
}

@AppIntent(schema: .clock.cancelTimer)
struct CancelTimerIntent {
    var entities: [TimerEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        for id in entities.map(\.id) { TimerController.shared.cancel(id) }
        return .result()
    }
}
