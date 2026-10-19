import TodayShared
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

// The Lock Screen and Dynamic Island countdown for a running timer or a snoozing alarm.
// AlarmKit starts and updates the Live Activity itself; this only draws `AlarmAttributes<AlarmMeta>`.
// Titles and buttons come from the `AlarmPresentation` the app scheduled ("Focus" or "Break" for the Pomodoro timer, or the alarm's label).

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmMeta>.self) { context in
            AlarmLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(context.attributes.tintColor)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        AlarmTitle(attributes: attributes, state: state)
                    } icon: {
                        AlarmIcon(attributes: attributes)
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTimeText(state: state)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(attributes.tintColor)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmButtons(attributes: attributes, state: state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                AlarmIcon(attributes: attributes)
            } compactTrailing: {
                AlarmTimeText(state: state)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 56)
                    .foregroundStyle(attributes.tintColor)
            } minimal: {
                AlarmProgressRing(attributes: attributes, state: state)
            }
            .keylineTint(attributes.tintColor)
        }
    }
}

// MARK: Lock Screen

private struct AlarmLockScreenView: View {
    let attributes: AlarmAttributes<AlarmMeta>
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    AlarmTitle(attributes: attributes, state: state)
                } icon: {
                    AlarmIcon(attributes: attributes)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                AlarmTimeText(state: state)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(attributes.tintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            AlarmButtons(attributes: attributes, state: state)
        }
        .padding(16)
    }
}

// MARK: Pieces

private struct AlarmIcon: View {
    let attributes: AlarmAttributes<AlarmMeta>

    var body: some View {
        Image(systemName: attributes.metadata?.kind == .alarm ? "alarm.fill" : "timer")
            .foregroundStyle(attributes.tintColor)
    }
}

private struct AlarmTitle: View {
    let attributes: AlarmAttributes<AlarmMeta>
    let state: AlarmPresentationState

    var body: some View {
        let presentation = attributes.presentation
        switch state.mode {
        case .paused:
            // "Paused" (the timer's paused title), else the alarm's own title.
            Text(presentation.paused?.title ?? presentation.countdown?.title ?? presentation.alert.title)
        case .alert:
            Text(presentation.alert.title)
        default:
            Text(presentation.countdown?.title ?? presentation.alert.title)
        }
    }
}

/// The time left: ticking while counting down, frozen while paused.
private struct AlarmTimeText: View {
    let state: AlarmPresentationState

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let c):
                if c.startDate <= c.fireDate {
                    Text(timerInterval: c.startDate...c.fireDate, countsDown: true)
                } else {
                    Text(Self.format(0))
                }
            case .paused(let p):
                Text(Self.format(max(0, p.totalCountdownDuration - p.previouslyElapsedDuration)))
            case .alert:
                Text("Ringing")
            @unknown default:
                Text("")
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Minimal island: a ring that empties as the countdown runs.
private struct AlarmProgressRing: View {
    let attributes: AlarmAttributes<AlarmMeta>
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let c):
            let start = c.startDate.addingTimeInterval(-c.previouslyElapsedDuration)
            if start <= c.fireDate {
                ProgressView(timerInterval: start...c.fireDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    AlarmIcon(attributes: attributes).font(.system(size: 10))
                }
                .progressViewStyle(.circular)
                .tint(attributes.tintColor)
            } else {
                AlarmIcon(attributes: attributes)
            }
        case .paused(let p):
            let total = max(p.totalCountdownDuration, 1)
            ProgressView(value: max(0, total - p.previouslyElapsedDuration), total: total) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "pause.fill").font(.system(size: 9))
            }
            .progressViewStyle(.circular)
            .tint(attributes.tintColor)
        default:
            AlarmIcon(attributes: attributes)
        }
    }
}

/// Pause/Resume (only when the presentation has them: the timer, not a snooze) and Stop.
private struct AlarmButtons: View {
    let attributes: AlarmAttributes<AlarmMeta>
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 10) {
            switch state.mode {
            case .countdown:
                if let pause = attributes.presentation.countdown?.pauseButton {
                    circle(pause.systemImageName, label: pause.text, intent: PauseAlarmIntent(alarmID: state.alarmID))
                }
            case .paused:
                if let resume = attributes.presentation.paused?.resumeButton {
                    circle(resume.systemImageName, label: resume.text, intent: ResumeAlarmIntent(alarmID: state.alarmID))
                }
            default:
                EmptyView()
            }
            circle("xmark", label: "Stop", intent: StopAlarmIntent(alarmID: state.alarmID), prominent: false)
        }
    }

    private func circle(_ symbol: String, label: LocalizedStringResource, intent: some LiveActivityIntent,
                        prominent: Bool = true) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(prominent ? attributes.tintColor : .secondary)
                .background(Circle().fill((prominent ? attributes.tintColor : Color.gray).opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
