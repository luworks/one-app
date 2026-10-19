import Foundation
import os

// How the Health sheet and the Today line talk to a `HealthSource` without ever hanging.
// HealthKit calls can stall: `requestAuthorization` waits for a system sheet that may not present (or never report back),
// and a query can simply never call its handler. A stuck call cannot be cancelled, so nothing here waits for one:
// every call is raced against a timer (`HealthTimeout.race`), each metric is fetched on its own, and a stalled call
// is abandoned (and, if it answers late, used for a refresh). Foundation only, so it runs under `swift test`.

private let healthLog = Logger(subsystem: "com.luworks.one", category: "health")

// MARK: - Source

/// Where the Health sheet and the Today line get their numbers. Read-only: Today never writes to Apple Health.
public protocol HealthSource: Sendable {
    /// False when this device has no Health data at all (iPad without Health, managed devices).
    var isAvailable: Bool { get }
    /// The page shows made-up numbers (UI tests and the simulator).
    var isSample: Bool { get }
    /// Shows Apple's permission sheet for these metrics' types, if any of them has not been asked about yet; a no-op
    /// for the rest. Health never says whether reading was denied: a denied type just returns no data, so the page
    /// treats "no data" and "not allowed" the same way. May take as long as the person takes to answer, or never return.
    func requestAccess(for metrics: [HealthMetric]) async
    /// The last `days` days of each metric. A metric with no data (or no permission) maps to an empty series.
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries]
    /// The units the user chose in Apple Health (lb or kg, mi or km); nil to follow the region (`HealthUnits()`).
    func preferredUnits() async -> HealthUnits?
}

extension HealthSource {
    public var isSample: Bool { false }
    public func preferredUnits() async -> HealthUnits? { nil }
}

// MARK: - Timeout

public enum HealthTimeout {
    /// How long any one Health call may take before the page moves on.
    public static let seconds: Double = 8

    public enum Outcome<T: Sendable>: Sendable {
        case value(T)
        case timedOut
    }

    /// Resumes a continuation at most once: the first of "the call answered" and "the timer fired" wins, the other is a no-op.
    // Every mutable field is accessed under lock; only the winning caller resumes the continuation.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome<T>, Never>?
        private var timer: Task<Void, Never>?

        init(_ continuation: CheckedContinuation<Outcome<T>, Never>) { self.continuation = continuation }

        func setTimer(_ task: Task<Void, Never>) {
            lock.lock()
            if continuation == nil { lock.unlock(); task.cancel(); return }
            timer = task
            lock.unlock()
        }

        /// True when this call was the one that resumed.
        @discardableResult
        func resume(_ outcome: Outcome<T>) -> Bool {
            lock.lock()
            guard let continuation else { lock.unlock(); return false }
            self.continuation = nil
            let timer = self.timer
            self.timer = nil
            lock.unlock()
            timer?.cancel()
            continuation.resume(returning: outcome)
            return true
        }
    }

    /// Runs `operation` and returns its value, or `.timedOut` after `seconds`, whichever comes first. The operation
    /// runs in its own unstructured task, so a call that never returns (and ignores cancellation) is just abandoned
    /// instead of holding this call open. `onLate` gets the value of an operation that answers after the timeout.
    public static func race<T: Sendable>(
        seconds: Double = HealthTimeout.seconds,
        _ operation: @escaping @Sendable () async -> T,
        onLate: (@Sendable (T) -> Void)? = nil
    ) async -> Outcome<T> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Outcome<T>, Never>) in
            let gate = Gate<T>(continuation)
            Task.detached {
                let value = await operation()
                if !gate.resume(.value(value)) { onLate?(value) }
            }
            gate.setTimer(Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(.timedOut)
            })
        }
    }
}

// MARK: - Per-metric state

/// Why a row has no number.
public enum HealthFailure: Equatable, Sendable {
    /// The query did not answer in time.
    case stalled
    /// Apple's permission sheet did not answer in time (or could not be shown).
    case accessUnanswered
}

public enum HealthMetricState: Equatable, Sendable {
    /// Waiting for the first answer for this metric (only this row shows a spinner).
    case loading
    /// Answered (an empty series is fine: "No data", which also covers "not allowed").
    case loaded
    case failed(HealthFailure)
}

public enum HealthFetchResult: Sendable, Equatable {
    case series(HealthSeries)
    case stalled
}

extension HealthMetricState {
    /// What a row shows once its fetch has settled. `hadData`: the row already has numbers (new or from before).
    /// - A stalled fetch keeps old numbers on screen and only fails a row that has none.
    /// - An empty answer is "No data" (Health never says "not allowed"), except when Apple's sheet never answered:
    ///   then it is "can't read this yet", so the person is pointed at the permission.
    public static func settled(_ result: HealthFetchResult, access: HealthAccessOutcome, hadData: Bool) -> HealthMetricState {
        switch result {
        case .stalled: return hadData ? .loaded : .failed(.stalled)
        case .series(let series):
            if !series.points.isEmpty || access == .answered { return .loaded }
            return .failed(.accessUnanswered)
        }
    }
}

