#if os(iOS)
import SwiftUI
import TodayCore
import TodayDesignSystem
import TodayPlatform

/// The one stopwatch. It stores only dates (`StopwatchState`), saved to UserDefaults on every change, so it keeps
/// running while you are on another tab, with the app in the background, or after a relaunch. UI tests start it clean.
@MainActor
@Observable
public final class StopwatchModel {
    public static let shared = StopwatchModel()

    public private(set) var state: StopwatchState
    /// The face shown: digital or analog. Kept across launches.
    public var page: StopwatchPage {
        didSet { defaults.set(page.rawValue, forKey: StopwatchPage.defaultsKey) }
    }

    private let defaults: UserDefaults
    private let now: (() -> Date)?

    /// An injected clock also drives the rendered faces and current lap. Nil keeps production's live timeline dates.
    public init(defaults: UserDefaults = .standard, now: (() -> Date)? = nil,
                arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        self.now = now
        let args = arguments
        if args.contains("-uiTesting") {
            defaults.removeObject(forKey: StopwatchState.defaultsKey)
            defaults.removeObject(forKey: StopwatchPage.defaultsKey)
            state = StopwatchState()
            page = .analog
            #if DEBUG
            // A frozen frame for screenshots: `-uiTestingStopwatch 5.75` is stopped at 5.75 s;
            // `-uiTestingStopwatchLaps 4.2,6.5,5.1` adds finished laps (the time then continues from their sum).
            if let i = args.firstIndex(of: "-uiTestingStopwatch"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
                var laps: [TimeInterval] = []
                if let j = args.firstIndex(of: "-uiTestingStopwatchLaps"), j + 1 < args.count {
                    laps = args[j + 1].split(separator: ",").compactMap { Double($0) }
                }
                state = StopwatchState(startedAt: nil, accumulated: seconds + laps.reduce(0, +), laps: laps)
            }
            if let i = args.firstIndex(of: "-uiTestingStopwatchPage"), i + 1 < args.count, let p = StopwatchPage(rawValue: args[i + 1]) {
                page = p
            }
            #endif
        } else {
            state = StopwatchState.load(from: defaults)
            page = StopwatchPage.load(from: defaults)
        }
    }

    public func startStop() {
        let date = date(at: .now)
        update { $0.isRunning ? $0.stop(at: date) : $0.start(at: date) }
    }

    /// Lap while running, Reset while stopped.
    public func lapReset() {
        let date = date(at: .now)
        update { $0.isRunning ? $0.lap(at: date) : $0.reset() }
    }

    fileprivate func date(at timelineDate: Date) -> Date { now?() ?? timelineDate }

    private func update(_ change: (inout StopwatchState) -> Void) {
        change(&state)
        state.save(to: defaults)
    }
}

/// Stopwatch, as in Apple's Clock app: a big analog dial (seconds ring, 30-minute counter, orange hands) or big digits
/// (swipe sideways, the dots show which), Lap/Reset on the left and Start/Stop on the right, and the laps below,
/// newest first, with the fastest in green and the slowest in red.
public struct StopwatchView: View {
    @State private var model: StopwatchModel
    @State private var scrolledPage: StopwatchPage?

    public init(model: StopwatchModel = .shared) {
        _model = State(initialValue: model)
        _scrolledPage = State(initialValue: model.page)
    }
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize = 76

    private var state: StopwatchState { model.state }

    public var body: some View {
        GeometryReader { geo in
            let side = dialSide(in: geo.size)
            VStack(spacing: 0) {
                pager(side: side)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                controls
                laps
            }
        }
    }

    /// The dial is 305 pt wide like Clock's, and shrinks to fit narrow or short screens so the buttons and laps stay in view.
    private func dialSide(in size: CGSize) -> CGFloat {
        let reference = CGFloat(StopwatchDial.referenceDiameter)
        let room = size.height - 8 - 40 - StopwatchLayout.buttonSize - 12 - 130
        return max(170, min(reference, size.width - 48, room))
    }

    // MARK: Faces

