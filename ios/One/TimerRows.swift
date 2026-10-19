import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI

/// One timer as a line: icon, name and length, and the time left counting down on its own
/// (`Text(timerInterval:)` is drawn by the system, so nothing re-renders every second). Used by the Today tab.
/// The Timer tab has its own screen (TimerSection.swift). Logic: TimerList.swift.
struct TimerLine: View {
    let timer: RunningTimer
    let isRinging: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isRinging ? "bell.fill" : (timer.isPaused ? "pause.circle" : "timer"))
                .foregroundStyle(Color.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(TimerList.title(timer)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            countdown
                .font(.title3.monospacedDigit())
                .foregroundStyle(timer.isPaused ? Color.secondary : Color.orange)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimerList.spoken(timer, ringing: isRinging, now: .now))
    }

    private var subtitle: String {
        if isRinging { return "Time's up" }
        let total = TimerList.totalText(timer.total)
        return timer.isPaused ? "Paused · \(total)" : total
    }

    @ViewBuilder private var countdown: some View {
        if isRinging {
            Text("0:00")
        } else if timer.isPaused {
            Text(TimerList.clock(timer.remaining(now: .now)))
        } else if let end = timer.endsAt {
            let start = Date.now
            Text(timerInterval: start...max(end, start), pauseTime: nil, countsDown: true, showsHours: timer.total >= 3600)
        } else {
            Text("0:00")
        }
    }
}

extension RowAction {
    /// Stop a timer (cancel while it counts down, dismiss while it rings). Red and rightmost, like Delete.
    static func timerStop(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly) }
            .tint(.red)
    }

    static func timerPause(_ paused: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill").labelStyle(.iconOnly)
        }
        .tint(.orange)
    }
}

/// The running timers at the top of the Today tab: up to two quiet rows with the time left, then "+N more".
/// Tap opens the Timer tab; swipe right to left (or long-press) for Pause/Resume and Stop. Nothing when no timer runs.
struct TodayTimerRows: View {
    var open: () -> Void
    @State private var controller = TimerController.shared

    var body: some View {
        let split = TimerList.rows(controller.timers, ringing: controller.ringing, now: .now)
        ForEach(split.shown) { timer in
            let ringing = controller.ringing.contains(timer.id)
            Button(action: open) {
                TimerLine(timer: timer, isRinging: ringing)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                RowAction.timerStop { withAnimation(.snappy) { controller.cancel(timer.id) } }
                if !ringing {
                    RowAction.timerPause(timer.isPaused) {
                        if timer.isPaused { controller.resume(timer.id) } else { controller.pause(timer.id) }
                    }
                }
            }
            .contextMenu {
                if !ringing {
                    Button { timer.isPaused ? controller.resume(timer.id) : controller.pause(timer.id) } label: {
                        Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                    }
                }
                Button(role: .destructive) { withAnimation(.snappy) { controller.cancel(timer.id) } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the Timer tab")
            .accessibilityIdentifier("todayTimerRow")
        }
        if split.more > 0 {
            Button(action: open) {
                Text(TimerList.moreLabel(split.more))
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .accessibilityIdentifier("todayTimerMore")
        }
    }
}
