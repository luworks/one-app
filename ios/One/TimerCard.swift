import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI

/// The look of Apple's Timers screen, measured from its screenshots (440 pt wide): a dark-green round play button with a
/// light-green triangle, a gray round X, light gray numerals. All adaptive: the same colors read as Clock's light look
/// in light mode (a soft green circle and iOS green triangle).
enum TimerLook {
    static let playFill = adaptive(dark: (18, 41, 20), light: (214, 240, 218))
    static let playGlyph = adaptive(dark: (103, 206, 103), light: (52, 199, 89))

    private static func adaptive(dark: (Int, Int, Int), light: (Int, Int, Int)) -> Color {
        func ui(_ c: (Int, Int, Int)) -> UIColor { UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1) }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// A round button: a filled circle with one symbol. Green play (start / resume), orange pause, gray X (cancel).
struct TimerRoundButton: View {
    enum Kind { case play, pause, cancel }

    let kind: Kind
    var size: CGFloat = 72
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Image(systemName: symbol)
                    .font(.system(size: glyphSize, weight: kind == .cancel ? .light : .semibold))
                    .foregroundStyle(glyph)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch kind {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .cancel: "xmark"
        }
    }

    private var glyphSize: CGFloat {
        switch kind {
        case .cancel: size * 0.42
        default: size * 0.39
        }
    }

    private var fill: Color {
        switch kind {
        case .play: TimerLook.playFill
        case .pause: Color.orange.opacity(0.2)
        case .cancel: Color(.tertiarySystemFill)
        }
    }

    private var glyph: Color {
        switch kind {
        case .play: TimerLook.playGlyph
        case .pause: Color.orange
        case .cancel: Color(.tertiaryLabel)
        }
    }
}

/// A running timer, above the picker (like Clock, several stack): a ring that runs down around the time left, the
/// name under it, and a round pause / resume button and cancel X. While it rings the ring is gone and X says Stop.
/// The time comes from `RunningTimer` (TimerDial.swift); what the controller does is in TimerController.swift.
struct RunningTimerCard: View {
    let timer: RunningTimer
    let isRinging: Bool
    let onPauseResume: () -> Void
    let onCancel: () -> Void

    private let ring: CGFloat = 124
    private let lineWidth: CGFloat = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = timer.remaining(now: context.date)
            let fraction = timer.total > 0 && !isRinging ? left / Double(timer.total) : 0
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(timer.isPaused ? Color(.systemGray) : Color.orange,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(isRinging ? "0:00" : TimerList.clock(left))
                            .font(.system(size: 30, weight: .light).monospacedDigit())
                            .foregroundStyle(timer.isPaused ? Color.secondary : Color.primary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText(countsDown: true))
                            .accessibilityLabel(TimerList.spokenRemaining(timer, ringing: isRinging, now: context.date))
                            .accessibilityIdentifier("timer.remaining")
                        Text(isRinging ? "Time's up" : TimerList.title(timer))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, lineWidth + 12)
                }
                .frame(width: ring, height: ring)
                .accessibilityElement(children: .contain)
                Spacer(minLength: 0)
                if !isRinging {
                    TimerRoundButton(kind: timer.isPaused ? .play : .pause, size: 56, action: onPauseResume)
                        .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
                        .accessibilityIdentifier("timer.pause")
                }
                TimerRoundButton(kind: .cancel, size: 56, action: onCancel)
                    .accessibilityLabel(isRinging ? "Stop" : "Cancel timer")
                    .accessibilityIdentifier(isRinging ? "timer.stop" : "timer.cancel")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer.card")
    }
}