    /// Two pages side by side: digital (left dot) and analog (right dot). Analog is the one you open on.
    private func pager(side: CGFloat) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                digitalFace(side: side)
                    .containerRelativeFrame(.horizontal)
                    .id(StopwatchPage.digital)
                    .accessibilityHidden(model.page != .digital)
                analogFace(side: side)
                    .containerRelativeFrame(.horizontal)
                    .id(StopwatchPage.analog)
                    .accessibilityHidden(model.page != .analog)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledPage)
        .onChange(of: scrolledPage) { _, new in if let new, new != model.page { model.page = new } }
        .onChange(of: model.page) { _, new in if new != scrolledPage { withAnimation(.snappy) { scrolledPage = new } } }
        // The initial scroll position is not applied before the pages are laid out: jump there once they are.
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(model.page, anchor: .leading) }
        }
        }
        .frame(height: side)
        .accessibilityIdentifier("stopwatch.pager")
    }

    private func analogFace(side: CGFloat) -> some View {
        ZStack {
            StopwatchFace()
            TimelineView(.animation(paused: !state.isRunning)) { context in
                let elapsed = state.elapsed(at: model.date(at: context.date))
                ZStack {
                    StopwatchHands(elapsed: elapsed)
                    Text(StopwatchState.format(elapsed))
                        .font(.system(size: StopwatchDial.Metrics.readoutSize, weight: .regular).monospacedDigit())
                        .offset(y: StopwatchDial.Metrics.readoutOffset)
                        .accessibilityLabel(StopwatchState.spoken(elapsed, running: state.isRunning))
                        .accessibilityIdentifier("stopwatch.time")
                }
            }
        }
        .frame(width: StopwatchDial.referenceDiameter, height: StopwatchDial.referenceDiameter)
        .scaleEffect(side / CGFloat(StopwatchDial.referenceDiameter))
        .frame(width: side, height: side)
    }

    private func digitalFace(side: CGFloat) -> some View {
        TimelineView(.animation(paused: !state.isRunning)) { context in
            let elapsed = state.elapsed(at: model.date(at: context.date))
            Text(StopwatchState.digital(elapsed))
                .font(.system(size: digitSize, weight: .thin).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: side)
                .accessibilityLabel(StopwatchState.spoken(elapsed, running: state.isRunning))
                .accessibilityIdentifier("stopwatch.timeLarge")
        }
    }

    // MARK: Buttons and dots

    private var controls: some View {
        ZStack {
            HStack {
                RoundButton(title: state.isRunning || !state.hasTime ? "Lap" : "Reset",
                            kind: .neutral) { model.lapReset() }
                    .disabled(!state.hasTime)
                    .accessibilityIdentifier("stopwatch.lapReset")
                Spacer()
                RoundButton(title: state.isRunning ? "Stop" : "Start",
                            kind: state.isRunning ? .stop : .start) { model.startStop() }
                    .accessibilityIdentifier("stopwatch.startStop")
            }
            pageDots
        }
        .padding(.horizontal, StopwatchLayout.edge)
        .padding(.bottom, 12)
        .sensoryFeedback(.impact(weight: .light), trigger: state)
    }

    /// Two dots between the buttons, like a page control: the white one is the face you see.
    private var pageDots: some View {
        HStack(spacing: StopwatchLayout.dotGap) {
            ForEach(StopwatchPage.allCases, id: \.self) { page in
                Circle()
                    .fill(Color.primary.opacity(page == model.page ? 1 : 0.45))
                    .frame(width: StopwatchLayout.dot, height: StopwatchLayout.dot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stopwatch face")
        .accessibilityValue(model.page == .analog ? "Analog" : "Digital")
        .accessibilityIdentifier("stopwatch.dots")
        .accessibilityAdjustableAction { direction in
            let all = StopwatchPage.allCases
            guard let i = all.firstIndex(of: model.page) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            if all.indices.contains(next) { model.page = all[next] }
        }
    }

    // MARK: Laps

    private var laps: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if state.hasTime {
                    LapSeparator()
                    TimelineView(.animation(paused: !state.isRunning)) { context in
                        LapRow(number: state.laps.count + 1, time: state.currentLap(at: model.date(at: context.date)), mark: nil)
                    }
                    LapSeparator()
                }
                ForEach(Array(state.laps.indices.reversed()), id: \.self) { i in
                    LapRow(number: i + 1, time: state.laps[i], mark: state.mark(forLap: i))
                    LapSeparator()
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Sizes taken from the Clock app (points).
private enum StopwatchLayout {
    static let buttonSize: CGFloat = 84
    /// Distance from the screen edge to the round buttons, and to the lap rows' separators.
    static let edge: CGFloat = 16
    static let rowInset: CGFloat = 15
    static let rowHeight: CGFloat = 44
    static let dot: CGFloat = 7
    static let dotGap: CGFloat = 10
}

// MARK: - The analog face

/// Ticks and numerals: drawn once (they only change with the size or the light/dark look).
private struct StopwatchFace: View {
    private typealias M = StopwatchDial.Metrics

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            drawRing(&context, center: c)
            drawSubDial(&context, center: CGPoint(x: c.x, y: c.y + M.subCenterOffset))
        }
        .accessibilityHidden(true)
    }

    private func drawRing(_ context: inout GraphicsContext, center c: CGPoint) {
        var white = Path(), grey = Path()
        for i in 0..<StopwatchDial.tickCount {
            let kind = StopwatchDial.tick(at: i)
            let length = kind == .quarter ? M.shortTickLength : M.longTickLength
            let segment = Self.segment(center: c, angle: StopwatchDial.angle(ofTick: i), from: M.outerRadius - length, to: M.outerRadius)
            if kind == .major { white.addPath(segment) } else { grey.addPath(segment) }
        }
        context.stroke(grey, with: .color(Color.primary.opacity(M.greyTickOpacity)), lineWidth: M.tickWidth)
        context.stroke(white, with: .color(.primary), lineWidth: M.tickWidth)

        for n in StopwatchDial.numerals {
            let p = Self.point(center: c, angle: StopwatchDial.numeralAngle(n), radius: M.numeralRadius)
            let text = context.resolve(Text("\(n)").font(.system(size: M.numeralSize, weight: .regular)).foregroundStyle(Color.primary))
            context.draw(text, at: p, anchor: .center)
        }
    }

    private func drawSubDial(_ context: inout GraphicsContext, center c: CGPoint) {
        var white = Path(), grey = Path()
        for i in 0..<StopwatchDial.subTickCount {
            let kind = StopwatchDial.subTick(at: i)
            let length = kind == .major ? M.subMajorLength : kind == .minute ? M.subMinuteLength : M.subHalfLength
            let segment = Self.segment(center: c, angle: StopwatchDial.angle(ofSubTick: i), from: M.subOuterRadius - length, to: M.subOuterRadius)
            if kind == .major { white.addPath(segment) } else { grey.addPath(segment) }
        }
        context.stroke(grey, with: .color(Color.primary.opacity(M.greyTickOpacity)), lineWidth: M.subTickWidth)
        context.stroke(white, with: .color(.primary), lineWidth: M.subMajorWidth)

        for n in StopwatchDial.subNumerals {
            let p = Self.point(center: c, angle: StopwatchDial.subNumeralAngle(n), radius: M.subNumeralRadius)
            let text = context.resolve(Text("\(n)").font(.system(size: M.subNumeralSize, weight: .regular)).foregroundStyle(Color.primary))
            context.draw(text, at: p, anchor: .center)
        }
    }

    static func point(center c: CGPoint, angle degrees: Double, radius: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: c.x + radius * sin(a), y: c.y - radius * cos(a))
    }

    static func segment(center c: CGPoint, angle: Double, from r0: Double, to r1: Double) -> Path {
        var p = Path()
        p.move(to: point(center: c, angle: angle, radius: r0))
        p.addLine(to: point(center: c, angle: angle, radius: r1))
        return p
    }
}

/// The two hands, redrawn every frame while running (nothing else is).
private struct StopwatchHands: View {
    let elapsed: TimeInterval
    private typealias M = StopwatchDial.Metrics

    /// Clock's orange, a little softer than the system orange.
    static let orange = Color(red: 240 / 255, green: 151 / 255, blue: 72 / 255)

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            // Short hand in the 30-minute counter, with a solid hub.
            let sub = CGPoint(x: c.x, y: c.y + M.subCenterOffset)
            let minuteAngle = StopwatchDial.minutesHandAngle(elapsed: elapsed)
            context.stroke(StopwatchFace.segment(center: sub, angle: minuteAngle, from: 0, to: M.minutesHandLength),
                           with: .color(Self.orange), style: StrokeStyle(lineWidth: M.handWidth, lineCap: .butt))
            context.fill(Path(ellipseIn: CGRect(x: sub.x - M.minutesHubRadius, y: sub.y - M.minutesHubRadius,
                                                width: 2 * M.minutesHubRadius, height: 2 * M.minutesHubRadius)), with: .color(Self.orange))

            // Long hand: from the hollow hub to the ring, and a short tail the other way.
            let angle = StopwatchDial.secondsHandAngle(elapsed: elapsed)
            var hand = StopwatchFace.segment(center: c, angle: angle, from: M.hubOuterRadius - 0.5, to: M.secondsHandTip)
            hand.addPath(StopwatchFace.segment(center: c, angle: angle + 180, from: M.hubOuterRadius - 0.5, to: M.secondsHandTail))
            context.stroke(hand, with: .color(Self.orange), style: StrokeStyle(lineWidth: M.handWidth, lineCap: .butt))
            let ringRadius = M.hubOuterRadius - M.hubStroke / 2
            context.stroke(Path(ellipseIn: CGRect(x: c.x - ringRadius, y: c.y - ringRadius, width: 2 * ringRadius, height: 2 * ringRadius)),
                           with: .color(Self.orange), lineWidth: M.hubStroke)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Laps

private struct LapRow: View {
    let number: Int
    let time: TimeInterval
    let mark: LapMark?

    private var color: Color {
        switch mark {
        case .fastest: Color(.systemGreen)
        case .slowest: Color(.systemRed)
        case nil: .primary
        }
    }

    var body: some View {
        HStack {
            Text("Lap \(number)")
            Spacer()
            Text(StopwatchState.format(time)).monospacedDigit()
        }
        .font(.body)
        .foregroundStyle(color)
        .padding(.horizontal, StopwatchLayout.rowInset)
        .frame(minHeight: StopwatchLayout.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StopwatchState.spokenLap(number: number, time: time, mark: mark))
        .accessibilityIdentifier("stopwatch.lap")
    }
}

private struct LapSeparator: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 1 / scale)
            .padding(.horizontal, StopwatchLayout.rowInset)
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Clock's round control: a flat filled circle, the title in the middle. Lap/Reset is grey; Start is green on dark
/// green; Stop is red on dark red.
private struct RoundButton: View {
    enum Kind { case neutral, start, stop }

    let title: String
    let kind: Kind
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body))
                .foregroundStyle(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: StopwatchLayout.buttonSize, height: StopwatchLayout.buttonSize)
                .background(fill, in: Circle())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
    }

    private var text: Color {
        switch kind {
        case .neutral: .primary
        case .start: Self.adaptive(light: (0.10, 0.60, 0.25), dark: (103, 206, 103))
        case .stop: Self.adaptive(light: (0.86, 0.15, 0.12), dark: (255, 105, 97))
        }
    }

    private var fill: Color {
        switch kind {
        case .neutral: Self.adaptive(light: (229, 229, 234), dark: (51, 51, 51))
        case .start: Self.adaptive(light: (219, 242, 223), dark: (18, 41, 20))
        case .stop: Self.adaptive(light: (252, 224, 222), dark: (52, 18, 16))
        }
    }

    /// Components above 1 are 0-255 values; at most 1 are 0-1 fractions.
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        func ui(_ c: (Double, Double, Double)) -> UIColor {
            let k = max(c.0, c.1, c.2) > 1 ? 255.0 : 1.0
            return UIColor(red: c.0 / k, green: c.1 / k, blue: c.2 / k, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}
#endif
