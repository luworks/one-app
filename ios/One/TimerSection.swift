import SwiftUI

/// The Timer section of the Clock tab, copied from the Timers screen of Apple's Clock app (iPhone, 440 pt wide):
/// the large "Timers" title, the running timers (rings, several stack), Apple's hours / min / sec wheel with a gray X
/// and a green play button under it, a card with Label and Sound, and "Recents": the last timers you started, each
/// a big light time with a small caption and a round play button. Tap the play button to start it at once, tap
/// the rest of the row to put it on the wheel, swipe left to delete it.
/// Differences from Apple on purpose: no Edit button (Recents are deleted by swiping, like every list in the app);
/// the three Pomodoro presets (25:00 Focus, 5:00 Short break, 15:00 Long break) fill Recents until you start your own.
/// Logic: TimerRecents.swift, TimerList.swift, Pomodoro.swift; the countdowns: TimerController.swift.
struct TimerSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = TimerController.shared
    /// What the wheel shows; starts at the last timer you started.
    @State private var seconds: Int
    @State private var label = ""
    @State private var showsSound = false

    init() {
        _seconds = State(initialValue: TimerController.shared.recents.first?.seconds ?? 0)
    }

    /// Apple's screen insets: the title 20 pt, the buttons and card 26 pt, Recents 30 pt (28 on the right).
    private enum Inset {
        static let title: CGFloat = 20
        static let card: CGFloat = 26
        static let recents: CGFloat = 30
    }

    var body: some View {
        NavigationStack {
            List {
                Text("Timers")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("timer.title")
                    .row(top: 2, bottom: 0, leading: Inset.title, trailing: Inset.title)
                runningCards
                TimerWheel(seconds: $seconds)
                    .frame(height: 216)
                    .accessibilityIdentifier("timer.picker")
                    .row(top: 0, bottom: 0, leading: 0, trailing: 0)
                pickerButtons.row(top: 4, bottom: 0, leading: Inset.card, trailing: Inset.card)
                messageRow
                optionsCard.row(top: 20, bottom: 0, leading: Inset.card, trailing: Inset.card)
                recentsHeader.row(top: 40, bottom: 8, leading: Inset.recents + 1, trailing: Inset.recents)
                recentRows
                siriNote.row(top: 18, bottom: 24, leading: Inset.recents, trailing: Inset.recents)
            }
            .listStyle(.plain)
            // Runtime List bounds extend 32 pt behind the floating composer; leave another 8 pt of clearance.
            .contentMargins(.bottom, 40, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsSound) {
                SoundScreen(sound: Binding(get: { controller.sound }, set: { controller.sound = $0 }))
            }
        }
        .onAppear { controller.refresh() }
        .onChange(of: AlarmCenter.shared.states) { controller.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.refresh() } }
    }

    // MARK: Running timers

    @ViewBuilder private var runningCards: some View {
        ForEach(TimerList.ordered(controller.timers, ringing: controller.ringing, now: .now)) { timer in
            RunningTimerCard(
                timer: timer,
                isRinging: controller.ringing.contains(timer.id),
                onPauseResume: { if timer.isPaused { controller.resume(timer.id) } else { controller.pause(timer.id) } },
                onCancel: { withAnimation(.snappy) { controller.cancel(timer.id) } })
                .row(top: 14, bottom: 0, leading: Inset.card, trailing: Inset.card)
        }
    }

    // MARK: Picker and its buttons

    private var pickerButtons: some View {
        HStack {
            TimerRoundButton(kind: .cancel) {
                seconds = 0
                label = ""
            }
            .opacity(seconds > 0 || !label.isEmpty ? 1 : 0.5)
            .disabled(seconds == 0 && label.isEmpty)
            .accessibilityLabel("Clear")
            .accessibilityIdentifier("timer.reset")
            Spacer()
            TimerRoundButton(kind: .play) { start(RecentTimer(seconds: seconds, label: label), clearsLabel: true) }
                .opacity(seconds > 0 ? 1 : 0.5)
                .disabled(seconds == 0)
                .accessibilityLabel("Start timer \(IntentTimer.spoken(seconds: seconds))")
                .accessibilityIdentifier("timer.start")
        }
    }

    /// "Timers need alarm access", with a way to Settings when alarms are denied.
    @ViewBuilder private var messageRow: some View {
        if let message = controller.message {
            HStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("timer.message")
                if Ringer.isDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .row(top: 12, bottom: 0, leading: Inset.card + 4, trailing: Inset.card)
        }
    }

    /// Label (a text field, "Timer" until you name it) and Sound (opens the list of tones).
    private var optionsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Label")
                TextField("Timer", text: $label)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .accessibilityIdentifier("timer.label")
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            Divider().padding(.horizontal, 20)
            Button { showsSound = true } label: {
                HStack {
                    Text("Sound")
                    Spacer()
                    Text(controller.sound.isEmpty ? "Default" : controller.sound).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.leading, 16)
                .padding(.trailing, 20)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timer.sound")
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Recents

    private var recentsHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recents")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            // A quiet count, only once a Focus round has run out today.
            if controller.log.rounds > 0 {
                Text("Focus rounds today: \(controller.log.rounds)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Pomodoro.spokenRounds(controller.log.rounds))
                    .accessibilityIdentifier("pomodoro.rounds")
            }
        }
    }

    @ViewBuilder private var recentRows: some View {
        let seeded = controller.recents.isEmpty
        ForEach(Array(TimerRecents.shown(controller.recents).enumerated()), id: \.element.id) { index, recent in
            RecentTimerRow(
                recent: recent,
                onLoad: { load(recent) },
                onStart: { start(recent, clearsLabel: false) })
                .listRowSeparator(.visible, edges: index == 0 ? .all : .bottom)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Inset.recents, bottom: 0, trailing: Inset.recents - 2))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // The seeded Pomodoro presets are not the user's recents: nothing to delete yet.
                    if !seeded {
                        RowAction.delete { withAnimation(.snappy) { controller.deleteRecent(id: recent.id) } }
                    }
                }
        }
    }

    /// What iOS allows: Today can show only the timers it started. A timer made with Siri's default Clock is invisible
    /// to other apps (AlarmKit lists only the app's own), so the way to see a voice timer here is to ask for it by name.
    private var siriNote: some View {
        Text("Timers set with Siri's default Clock aren't visible to other apps. Say “Start a timer in Today for 10 minutes” and it shows here and on the Today tab.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("timer.siriNote")
    }

    // MARK: Actions

    private func start(_ recent: RecentTimer, clearsLabel: Bool) {
        guard recent.seconds > 0 else { return }
        if clearsLabel { label = "" }
        Task { await controller.start(seconds: recent.seconds, label: recent.label, byHand: true) }
    }

    /// Puts a recent on the wheel and in the Label field, without starting it.
    private func load(_ recent: RecentTimer) {
        seconds = recent.seconds
        label = recent.label ?? ""
    }
}

/// One Recents row: a big light time with its caption (the name, or "7 min"), and a round play button.
/// The numerals scale with Dynamic Type up to a limit, and shrink to fit a long time.
private struct RecentTimerRow: View {
    let recent: RecentTimer
    let onLoad: () -> Void
    let onStart: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onLoad) {
                VStack(alignment: .leading, spacing: -6) {
                    Text(TimerList.clock(TimeInterval(recent.seconds)))
                        .font(.system(size: min(digitSize, 68), weight: .light))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(TimerRecents.caption(recent))
                        .font(.callout)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Timer \(IntentTimer.spoken(seconds: recent.seconds))" + (recent.label.map { ", \($0)" } ?? ""))
            .accessibilityHint("Puts it on the picker")
            .accessibilityIdentifier("timer.recent")
            TimerRoundButton(kind: .play, size: 56, action: onStart)
                .accessibilityLabel(TimerRecents.startLabel(recent))
                .accessibilityIdentifier("timer.recent.start")
        }
        .frame(minHeight: 91)
    }
}

private extension View {
    /// A plain list row for the parts of the screen that are not list rows (title, wheel, buttons, card).
    func row(top: CGFloat, bottom: CGFloat, leading: CGFloat, trailing: CGFloat) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
    }
}
