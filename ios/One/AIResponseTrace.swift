import SwiftUI
import UIKit

/// Opt-in app-side monotonic timings. Layout/display-link opportunities do not prove presentation.
@MainActor @Observable
final class AIResponseTrace {
    static let shared = AIResponseTrace()
    static let enabled = ProcessInfo.processInfo.arguments.contains("-performanceTrace")
    static let showsHistory = enabled && ProcessInfo.processInfo.arguments.contains("-uiTesting")

    enum Phase: String, Hashable { case feedback, response }
    private struct Turn {
        let token: UUID
        let start: UInt64
        let modelAvailable: Bool
        var backend = "rules"
        var ready: UInt64?
        var pending: Set<Phase> = [.feedback, .response]
    }
    private var turn: Turn?
    private var sequence = 0
    // Diagnostic bookkeeping must not publish state changes or add accessibility samples.
    @ObservationIgnored private var stageTimes: [String: UInt64] = [:]
    @ObservationIgnored private var stageToken: UUID?
    @ObservationIgnored private var conversationStageToken: UUID?
    private(set) var history: [String] = []

    func begin(_ token: UUID, modelAvailable: Bool) {
        guard Self.enabled else { return }
        cancel()
        turn = Turn(token: token, start: DispatchTime.now().uptimeNanoseconds, modelAvailable: modelAvailable)
        stageToken = token
        stageTimes = ["send": turn?.start ?? 0]
    }

    /// Only the conversation wrapper is diagnosed; model internals and save outcomes remain unobserved.
    func diagnoseConversation(_ token: UUID) {
        guard Self.enabled, stageToken == token else { return }
        conversationStageToken = token
    }

    func stage(_ name: String, token: UUID, at timestamp: UInt64? = nil) {
        guard Self.enabled, stageToken == token,
              name == "context_complete" || conversationStageToken == token else { return }
        let now = timestamp ?? DispatchTime.now().uptimeNanoseconds
        // Keep the first entry and latest entry when deferred emission is visited before and after await.
        if stageTimes[name] == nil { stageTimes[name] = now }
        stageTimes[name + "_last"] = now
    }

    private func emitConversationStages(_ current: Turn) {
        guard conversationStageToken == current.token, current.pending.isEmpty else { return }
        let fields = stageTimes.keys.sorted().map { "\($0)_ns=\(stageTimes[$0]!)" }.joined(separator: ";")
        print("PERF_STAGE_AI v=1;turn=\(current.token.uuidString);backend=\(current.backend);\(fields)")
        stageTimes.removeAll(keepingCapacity: true)
        stageToken = nil
        conversationStageToken = nil
    }

    func backend(_ backend: String, token: UUID) {
        guard turn?.token == token else { return }
        turn?.backend = backend
    }

    /// Called only after this turn has emitted its own reply, card or follow-up state.
    func ready(_ token: UUID) {
        guard var current = turn, current.token == token, current.ready == nil else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        current.ready = now
        turn = current
        stage("ready", token: token, at: now)
        // Existing APIs emit one complete result, with no streaming token callback. These share an endpoint.
        emit("ai_send_to_first_response_ready", start: current.start, end: now, turn: current)
        emit("ai_send_to_full_response_ready", start: current.start, end: now, turn: current)
    }

    func wants(_ phase: Phase, token: UUID) -> Bool {
        guard let turn, turn.token == token, turn.pending.contains(phase) else { return false }
        return phase == .feedback || turn.ready != nil
    }

    func layout(_ phase: Phase, token: UUID) {
        guard wants(phase, token: token), var current = turn else { return }
        let end = DispatchTime.now().uptimeNanoseconds
        current.pending.remove(phase)
        turn = current
        stage(phase.rawValue + "_layout", token: token, at: end)
        switch phase {
        case .feedback:
            emit("ai_send_to_feedback_layout", start: current.start, end: end, turn: current)
        case .response:
            guard let ready = current.ready else { return }
            emit("ai_ready_to_response_layout", start: ready, end: end, turn: current)
            emit("ai_turn_to_response_layout", start: current.start, end: end, turn: current)
        }
        emitConversationStages(current)
    }

    func cancel(_ token: UUID? = nil) {
        guard let current = turn, token == nil || token == current.token else { return }
        if !current.pending.isEmpty {
            print("PERF_TRACE v=1 event=ai_cancel turn=\(current.token.uuidString) uptime_ns=\(DispatchTime.now().uptimeNanoseconds)")
        }
        turn = nil
        stageTimes.removeAll(keepingCapacity: true)
        stageToken = nil
        conversationStageToken = nil
    }

    private func emit(_ name: String, start: UInt64, end: UInt64, turn: Turn) {
        sequence += 1
        let endpoint = name.hasSuffix("_ready") ? "response_state_observation" : "layout_displaylink_proxy"
        let sample = "v=1;name=\(name);seq=\(sequence);turn=\(turn.token.uuidString);start_ns=\(start);end_ns=\(end);ms=\(Double(end - start) / 1_000_000);backend=\(turn.backend);model_available=\(turn.modelAvailable ? 1 : 0);streaming=0;first_full_same_emission=1;endpoint=\(endpoint)"
        print("PERF_SAMPLE_APP \(sample)")
        // Bounded raw history lets XCTest collect every stage instead of racing a single latest value.
        history.append(sample)
        if history.count > 128 { history.removeFirst(history.count - 128) }
    }
}

/// Background of the actual sent message or emitted reply/card, never an artificial layout request.
struct AIResponseContentProbe: UIViewRepresentable {
    let token: UUID
    let phase: AIResponseTrace.Phase

    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) { view.arm(token: token, phase: phase) }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: UIView {
        private var link: CADisplayLink?
        private var token: UUID?
        private var phase: AIResponseTrace.Phase = .feedback
        private var ticks = 0

        func arm(token: UUID, phase: AIResponseTrace.Phase) {
            guard AIResponseTrace.shared.wants(phase, token: token) else { stop(); return }
            guard self.token != token || self.phase != phase || link == nil else { return }
            stop()
            self.token = token
            self.phase = phase
            ticks = 0
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            let link = CADisplayLink(target: self, selector: #selector(tick))
            self.link = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func tick() {
            guard let token, AIResponseTrace.shared.wants(phase, token: token) else { stop(); return }
            guard let window, window.windowScene?.activationState == .foregroundActive,
                  !isHidden, bounds.width > 0, bounds.height > 0,
                  convert(bounds, to: window).intersects(window.bounds) else { return }
            ticks += 1
            if ticks >= 2 {
                AIResponseTrace.shared.layout(phase, token: token)
                stop()
            }
        }

        func stop() { link?.invalidate(); link = nil }
    }
}

/// Diagnostic-only accessibility data lives on Ask, including when Ask is itself a full-screen sheet.
struct AIResponseTraceHistory: View {
    var body: some View {
        if AIResponseTrace.showsHistory {
            Text("AI trace")
                .font(.system(size: 1))
                .frame(width: 2, height: 2)
                .accessibilityLabel(AIResponseTrace.shared.history.joined(separator: "\n"))
                .accessibilityIdentifier("performance.ai.history")
                .allowsHitTesting(false)
        }
    }
}
