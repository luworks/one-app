import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI
import AppIntents
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Every countdown timer Today started (AlarmKit, iOS 26+): the ones set on the Timer tab (Apple-style picker and
/// Recents, including the Focus / break presets) and the ones started by voice ("Start a timer in Today for 10 minutes"),
/// Siri, Shortcuts or the Clock schema. Any number run at once, except that a Focus / break preset replaces the
/// previous one. They ring full-screen through Silent and Focus, even with the app closed.
///
/// AlarmKit has no fire date on `Alarm` and lists only this app's own alarms (never the Clock app's, never Siri's
/// built-in timers), so the end times live in `TimerStore` (UserDefaults), keyed by the AlarmKit id.
/// `Ringer.sync` keeps those ids when it cancels leftovers. The pure parts are in TimerList.swift.
@MainActor
@Observable
final class TimerController {
    static let shared = TimerController()

    /// All running timers, in the order they were started.
    private(set) var timers: [RunningTimer]
    /// Ids that are ringing right now.
    private(set) var ringing: Set<UUID> = []
    /// Today's Pomodoro rounds (UserDefaults, starts over at midnight).
    private(set) var log: PomodoroLog = TimerController.initialLog()
    /// The Recents under the picker: what was started, newest first (UserDefaults; `TimerRecents`).
    private(set) var recents: [RecentTimer]
    /// The tone new timers ring with: a name from `AlarmSound.all`, empty for the system alarm sound.
    var sound: String { didSet { if !Self.isUITesting { UserDefaults.standard.set(sound, forKey: Self.soundKey) } } }
    /// A short line under the controls, e.g. when alarms are not allowed.
    var message: String?

    private static let soundKey = "timer.sound"

    init() {
        let (seeded, rings) = Self.seededTimers()
        timers = seeded ?? (Self.isUITesting ? [] : TimerStore.load())
        ringing = rings
        recents = Self.seededRecents() ?? (Self.isUITesting ? [] : TimerRecentsStore.load())
        sound = Self.isUITesting ? "" : (UserDefaults.standard.string(forKey: Self.soundKey) ?? "")
    }

    // MARK: Test seams (debug builds)

    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    /// UI tests only: `-uiTestingTimers 600:Pasta,1500,300:Tea:paused,60:Eggs:ringing` seeds voice timers
    /// (seconds[:label][:paused|:ringing]) and replaces AlarmKit with a fake: Start, Pause, Resume and Stop only change
    /// the list. The simulator denies AlarmKit, so this is the only way a test can run a timer.
    private static func seededTimers() -> ([RunningTimer]?, Set<UUID>) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingTimers"), i + 1 < args.count else { return (nil, []) }
        var list: [RunningTimer] = []
        var rings = Set<UUID>()
        for part in args[i + 1].split(separator: ",") {
            let fields = part.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let seconds = Int(fields[0]) else { continue }
            var timer = RunningTimer.start(id: UUID(), seconds: seconds, now: .now, label: fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil, source: .voice)
            if fields.contains("paused") { timer = timer.paused(now: .now) }
            if fields.contains("ringing") { rings.insert(timer.id) }
            list.append(timer)
        }
        return (list, rings)
        #else
        return (nil, [])
        #endif
    }

    /// UI tests only: `-uiTestingRecents 420,1200,1200:go to lion market,3600:have a rest` seeds the Recents
    /// (seconds[:label], newest first).
    private static func seededRecents() -> [RecentTimer]? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingRecents"), i + 1 < args.count else { return nil }
        return args[i + 1].split(separator: ",").compactMap { part in
            let fields = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let seconds = Int(fields[0]) else { return nil }
            return RecentTimer(seconds: seconds, label: fields.count > 1 ? fields[1] : nil)
        }
        #else
        return nil
        #endif
    }

    /// True when a test replaced AlarmKit with the fake (see `seededTimers`).
    private static let usesFakeAlarms: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestingTimers")
        #else
        false
        #endif
    }()

    // MARK: Start, pause, resume, stop

    /// Starts a countdown and adds it to the Recents. Timers run next to each other, except that a Focus / break preset
    /// (25:00 "Focus", 5:00 "Short break", 15:00 "Long break": the only ones that count Pomodoro rounds) replaces the
    /// previous one. `byHand`: the user set it on the Timer tab, which teaches Siri the phrase.
    @discardableResult
    func start(seconds: Int, label: String? = nil, byHand: Bool = false) async -> RunningTimer? {
        message = nil
        guard seconds > 0 else { return nil }
        let seconds = min(seconds, TimerDial.maxSeconds)
        let label = IntentTimer.label(label)
        let phase = Pomodoro.preset(seconds: seconds, label: label)
        if phase != nil { setLog { $0.pending = nil } }
        let id = UUID()
        let timer = RunningTimer.start(id: id, seconds: seconds, now: .now, phase: phase ?? .focus, label: label,
                                       source: phase == nil ? .voice : .card)
        let previous = phase == nil ? nil : timers.first { $0.isCard }
        if Self.usesFakeAlarms {
            if let previous { ringing.remove(previous.id) }
            set(TimerList.adding(timer, to: timers))
            remember(seconds, label)
            return timer
        }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { message = "Timers need iOS 26 or later."; return nil }
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { await Ringer.requestAuthorization() }
        guard manager.authorizationState == .authorized else {
            message = "Timers need alarm access. Allow alarms for Today in Settings."
            return nil
        }
        if let previous { try? manager.cancel(id: previous.id) }
        // Saved before scheduling so a sync that runs on the AlarmKit update keeps it.
        let before = timers
        set(TimerList.adding(timer, to: timers))
        do {
            _ = try await manager.schedule(id: id, configuration: Self.configuration(for: timer, sound: sound))
            AlarmScheduler.log.info("timer scheduled \(seconds)s")
            remember(seconds, label)
            // Starting by hand teaches Siri the phrase: it can then suggest "Start a timer in Today" for this length.
            if byHand { TimerIntentSupport.donate(seconds: seconds) }
            return timer
        } catch {
            AlarmScheduler.log.error("timer failed \((error as NSError).code, privacy: .public)")
            set(before.filter { $0.id != id })
            message = "Couldn't start the timer."
            return nil
        }
        #else
        message = "Timers need alarm access."
        return nil
        #endif
    }

    func pause(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }), !timer.isPaused else { return }
        if !Self.usesFakeAlarms {
            #if canImport(AlarmKit)
            guard #available(iOS 26, *) else { return }
            do { try AlarmManager.shared.pause(id: id) } catch { message = "Couldn't pause the timer."; return }
            #endif
        }
        replace(timer.paused(now: .now))
    }

    func resume(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }), timer.isPaused else { return }
        if !Self.usesFakeAlarms {
            #if canImport(AlarmKit)
            guard #available(iOS 26, *) else { return }
            do { try AlarmManager.shared.resume(id: id) } catch { message = "Couldn't resume the timer."; return }
            #endif
        }
        replace(timer.resumed(now: .now))
    }

    /// Cancel while counting down (no round), or Stop while ringing (the round already counted when it rang).
    func cancel(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        if ringing.contains(id), timer.isCard { complete(timer) }
        if !Self.usesFakeAlarms {
            #if canImport(AlarmKit)
            if #available(iOS 26, *) {
                if ringing.contains(id) { try? AlarmManager.shared.stop(id: id) }
                try? AlarmManager.shared.cancel(id: id)
            }
            #endif
        }
        ringing.remove(id)
        set(timers.filter { $0.id != id })
    }

    // MARK: Recents

    private func remember(_ seconds: Int, _ label: String?) {
        setRecents(TimerRecents.recording(RecentTimer(seconds: seconds, label: label), in: recents))
    }

    /// Swipe to delete on a Recents row.
    func deleteRecent(id: String) { setRecents(TimerRecents.removing(id: id, from: recents)) }

    private func setRecents(_ list: [RecentTimer]) {
        recents = list
        if !Self.isUITesting { TimerRecentsStore.save(list) }
    }

    /// Lines the list up with AlarmKit (`TimerList.reconcile`): a timer it no longer has (rang and was stopped, or
    /// cancelled from the Lock Screen) leaves; pause/resume done outside the app is followed; the list is read again
    /// from storage first, so a timer started by an intent while the app was closed appears at once.
    /// A Focus round counts only when its countdown ran out: seen ringing, or gone at or after its end time
    /// (stopped from the Lock Screen while the app was closed). Gone early means cancelled: no round.
    func refresh() {
        setLog { _ in }  // midnight reset
        if Self.usesFakeAlarms || Self.isUITesting { return }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { ringing = []; return }
        let stored = TimerStore.load()
        var live: [UUID: LiveTimerState] = [:]
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            switch alarm.state {
            case .alerting: live[alarm.id] = .ringing
            case .paused: live[alarm.id] = .paused
            default: live[alarm.id] = .running
            }
        }
        let result = TimerList.reconcile(local: stored, live: live, now: .now)
        for timer in result.finished where timer.isCard { complete(timer) }
        if result.ringing != ringing { ringing = result.ringing }
        if result.timers != timers || result.timers != stored { set(result.timers) }
        #else
        set([])
        #endif
    }

    /// Follows AlarmKit until the calling task is cancelled (attach it to a view with `.task`), so a timer that ends,
    /// or is paused on the Lock Screen, shows up on whatever tab is open.
    func watch() async {
        refresh()
        if Self.usesFakeAlarms || Self.isUITesting { return }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        for await _ in AlarmManager.shared.alarmUpdates { refresh() }
        #endif
    }

    private func complete(_ timer: RunningTimer) {
        setLog { $0 = $0.completing(timer.pomodoroPhase, id: timer.id, now: .now) }
    }

    private func setLog(_ change: (inout PomodoroLog) -> Void) {
        var next = log.current(.now)
        change(&next)
        if next != log {
            log = next
            PomodoroLog.save(next)
        }
    }

    private static func initialLog() -> PomodoroLog {
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        // UI tests: `-pomodoroRounds N` starts the day with N finished Focus rounds, the last one just ended.
        if let i = args.firstIndex(of: "-pomodoroRounds"), i + 1 < args.count, let n = Int(args[i + 1]) {
            var log = PomodoroLog.empty(.now)
            log.rounds = n
            log.pending = n > 0 ? .focus : nil
            return log
        }
        #endif
        if args.contains("-uiTesting") { return .empty(.now) }
        return PomodoroLog.load()
    }

    private func replace(_ timer: RunningTimer) {
        set(timers.map { $0.id == timer.id ? timer : $0 })
    }

    private func set(_ list: [RunningTimer]) {
        timers = list
        if !Self.isUITesting { TimerStore.save(list) }
    }

    // MARK: AlarmKit configuration

    #if canImport(AlarmKit)
    @available(iOS 26, *)
    nonisolated private static func configuration(for timer: RunningTimer, sound: String) -> AlarmManager.AlarmConfiguration<AlarmScheduler.Meta> {
        // "Focus", "Break" or the user's name: the full-screen alert, the Lock Screen and the Dynamic Island show this.
        let title = LocalizedStringResource(stringLiteral: TimerList.title(timer))
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(title: title,
                                            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
        }
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: title,
                                                   pauseButton: AlarmButton(text: "Pause", textColor: .orange, systemImageName: "pause.fill")),
            paused: AlarmPresentation.Paused(title: "Paused",
                                             resumeButton: AlarmButton(text: "Resume", textColor: .orange, systemImageName: "play.fill")))
        let attributes = AlarmAttributes<AlarmScheduler.Meta>(presentation: presentation, metadata: AlarmMeta(kind: .timer), tintColor: .orange)
        // The entity lets Siri act on this very timer ("pause the timer", "add 5 minutes"): iOS 27.
        return .timer(duration: TimeInterval(timer.total), attributes: attributes,
                      appEntityIdentifier: EntityIdentifier(for: TimerEntity.self, identifier: timer.id),
                      sound: AlarmSound.named(sound)?.alertSound ?? .default)
    }
    #endif
}
