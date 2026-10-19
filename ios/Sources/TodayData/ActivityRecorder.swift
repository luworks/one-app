import Foundation
import TodayCore
import TodayShared

// The buffer in front of the Activity store. Pure Foundation: the clock-driven flush is injected, so tests run it by hand.
// The app side (store location, background task, Settings, outbox import) is `ActivityCenter.swift`.

/// Collects events in memory and writes them in one transaction every second or two, or when asked (app goes to the
/// background, the Activity screen opens, an export starts). Respects the user's settings: paused or switched-off categories
/// are dropped before they are buffered.
@MainActor
public final class ActivityRecorder {
    public typealias Scheduler = @MainActor (_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) -> Void

    /// One id per app launch.
    public let session: String
    private let store: ActivityStoring?
    private let settings: () -> ActivitySettings
    private let schedule: Scheduler
    private let lock = NSLock()
    private var buffer: [ActivityEvent] = []
    private var flushScheduled = false

    /// Seconds between a first buffered event and the write.
    public var flushDelay: TimeInterval = 1.5
    /// A buffer this long is written at once.
    public var maxBuffered = 200
    /// Called after a write with the number of new events (the app uses it to refresh counts).
    public var didFlush: ((Int) -> Void)?
    public private(set) var writeFailures = 0

    public init(store: ActivityStoring?, session: String = UUID().uuidString, settings: @escaping () -> ActivitySettings = { ActivitySettings() },
         schedule: @escaping Scheduler = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } }) {
        self.store = store
        self.session = session
        self.settings = settings
        self.schedule = schedule
    }

    public var isAvailable: Bool { store != nil }

    /// Whether an event of this tier would be kept right now.
    public func isRecording(_ tier: ActivityTier) -> Bool { store != nil && settings().records(tier) }

    /// Buffers the event unless its category is off. Returns whether it was kept.
    @discardableResult
    public func record(_ event: ActivityEvent) -> Bool {
        guard store != nil, settings().records(event.tierValue) else { return false }
        var e = event
        if e.session == nil { e.session = session }
        lock.lock()
        buffer.append(e)
        let full = buffer.count >= maxBuffered
        let needsSchedule = !flushScheduled && !full
        if needsSchedule { flushScheduled = true }
        lock.unlock()
        if full {
            flush()
        } else if needsSchedule {
            schedule(flushDelay) { [weak self] in self?.flush() }
        }
        return true
    }

    /// Writes what is buffered, now. Owned by the app lifecycle actor; nothing happens when the buffer is empty.
    public func flush() {
        lock.lock()
        let batch = buffer
        buffer = []
        flushScheduled = false
        lock.unlock()
        guard let store, !batch.isEmpty else { return }
        do {
            let inserted = try store.insert(batch)
            lock.lock(); writeFailures = 0; lock.unlock()
            didFlush?(inserted)
        } catch {
            // Keep the events for the next try instead of losing them; give up on a batch that keeps failing.
            lock.lock()
            writeFailures += 1
            if writeFailures < 5 { buffer.insert(contentsOf: batch, at: 0) }
            lock.unlock()
        }
    }

    /// Forgets what is waiting to be written (Clear must not let a buffered event come back after it).
    public func discardBuffered() {
        lock.lock()
        buffer = []
        lock.unlock()
    }

    public var bufferedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.count
    }
}
