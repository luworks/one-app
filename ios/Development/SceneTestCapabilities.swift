#if DEBUG
import Foundation
import Synchronization
import SwiftUI
import TodayCore
import TodayScenes
import TodayShared
import FeatureAsk
import One

/// Thread-safe deterministic clock/identity stream; no process clock or mutable static state.
final class SceneRuntimeState: Sendable {
    private struct Values { var now: Date; var index: UInt64 = 10_000 }
    private let values: Mutex<Values>
    private let configuration: SceneConfiguration

    init(configuration: SceneConfiguration) {
        self.configuration = configuration
        values = Mutex(Values(now: configuration.now))
    }
    func now() -> Date { values.withLock { $0.now } }
    func nextID() -> UUID {
        values.withLock { state in
            defer { state.index &+= 1 }
            return configuration.uuid(at: state.index)
        }
    }
    func advance(by seconds: TimeInterval) { values.withLock { $0.now.addTimeInterval(seconds) } }
    var runtime: PlannerRuntime {
        PlannerRuntime(now: { self.now() }, nextID: { self.nextID() },
                       calendar: configuration.calendar, locale: Locale(identifier: configuration.localeIdentifier))
    }
}

/// Every optional model route is explicitly scripted here, outside production features.
@MainActor
final class SceneAskCapabilities {
    let scenario: SceneScenario
    private(set) var prewarmCount = 0
    private(set) var calls: [String] = []
    private(set) var disposed = false
    init(scenario: SceneScenario) { self.scenario = scenario }

    var intelligence: AskIntelligence {
        AskIntelligence(
            backend: { .scripted },
            parse: { [self] text, _, now, calendar in
                calls.append("parse")
                return CaptureConversation.parse(text, now: now, calendar: calendar)
            },
            propose: { [self] text, now, calendar in
                calls.append("propose")
                guard !disposed, scenario != .unavailable, scenario != .error else { return nil }
                // A batch is explicit input; uncertain conversation never becomes a fixture capture.
                let parts = text.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count > 1, parts.allSatisfy({ !$0.isEmpty && ChatRouting.intent($0) == .capture }) else { return nil }
                return parts.map { CaptureConversation.parse($0, now: now, calendar: calendar) }
            },
            refineTitle: { [self] capture, _, _ in calls.append("refineTitle"); return capture },
            respond: { [self] _, _, _ in
                calls.append("respond")
                return .reply(scenario == .error ? "The scripted response could not be loaded. Please try again."
                              : "This is a local scripted conversation. Tell me what you would like to prepare; Add or Apply confirms any change.")
            },
            plan: { [self] text, items, now, calendar, _ in
                calls.append("plan")
                guard !disposed, scenario != .error else { throw SceneCapabilityError.scriptedFailure }
                let decision = Editing.decide(text: text, plan: nil, items: items, now: now, calendar: calendar)
                return EditPlan(op: EditOp(rawValue: decision.op.rawValue) ?? .clarify, target: decision.target)
            },
            rank: { [self] _, _, _, _ in calls.append("rank"); return nil },
            prewarm: { [self] in if !disposed { prewarmCount += 1 } },
            isAvailable: { [self] in !disposed && scenario != .unavailable && scenario != .denied && scenario != .revoked },
            unavailableReason: { [self] _ in
                disposed || scenario == .unavailable || scenario == .denied || scenario == .revoked
                    ? "Scripted intelligence is unavailable in this scene. Rule-based capture is still available." : nil
            })
    }
    func dispose() { disposed = true }
}

/// Local speech driver. Start/stop never resolve speech recognition, audio or a permission API.
@MainActor
final class SceneSpeechDriver: SpeechInputDriving {
    let scenario: SceneScenario
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var stateCallback: (@MainActor (VoiceInput.State) -> Void)?
    init(scenario: SceneScenario) { self.scenario = scenario }
    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onState: @escaping @MainActor (VoiceInput.State) -> Void) async {
        startCount += 1
        stateCallback = onState
        switch scenario {
        case .denied, .revoked: onState(.denied)
        case .unavailable, .error: onState(.unavailable)
        case .loading: onState(.listening)
        default:
            onState(.listening)
            onTranscript("Remind me to review the design tomorrow at 2 pm")
        }
    }
    func stop() { stopCount += 1; stateCallback?(.idle); stateCallback = nil }
}

@MainActor
struct SceneEmptyInbox: ShareInboxReading {
    func read() throws -> [SharedReminder] { [] }
    func acknowledge(_ ids: Set<UUID>) -> Bool { ids.isEmpty }
}

enum SceneCapabilityError: LocalizedError {
    case scriptedFailure
    var errorDescription: String? { "The local scripted operation failed. Try again in the Normal scenario." }
}
#endif
