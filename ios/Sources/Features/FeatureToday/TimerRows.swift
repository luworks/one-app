#if os(iOS)
import One
import TodayPlannerUI
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureHealth
import SwiftUI

/// One timer as a line: icon, name and length, and the time left counting down on its own
/// (the countdown reads the session clock on each timeline tick). Used by the Today tab.
/// The Timer tab has its own screen (TimerSection.swift). Logic: TimerList.swift.
struct TimerLine: View {
    @Environment(PlannerPresentation.self) private var presentation
    let timer: RunningTimer
    let isRinging: Bool

    package var body: some View {
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
        .accessibilityLabel(TimerList.spoken(timer, ringing: isRinging, now: presentation.now))
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
            Text(TimerList.clock(timer.remaining(now: presentation.now)))
        } else if timer.endsAt != nil {
            TimelineView(.periodic(from: presentation.now, by: 1)) { _ in
                Text(TimerList.clock(timer.remaining(now: presentation.now)))
            }
        } else {
            Text("0:00")
        }
    }
}

/// The running timers at the top of the Today tab: up to two quiet rows with the time left, then "+N more".
/// Tap opens the Timer tab; swipe right to left (or long-press) for Pause/Resume and Stop. Nothing when no timer runs.
package struct TodayTimerRows: View {
    @Environment(PlannerPresentation.self) private var presentation
    let controller: any TimerService
    var open: () -> Void

    package init(controller: any TimerService, open: @escaping () -> Void) { self.controller = controller; self.open = open }

    package var body: some View {
        let split = TimerList.rows(controller.timers, ringing: controller.ringing, now: presentation.now)
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

#endif
