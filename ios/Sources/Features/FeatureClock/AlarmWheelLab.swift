#if os(iOS) && DEBUG
  import SwiftUI
  import TodayCore
  import UIKit

  /// Debug only (Settings → Developer): compares three alarm time pickers on the same set-a-time tasks. A is the
  /// alarm editor's own picker, B the custom wheel with fixed spacing, C the same wheel with speed-sensitive minutes.
  /// Nothing here creates an alarm; trials stay in this app's files until exported.
  package struct AlarmWheelLab: View {
    private let runtime: PlannerRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var log = WheelLabLog.load(from: AlarmWheelLab.logURL)
    @State private var mode = Mode.practice
    @State private var practiceVariant = WheelLabVariant.c
    @State private var session: Int?
    @State private var steps: [WheelLabStep] = []
    @State private var index = 0
    @State private var counter: WheelLabCounter?
    @State private var minutes = 7 * 60 + 30
    @State private var resetID = 0
    @State private var rating: WheelLabVariant?
    @State private var wrong = 0
    @State private var right = 0
    @State private var saveFailed = false

    package init(runtime: PlannerRuntime) { self.runtime = runtime }

    enum Mode: String, CaseIterable {
      case practice = "Practice"
      case session = "Session"
    }

    private var step: WheelLabStep? { steps.indices.contains(index) ? steps[index] : nil }
    private var variant: WheelLabVariant { step?.variant ?? practiceVariant }
    /// Reduce Motion keeps C's minutes at fixed spacing (recorded with each trial).
    private var adaptive: Bool { variant == .c && !reduceMotion }

    package var body: some View {
      VStack(spacing: 16) {
        Picker("Mode", selection: $mode) {
          ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .disabled(session != nil)
        .accessibilityIdentifier("wheelLab.mode")

        if mode == .practice {
          Picker("Version", selection: $practiceVariant) {
            ForEach(WheelLabVariant.allCases, id: \.self) { Text($0.title) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("wheelLab.variant")
        }

        taskCard
        readout
        wheel
          .frame(height: 216)
          .frame(maxWidth: .infinity)
        footer
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Alarm wheel lab")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          // Leaving for Results would end a running session (onDisappear).
          NavigationLink("Results") { WheelLabResults(log: $log, save: save) }
            .disabled(session != nil)
            .accessibilityIdentifier("wheelLab.results")
        }
      }
      // A stray downward drag on the wheel area must not close Settings mid-trial.
      .interactiveDismissDisabled()
      .environment(\.calendar, runtime.calendar)
      .environment(\.locale, runtime.locale)
      .environment(\.timeZone, runtime.calendar.timeZone)
      .sensoryFeedback(.success, trigger: right)
      .sensoryFeedback(.error, trigger: wrong)
      .onChange(of: practiceVariant) { _, _ in restart(at: minutes) }
      .onChange(of: mode) { _, new in if new == .practice { endSession() } }
      .onDisappear { endSession() }
      .sheet(item: $rating) { variant in
        WheelLabRatingSheet(variant: variant) { easy, control in
          log.ratings.append(
            WheelLabRating(
              date: Date(), session: session ?? 0, variant: variant, easyToStop: easy,
              inControl: control))
          save()
          rating = nil
          if step == nil { endSession() }
        }
        .interactiveDismissDisabled()
      }
      .alert("Couldn’t save the trial", isPresented: $saveFailed) {
        Button("OK", role: .cancel) {}
      }
    }

    // MARK: Parts

    @ViewBuilder private var taskCard: some View {
      VStack(spacing: 4) {
        if let step {
          Text("Set \(Self.clock(step.task.target, locale: runtime.locale))")
            .font(.title2.weight(.semibold))
            .accessibilityIdentifier("wheelLab.target")
          Text(
            "Trial \(index + 1) of \(steps.count) · \(step.variant.title) · Session \(session ?? 0)"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        } else if mode == .session {
          Text("Session \(log.nextSession)")
            .font(.title2.weight(.semibold))
          Text(
            "\(3 * WheelLabTask.all.count) trials in three blocks, one version per block. The order changes each session."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        } else {
          Text(variant.title)
            .font(.title2.weight(.semibold))
          Text(practiceNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 64)
    }

    private var practiceNote: String {
      if variant == .c && reduceMotion {
        return "Reduce Motion is on, so C keeps fixed spacing. Nothing is recorded."
      }
      return "Try it freely. Nothing is recorded."
    }

    private var readout: some View {
      let parts = AlarmPlan.timeParts(
        hour: minutes / 60, minute: minutes % 60, locale: runtime.locale)
      return HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(parts.time).font(.system(size: 40, weight: .light).monospacedDigit())
        if let suffix = parts.suffix { Text(suffix).font(.title3) }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("wheelLab.readout")
    }

    @ViewBuilder private var wheel: some View {
      switch variant {
      case .a:
        AlarmTimePicker(time: dateBinding)
          .id(resetID)
          .background(
            TouchProbe { down, time in
              if down {
                counter?.touchDown(at: time)
              } else {
                counter?.lifted(at: time)
              }
            })
      case .b, .c:
        TimeWheelPicker(
          minutes: $minutes, resetID: resetID, adaptiveMinutes: adaptive, locale: runtime.locale
        ) { event, time in
          switch event {
          case .touchDown: counter?.touchDown(at: time)
          case .liftedWhileMoving: counter?.lifted(at: time)
          case .reversal: counter?.reversal()
          case .settled(let value): counter?.settled(minutes: value, at: time)
          }
        }
        .id(variant)
        .accessibilityIdentifier("wheelLab.wheel")
      }
    }

    @ViewBuilder private var footer: some View {
      if step != nil {
        Button(action: confirm) {
          Text("Set").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("wheelLab.set")
        Button("End Session", role: .destructive) { endSession() }
          .font(.footnote)
      } else if mode == .session {
        Button(action: startSession) {
          Text("Start Session \(log.nextSession)").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("wheelLab.start")
      }
    }

    /// A's wheel works on a `Date`; the lab keeps minutes of the day. Any fixed day works for hours and minutes.
    private var dateBinding: Binding<Date> {
      let day = runtime.calendar.startOfDay(for: Self.referenceDay)
      return Binding(
        get: {
          runtime.calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        },
        set: { date in
          let parts = runtime.calendar.dateComponents([.hour, .minute], from: date)
          let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
          guard value != minutes else { return }
          minutes = value
          // The system wheel only reports where it lands.
          counter?.settled(minutes: value, at: CACurrentMediaTime())
        })
    }

    private static let referenceDay = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: Flow

    private func startSession() {
      let number = log.nextSession
      session = number
      steps = WheelLabPlan.steps(session: number)
      index = 0
      begin()
    }

    private func begin() {
      guard let step else { return }
      restart(at: step.task.start)
      counter = WheelLabCounter(task: step.task, shownAt: CACurrentMediaTime())
    }

    /// Shows `start` with every wheel at rest (a new trial, a version switch).
    private func restart(at start: Int) {
      minutes = start
      resetID += 1
    }

    private func endSession() {
      session = nil
      steps = []
      index = 0
      counter = nil
    }

    /// Set: stops the custom wheel on what it shows, so the shown, confirmed and spoken values are the same one.
    private func confirm() {
      let now = CACurrentMediaTime()
      guard let step, var counter else { return }
      if variant != .a { resetID += 1 }
      guard minutes == step.task.target else {
        counter.wrongConfirm()
        self.counter = counter
        wrong += 1
        return
      }
      right += 1
      log.trials.append(
        WheelLabTrial(
          id: runtime.nextID(), date: runtime.now(), session: session ?? 0, block: step.block,
          variant: step.variant, counter: counter, confirmedAt: now,
          reduceMotion: reduceMotion, voiceOver: voiceOver, device: Self.device,
          system: "iOS \(UIDevice.current.systemVersion)", build: Self.build))
      save()
      index += 1
      let next = self.step
      if next?.block != step.block { rating = step.variant }
      if next != nil { begin() } else { self.counter = nil }
    }

    private func save() {
      do {
        try log.save(to: Self.logURL)
      } catch {
        saveFailed = true
      }
    }

    // MARK: Facts

    static var logURL: URL {
      URL.applicationSupportDirectory.appending(path: "WheelLab", directoryHint: .isDirectory)
        .appending(path: "log.json")
    }

    static func clock(_ minutes: Int, locale: Locale) -> String {
      let parts = AlarmPlan.timeParts(hour: minutes / 60 % 24, minute: minutes % 60, locale: locale)
      return [parts.time, parts.suffix].compactMap { $0 }.joined(separator: " ")
    }

    /// The model identifier (for example "iPhone17,1"), which names the exact iPhone.
    static let device: String = {
      var info = utsname()
      uname(&info)
      return withUnsafeBytes(of: &info.machine) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
      }
    }()

    /// Version, build and when this binary was built, so results map to a code version.
    static let build: String = {
      let info = Bundle.main.infoDictionary
      let version = info?["CFBundleShortVersionString"] as? String ?? "?"
      let number = info?["CFBundleVersion"] as? String ?? "?"
      let values = try? Bundle.main.executableURL?.resourceValues(forKeys: [
        .contentModificationDateKey
      ])
      let built = values?.contentModificationDate?.formatted(.iso8601) ?? "?"
      return "\(version) (\(number)) built \(built)"
    }()
  }

  /// Asked after each block: how the version just used felt.
  private struct WheelLabRatingSheet: View {
    let variant: WheelLabVariant
    let done: (Int, Int) -> Void
    @State private var easy = 3
    @State private var control = 3

    var body: some View {
      NavigationStack {
        Form {
          Section("Easy to stop where you want") { scale($easy, id: "wheelLab.rate.stop") }
          Section("In control") { scale($control, id: "wheelLab.rate.control") }
          Section {
            Button("Save") { done(easy, control) }
              .accessibilityIdentifier("wheelLab.rate.save")
          } footer: {
            Text("1 = not at all, 5 = completely.")
          }
        }
        .navigationTitle(variant.title)
        .navigationBarTitleDisplayMode(.inline)
      }
      .presentationDetents([.medium])
    }

    private func scale(_ value: Binding<Int>, id: String) -> some View {
      Picker("Rating", selection: value) {
        ForEach(1...5, id: \.self) { Text("\($0)") }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityIdentifier(id)
    }
  }

  /// Medians and the slow tail per version and task kind, first use apart from later sessions, plus export.
  private struct WheelLabResults: View {
    @Binding var log: WheelLabLog
    let save: () -> Void
    @State private var files: [URL] = []
    @State private var clearing = false

    var body: some View {
      let summary = WheelLabSummary(log.trials)
      List {
        Section {
          LabeledContent("Trials", value: "\(log.trials.count)")
          LabeledContent("Sessions", value: "\(log.nextSession - 1)")
          LabeledContent("iPhone", value: AlarmWheelLab.device)
          LabeledContent("System", value: "iOS \(UIDevice.current.systemVersion)")
          LabeledContent("Build", value: AlarmWheelLab.build)
        }
        ForEach([false, true], id: \.self) { familiar in
          let rows = summary.rows.filter { $0.familiar == familiar }
          if !rows.isEmpty {
            Section(familiar ? "Later sessions" : "First session") {
              ForEach(rows) { row($0) }
            }
          }
        }
        if !log.ratings.isEmpty {
          Section("Ratings (mean, 1-5)") {
            ForEach(WheelLabVariant.allCases) { variant in
              let mine = log.ratings.filter { $0.variant == variant }
              if !mine.isEmpty {
                LabeledContent(
                  variant.title,
                  value:
                    "stop \(mean(mine.map(\.easyToStop))) · control \(mean(mine.map(\.inControl)))"
                )
              }
            }
          }
        }
        Section {
          ShareLink(items: files) {
            Label("Export CSV and JSON", systemImage: "square.and.arrow.up")
          }
          .disabled(files.isEmpty)
          .accessibilityIdentifier("wheelLab.export")
          Button("Clear Results…", role: .destructive) { clearing = true }
            .disabled(log.trials.isEmpty && log.ratings.isEmpty)
        } footer: {
          Text(
            "Time runs from the first touch to the right time set. Slow = the 90th percentile. Overshoots count landing past the target."
          )
        }
      }
      .navigationTitle("Results")
      .task(id: log) { files = export() }
      .confirmationDialog("Clear all wheel lab results?", isPresented: $clearing) {
        Button("Clear Results", role: .destructive) {
          log = WheelLabLog()
          save()
        }
      }
    }

    private func row(_ row: WheelLabSummary.Row) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(row.variant.title) · \(row.category?.rawValue ?? "all") · n=\(row.count)")
          .font(.subheadline.weight(.semibold))
        Text(
          "median \(seconds(row.medianTime)) · slow \(seconds(row.slowTime)) · wrong \(row.wrongConfirms) · over \(row.overshoots)"
        )
        Text(
          "touches \(String(format: "%.1f", row.medianTouches)) · inertia wait \(seconds(row.medianInertiaWait))"
        )
      }
      .font(.footnote.monospacedDigit())
    }

    private func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }

    private func mean(_ values: [Int]) -> String {
      String(format: "%.1f", Double(values.reduce(0, +)) / Double(max(values.count, 1)))
    }

    private func export() -> [URL] {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: "WheelLabExport", directoryHint: .isDirectory)
      let trials = directory.appending(path: "wheel-lab-trials.csv")
      let ratings = directory.appending(path: "wheel-lab-ratings.csv")
      let json = directory.appending(path: "wheel-lab-log.json")
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try log.trialsCSV.write(to: trials, atomically: true, encoding: .utf8)
        try log.ratingsCSV.write(to: ratings, atomically: true, encoding: .utf8)
        try log.save(to: json)
        return [trials, ratings, json]
      } catch {
        return []
      }
    }
  }
#endif