// MARK: - Loading

public enum HealthLoader {
    /// The whole step: ask for access once for the new types (bounded), then read each metric on its own (bounded).
    /// The fetch does not depend on the answer: Health returns an empty series for a type nobody allowed yet, and
    /// `onLateAccess` runs if the permission sheet answers after the timeout, so the caller can read again.
    @discardableResult
    public static func load(
        _ metrics: [HealthMetric], source: HealthSource, gate: HealthAccessGate = .shared, days: Int, now: Date,
        timeout: Double = HealthTimeout.seconds,
        onLateAccess: @escaping @Sendable () -> Void = {},
        onResult: @escaping @Sendable (HealthMetric, HealthFetchResult, HealthAccessOutcome) async -> Void
    ) async -> HealthAccessOutcome {
        let access = await gate.request(metrics, source: source, timeout: timeout, onLate: onLateAccess)
        await fetch(metrics, source: source, days: days, now: now, timeout: timeout) { metric, result in
            await onResult(metric, result, access)
        }
        return access
    }

    /// Fetches every metric on its own with its own timeout, and reports each as soon as it settles, so one stalled
    /// metric never delays or blanks the others. Returns when all have settled (at most `timeout` later).
    public static func fetch(
        _ metrics: [HealthMetric], source: HealthSource, days: Int, now: Date,
        timeout: Double = HealthTimeout.seconds,
        onResult: @escaping @Sendable (HealthMetric, HealthFetchResult) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for metric in metrics {
                group.addTask {
                    let outcome = await HealthTimeout.race(seconds: timeout) {
                        await source.series(for: [metric], days: days, now: now)[metric] ?? .empty
                    }
                    switch outcome {
                    case .value(let series): await onResult(metric, .series(series))
                    case .timedOut:
                        healthLog.error("fetch stalled for \(metric.rawValue, privacy: .public) after \(timeout, privacy: .public) s")
                        await onResult(metric, .stalled)
                    }
                }
            }
        }
    }
}

public enum HealthAccessOutcome: Equatable, Sendable {
    /// Apple's sheet answered, or there was nothing new to ask.
    case answered
    /// No answer in time: the page moves on, and asks again when the app becomes active.
    case unanswered
}

/// Asks Apple Health for read access once per new batch of types, one request at a time, and never waits forever.
/// Shared by the sheet and the Today line, so the two never ask at once. HealthKit itself shows its sheet only for types
/// it has not asked about yet; this only stops Today from asking twice in a row for the same ones.
public actor HealthAccessGate {
    public static let shared = HealthAccessGate()

    private var asked: Set<HealthMetric> = []
    private var tail: Task<Void, Never>?
    private var tailFinished = true

    /// Requests access for the types in `metrics` that were not asked about yet, then returns (at most `timeout` later).
    /// A request that times out is forgotten (so a later call asks again) and `onLate` runs if it answers after all.
    public func request(
        _ metrics: [HealthMetric], source: HealthSource,
        timeout: Double = HealthTimeout.seconds,
        onLate: @escaping @Sendable () -> Void = {}
    ) async -> HealthAccessOutcome {
        let fresh = metrics.filter { !asked.contains($0) }
        if fresh.isEmpty {
            // Already asked: if that request is still waiting for the person, wait for it too (bounded).
            guard let pending = tail, !tailFinished else { return .answered }
            let outcome = await HealthTimeout.race(seconds: timeout) { await pending.value }
            if case .timedOut = outcome { return .unanswered }
            return .answered
        }
        asked.formUnion(fresh)
        let previous = tail
        tailFinished = false
        let task = Task { [weak self] in
            // One request at a time, but a stuck earlier one must not block this one for good.
            if let previous { _ = await HealthTimeout.race(seconds: timeout) { await previous.value } }
            await source.requestAccess(for: fresh)
            await self?.finished(fresh)
        }
        tail = task
        let names = fresh.map(\.rawValue).joined(separator: ",")
        healthLog.info("requesting Health access for \(names, privacy: .public)")
        let outcome = await HealthTimeout.race(seconds: timeout, { await task.value }, onLate: { _ in onLate() })
        switch outcome {
        case .value:
            return .answered
        case .timedOut:
            healthLog.error("Health access request for \(names, privacy: .public) did not answer in \(timeout, privacy: .public) s")
            asked.subtract(fresh)
            return .unanswered
        }
    }

    /// The request answered (maybe late): those types count as asked again.
    private func finished(_ types: [HealthMetric]) { tailFinished = true; asked.formUnion(types) }

    /// Forget what was asked (tests, and an explicit "Allow" tap).
    public func reset() { asked = []; tail = nil; tailFinished = true }

    public init() {}
}
