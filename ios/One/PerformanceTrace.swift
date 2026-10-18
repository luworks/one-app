import SwiftUI
import UIKit
import os.signpost

/// Opt-in benchmark probes. Times are app-side layout proxies, never touch-to-photon measurements.
@MainActor @Observable
final class PerformanceTrace {
    static let shared = PerformanceTrace()
    static let enabled = ProcessInfo.processInfo.arguments.contains("-performanceTrace")
    private static var pageContext: String {
        ProcessInfo.processInfo.arguments.contains("-performancePageRevisits")
            ? "first_cycle_plus_two_revisits" : "unclassified"
    }
    private let log = OSLog(subsystem: "com.luworks.one", category: "PerformanceTrace")
    private struct Pending {
        let name: String
        let destination: String?
        let start: UInt64
    }
    private var pending: Pending?
    private var phaseMarks: [String: UInt64] = [:]
    private var sequence = 0
    private var pageVisits: [String: Int] = [:]
    private(set) var bootstrapComplete = false
    private(set) var launchComplete = false
    private(set) var generation = 0
    private(set) var report = ""

    func mark(_ event: String) {
        guard Self.enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if ["store_start", "store_ready", "bootstrap_start", "bootstrap_complete"].contains(event) {
            phaseMarks[event] = now
        }
        os_signpost(.event, log: log, name: "PerformanceEndpoint", "%{public}@ uptime_ns=%llu", event as NSString, now)
        print("PERF_TRACE v=1 event=\(event) uptime_ns=\(now)")
    }

    func beginLaunch() {
        guard Self.enabled else { return }
        begin("app_init_to_content_layout", destination: nil)
    }

    func finishBootstrap() {
        guard Self.enabled else { return }
        mark("bootstrap_complete")
        bootstrapComplete = true
    }

    func begin(_ name: String, destination: String?) {
        guard Self.enabled else { return }
        // A superseded operation is not silently turned into a successful sample.
        if let pending { mark("cancel.\(pending.name)") }
        pending = Pending(name: name, destination: destination, start: DispatchTime.now().uptimeNanoseconds)
        generation += 1
        mark("begin.\(name)")
    }

    func wantsLayout(_ route: String) -> Bool {
        guard Self.enabled, bootstrapComplete, let pending else { return false }
        return pending.destination == nil || pending.destination == route
    }

    func finishLayout(_ route: String, generation expected: Int) {
        guard expected == generation, wantsLayout(route), let pending else { return }
        let end = DispatchTime.now().uptimeNanoseconds
        self.pending = nil
        if pending.name == "app_init_to_content_layout" { launchComplete = true }
        sequence += 1
        let ms = Double(end - pending.start) / 1_000_000
        report = "v=1;seq=\(sequence);name=\(pending.name);route=\(route);start_ns=\(pending.start);end_ns=\(end);ms=\(ms)"
        if pending.name.hasPrefix("page.") {
            let visit = (pageVisits[route] ?? 0) + 1
            pageVisits[route] = visit
            report += ";page_context=\(Self.pageContext);route_visit=\(visit)"
        }
        if pending.name == "app_init_to_content_layout",
           let storeStart = phaseMarks["store_start"], let storeReady = phaseMarks["store_ready"],
           let bootstrapStart = phaseMarks["bootstrap_start"], let bootstrapEnd = phaseMarks["bootstrap_complete"] {
            report += ";init_to_store_ms=\(Double(storeStart - pending.start) / 1_000_000)"
            report += ";store_ms=\(Double(storeReady - storeStart) / 1_000_000)"
            report += ";bootstrap_ms=\(Double(bootstrapEnd - bootstrapStart) / 1_000_000)"
            report += ";post_bootstrap_layout_ms=\(Double(end - bootstrapEnd) / 1_000_000)"
        }
        os_signpost(.event, log: log, name: "PerformanceSample", "%{public}@", report as NSString)
        print("PERF_SAMPLE_APP \(report)")
    }
}

/// Attached to the real content's background, after its bootstrap state has been published.
/// Two display-link callbacks leave a display opportunity between layout and the endpoint;
/// neither callback proves compositor presentation, animation completion or asynchronous sync.
struct PerformanceContentProbe: UIViewRepresentable {
    let route: String
    let generation: Int
    let bootstrapComplete: Bool

    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.arm(route: route, generation: generation, ready: bootstrapComplete)
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: UIView {
        private var link: CADisplayLink?
        private var route = ""
        private var generation = -1
        private var ticks = 0

        func arm(route: String, generation: Int, ready: Bool) {
            guard ready, PerformanceTrace.shared.wantsLayout(route) else { stop(); return }
            guard self.route != route || self.generation != generation || link == nil else { return }
            stop()
            self.route = route
            self.generation = generation
            ticks = 0
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            let link = CADisplayLink(target: self, selector: #selector(tick))
            self.link = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func tick() {
            guard window != nil, bounds.width > 0, bounds.height > 0,
                  window?.windowScene?.activationState == .foregroundActive else { return }
            // Observe normal layout; never force the app to perform layout early for the benchmark.
            guard !isHidden else { return }
            ticks += 1
            if ticks >= 2 {
                PerformanceTrace.shared.finishLayout(route, generation: generation)
                stop()
            }
        }

        func stop() { link?.invalidate(); link = nil }
    }
}

/// Page timers start in the action (or a control's binding setter), before navigation mutates state.
/// The endpoint describes content geometry, not async data readiness or animation completion.
extension PerformanceTrace {
    func beginPage(_ route: String) {
        begin("page.\(route)", destination: route)
    }
}

extension Binding where Value: Equatable {
    @MainActor
    func performanceAction(_ route: @escaping (Value) -> String?) -> Binding<Value> {
        guard PerformanceTrace.enabled else { return self }
        return Binding(get: { wrappedValue }, set: { value in
            if value != wrappedValue, let destination = route(value) {
                PerformanceTrace.shared.beginPage(destination)
            }
            wrappedValue = value
        })
    }
}

private struct PerformanceDestination: ViewModifier {
    let route: String
    func body(content: Content) -> some View {
        content.background {
            if PerformanceTrace.enabled {
                PerformanceContentProbe(route: route, generation: PerformanceTrace.shared.generation,
                                        bootstrapComplete: PerformanceTrace.shared.bootstrapComplete)
            }
        }
        .overlay(alignment: .topLeading) {
            if PerformanceTrace.enabled {
                Text(PerformanceTrace.shared.report).font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("performance.trace")
                    .accessibilityLabel(PerformanceTrace.shared.report)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Apply to the destination's List/Form/content, never the obscured presenting root.
    func performanceDestination(_ route: String) -> some View {
        modifier(PerformanceDestination(route: route))
    }
}


extension View {
    /// Keep NavigationLink's production structure and state ownership unchanged.
    /// Opt-in runs begin on the real navigation tap, never destination onAppear.
    @ViewBuilder
    func performanceNavigationAction(_ route: String) -> some View {
        if PerformanceTrace.enabled {
            simultaneousGesture(TapGesture().onEnded { PerformanceTrace.shared.beginPage(route) })
        } else {
            self
        }
    }
}
