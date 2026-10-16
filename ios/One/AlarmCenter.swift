import Foundation
import SwiftData
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// What AlarmKit says an alarm is doing right now.
enum AlarmLiveState: Equatable {
    /// Waiting for its time.
    case scheduled
    /// Rang and the user tapped Snooze; it rings again when the countdown ends.
    case snoozing
    case paused
    /// Ringing right now.
    case ringing
}

/// Live view of the alarms this app has scheduled in AlarmKit, for the Alarms tab: which one is ringing,
/// which one is snoozing, and whether the user allowed alarms.
///
/// This is AlarmKit's real state, but only for alarms Today scheduled. AlarmKit gives no access to alarms
/// made in Apple's Clock app.
@MainActor
@Observable
final class AlarmCenter {
    static let shared = AlarmCenter()

    private(set) var authorization: AlarmAuthorization = Ringer.authorization
    /// Keyed by `OneAlarm.alarmKitID` (and the ids of items that ring as alarms).
    private(set) var states: [UUID: AlarmLiveState] = [:]

    func state(of alarm: OneAlarm) -> AlarmLiveState? {
        alarm.alarmKitID.flatMap { states[$0] }
    }

    func requestAuthorization() async {
        await Ringer.requestAuthorization()
        authorization = Ringer.authorization
    }

    /// Follows AlarmKit until the calling task is cancelled (attach it to the view with `.task`).
    /// Every update also runs a sync, so a one-time alarm that rang is switched off in the list.
    func watch(context: ModelContext) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        authorization = Ringer.authorization
        refreshStates()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await _ in AlarmManager.shared.alarmUpdates {
                    self.refreshStates()
                    await Ringer.sync(context)
                }
            }
            group.addTask { @MainActor in
                for await _ in AlarmManager.shared.authorizationUpdates {
                    self.authorization = Ringer.authorization
                    await Ringer.sync(context)
                }
            }
        }
        #endif
    }

    private func refreshStates() {
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        var next: [UUID: AlarmLiveState] = [:]
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            switch alarm.state {
            case .scheduled: next[alarm.id] = .scheduled
            case .countdown: next[alarm.id] = .snoozing
            case .paused: next[alarm.id] = .paused
            case .alerting: next[alarm.id] = .ringing
            @unknown default: next[alarm.id] = .scheduled
            }
        }
        if next != states { states = next }
        #endif
    }
}
