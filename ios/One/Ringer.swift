import Foundation
import SwiftData
import SwiftUI
import os
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Real alarms (AlarmKit, iOS 26+) for items marked "Ring as alarm": full-screen, ring through Silent
/// and Focus. Stopping the alarm never completes the task; only Done does.
@MainActor
enum Ringer {
    static var isAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// True when the user turned alarms off for one. in Settings.
    static var isDenied: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26, *) { return AlarmManager.shared.authorizationState == .denied }
        #endif
        return false
    }

    /// Rebuilds all alarms from the current data.
    static func sync(_ context: ModelContext) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        let now = Date.now
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.ringsAsAlarm && !$0.isDone }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<OneEvent>(predicate: #Predicate { $0.ringsAsAlarm }))) ?? []
        let due: [(String, Date)] = tasks.compactMap { t in t.reminderDate.map { (t.title, $0) } }
            + events.compactMap { e in e.reminderDate.map { (e.title, $0) } }
        await AlarmScheduler.replaceAll(with: due.filter { $0.1 > now })
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26, *)
private enum AlarmScheduler {
    struct Meta: AlarmMetadata {}

    static let log = Logger(subsystem: "com.luworks.one", category: "alarms")

    static func replaceAll(with alarms: [(title: String, date: Date)]) async {
        let manager = AlarmManager.shared
        log.info("sync: \(alarms.count) alarm(s), auth \(String(describing: manager.authorizationState))")
        if manager.authorizationState == .notDetermined, !alarms.isEmpty {
            do {
                let state = try await manager.requestAuthorization()
                log.info("auth result \(String(describing: state))")
            } catch {
                log.error("auth failed \(error.localizedDescription)")
            }
        }
        guard manager.authorizationState == .authorized else { return }
        for existing in (try? manager.alarms) ?? [] { try? manager.cancel(id: existing.id) }
        for alarm in alarms.prefix(30) {
            let title = LocalizedStringResource(stringLiteral: alarm.title)
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: title)
            } else {
                alert = AlarmPresentation.Alert(title: title,
                                                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
            }
            let attributes = AlarmAttributes<Meta>(presentation: AlarmPresentation(alert: alert), tintColor: .orange)
            do {
                _ = try await manager.schedule(id: UUID(),
                                               configuration: .alarm(schedule: .fixed(alarm.date), attributes: attributes))
                log.info("scheduled \(alarm.title, privacy: .public) at \(alarm.date)")
            } catch {
                log.error("schedule failed \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
