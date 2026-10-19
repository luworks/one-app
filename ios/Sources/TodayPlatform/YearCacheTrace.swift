#if os(iOS)
#if DEBUG
import Foundation

/// Process-lifetime diagnostics only; never retains marks, model objects, signatures or titles.
/// Header lifecycle callbacks mean appeared/disappeared, not viewport visibility.
public enum YearCacheTrace {
    public static let enabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return ["-performanceYearCacheCounts", "-uiTesting", "-performanceTrace", "-performanceResources"]
            .allSatisfy(arguments.contains)
    }()
    // Gate before allocating any mutable store, including its lock and event buffer.
    private static let store: Store? = enabled ? Store() : nil

    public enum Kind: String, Codable, Sendable {
        case miss, invalidated, appeared, disappeared
    }

    public struct Event: Codable, Sendable {
        let sequence: UInt64
        let kind: Kind
        let ns: UInt64
        let year: Int?
        let start_ns: UInt64?
        let end_ns: UInt64?
        let cache_year_count: Int?
        let invalidation_sequence: UInt64
    }

    /// Counters are as of snapshot_ns, which may be later than the original layout_ns.
    /// Endpoint claims MUST filter events by ns <= layout_ns (miss ns is end_ns).
    /// Aggregate counters cannot be backdated; truncated events cannot prove absence.
    public struct Snapshot: Codable, Sendable {
        let snapshot_ns: UInt64
        let request_count: UInt64
        let hit_count: UInt64
        let miss_count: UInt64
        let invalidation_sequence: UInt64
        let event_limit: Int
        let truncated_count: UInt64
        let events: [Event]
    }

    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        let eventLimit = 256
        var requests: UInt64 = 0
        var hits: UInt64 = 0
        var misses: UInt64 = 0
        var invalidations: UInt64 = 0
        var sequence: UInt64 = 0
        var truncated: UInt64 = 0
        var events: [Event] = []

        // Caller holds lock. Retain the first bounded events and count every dropped event.
        func append(_ kind: Kind, year: Int? = nil, start: UInt64? = nil, cacheCount: Int? = nil) {
            sequence += 1
            let now = DispatchTime.now().uptimeNanoseconds
            guard events.count < eventLimit else { truncated += 1; return }
            events.append(Event(sequence: sequence, kind: kind, ns: now, year: year,
                                start_ns: start, end_ns: kind == .miss ? now : nil,
                                cache_year_count: cacheCount, invalidation_sequence: invalidations))
        }
    }

    public static func request() {
        guard let store else { return }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.requests += 1
    }

    public static func hit() {
        guard let store else { return }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.hits += 1
    }

    public static func miss(year: Int, start: UInt64, cacheCount: Int) {
        guard let store else { return }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.misses += 1
        store.append(.miss, year: year, start: start, cacheCount: cacheCount)
    }

    public static func invalidated(cacheCount: Int) {
        guard let store else { return }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.invalidations += 1
        store.append(.invalidated, cacheCount: cacheCount)
    }

    public static func header(year: Int, appeared: Bool) {
        guard let store else { return }
        store.lock.lock()
        defer { store.lock.unlock() }
        store.append(appeared ? .appeared : .disappeared, year: year)
    }

    public static func snapshot() -> Snapshot? {
        guard let store else { return nil }
        store.lock.lock()
        defer { store.lock.unlock() }
        return Snapshot(snapshot_ns: DispatchTime.now().uptimeNanoseconds,
                        request_count: store.requests, hit_count: store.hits, miss_count: store.misses,
                        invalidation_sequence: store.invalidations, event_limit: store.eventLimit,
                        truncated_count: store.truncated, events: store.events)
    }
}
#endif
#endif
