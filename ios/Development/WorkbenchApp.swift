#if DEBUG && TODAY_WORKBENCH
import SwiftUI
import TodayScenes

/// Separate executable: never opens OneStore, HomeView, AppDelegate or production lifecycle tasks.
@main
@MainActor
struct WorkbenchApp: App {
    private let launch: Result<SceneConfiguration, any Error>

    init() {
        launch = Result { try SceneRegistry.configuration(arguments: ProcessInfo.processInfo.arguments) }
    }

    var body: some Scene {
        WindowGroup { WorkbenchRoot(launch: launch) }
    }
}
#endif

#if DEBUG
import SwiftUI
import TodayScenes
import UIKit

@MainActor
struct WorkbenchRoot: View {
    let launch: Result<SceneConfiguration, any Error>
    @State private var selected: TodaySceneID
    @State private var scenario: SceneScenario
    @State private var appearance = "system"
    @State private var typeSize: DynamicTypeSize = .large
    @State private var locale: String
    @State private var result: Result<SceneSession, any Error>?
    @State private var controls = false
    @State private var started = false
    @State private var receiptWritten = false
    private let launchOptions: Result<WorkbenchLaunchOptions, any Error>
    private let receipt: UUID?
    private let requestedScene: String
    private let requestedScenario: String

    init(launch: Result<SceneConfiguration, any Error>) {
        self.launch = launch
        let arguments = ProcessInfo.processInfo.arguments
        let optionsResult = Result { try WorkbenchLaunchOptions(arguments: arguments) }
        launchOptions = optionsResult
        receipt = WorkbenchLaunchOptions.value("-sceneReceipt", in: arguments).flatMap(UUID.init(uuidString:))
        requestedScene = WorkbenchLaunchOptions.value("-scene", in: arguments) ?? "today"
        requestedScenario = WorkbenchLaunchOptions.value("-scenario", in: arguments) ?? "normal"
        if let options = try? optionsResult.get() {
            _appearance = State(initialValue: options.appearance)
            _typeSize = State(initialValue: options.typeSize)
        }
        let config = try? launch.get()
        _selected = State(initialValue: config?.scene ?? .today)
        _scenario = State(initialValue: config?.scenario ?? .normal)
        _locale = State(initialValue: config?.localeIdentifier ?? "en_US")
    }

    var body: some View {
        Group {
            if let result {
                switch result {
                case .success(let session):
                    SceneCatalog(session: session)
                        .id(session.identity)
                        .background(WorkbenchReceiptFrame { writeReceipt(status: "ready") })
                case .failure(let error): SceneFailure(error: error)
                }
            } else { ProgressView("Preparing scene") }
        }
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .dynamicTypeSize(typeSize)
        .safeAreaInset(edge: .bottom) {
            Button { controls = true } label: { Label("Scenes", systemImage: "square.grid.2x2") }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workbench.controls")
        }
        .sheet(isPresented: $controls) { settings }
        .onAppear {
            guard !started else { return }
            started = true
            do {
                _ = try launchOptions.get()
                _ = try launch.get()
                rebuild()
            } catch {
                result = .failure(error)
                writeReceipt(status: "failed")
            }
        }
        .onDisappear { dispose() }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Picker("Scene", selection: $selected) {
                    ForEach(SceneRegistry.all) { Text($0.title).tag($0.id) }
                }.accessibilityIdentifier("workbench.scene")
                Picker("Scenario", selection: $scenario) {
                    // Only genuine production states are offered; launch validation still rejects unsupported states.
                    ForEach(SceneScenario.allCases.filter { SceneRegistry.descriptor(for: selected).scenarios.contains($0) }, id: \.self) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("workbench.scenario")
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Dynamic Type", selection: $typeSize) {
                    ForEach(DynamicTypeSize.allCases, id: \.self) { Text(String(describing: $0)).tag($0) }
                }
                Picker("Locale", selection: $locale) {
                    Text("English (US)").tag("en_US")
                    Text("简体中文").tag("zh_CN")
                    Text("العربية").tag("ar_SA")
                    Text("Deutsch").tag("de_DE")
                }
                if let blocker = SceneRegistry.descriptor(for: selected).integrationBlocker {
                    Text(blocker).foregroundStyle(.secondary)
                }
            }
            .onChange(of: selected) { _, value in
                if !SceneRegistry.descriptor(for: value).scenarios.contains(scenario) { scenario = .normal }
            }
            .navigationTitle("Workbench")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { rebuild(); controls = false }
                        .accessibilityIdentifier("workbench.open")
                }
            }
        }
    }

    private func writeReceipt(status: String) {
        guard !receiptWritten, let receipt else { return }
        do {
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            let directory = caches.appendingPathComponent("TodayWorkbench", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: [
                "scene": requestedScene, "scenario": requestedScenario, "status": status,
            ], options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(receipt.uuidString + ".json"), options: .atomic)
            receiptWritten = true
        } catch {
            // No receipt means capture fails closed; never report a successful error screen.
            print("Workbench receipt write failed: \(error)")
        }
    }

    private func dispose() {
        if case .success(let session) = result { session.dispose() }
    }
    private func rebuild() {
        dispose()
        result = Result {
            let original = try? launch.get()
            let configuration = try SceneConfiguration(scene: selected, scenario: scenario,
                now: original?.now ?? Date(timeIntervalSince1970: 1_792_339_200),
                uuidSeed: original?.uuidSeed ?? 42,
                timeZoneIdentifier: original?.timeZoneIdentifier ?? "America/Los_Angeles", localeIdentifier: locale)
            return try SceneSession(configuration: configuration)
        }
        if case .failure = result { writeReceipt(status: "failed") }
    }
}

private struct WorkbenchLaunchOptions {
    let appearance: String
    let typeSize: DynamicTypeSize

    static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    init(arguments: [String]) throws {
        appearance = Self.value("-sceneAppearance", in: arguments) ?? "system"
        let sizes: [String: DynamicTypeSize] = [
            "xSmall": .xSmall, "small": .small, "medium": .medium, "large": .large,
            "xLarge": .xLarge, "xxLarge": .xxLarge, "xxxLarge": .xxxLarge,
            "accessibility1": .accessibility1, "accessibility2": .accessibility2,
            "accessibility3": .accessibility3, "accessibility4": .accessibility4,
            "accessibility5": .accessibility5,
        ]
        guard ["system", "light", "dark"].contains(appearance),
              let size = sizes[Self.value("-sceneTypeSize", in: arguments) ?? "large"] else {
            throw SceneConfigurationError.missingValue("valid scene appearance/type size")
        }
        typeSize = size
    }
}

/// Receipts follow a real SceneCatalog layout and the next display frame.
@MainActor
private struct WorkbenchReceiptFrame: UIViewRepresentable {
    let ready: () -> Void
    func makeUIView(context: Context) -> FrameView { FrameView(ready: ready) }
    func updateUIView(_ uiView: FrameView, context: Context) {}
    static func dismantleUIView(_ uiView: FrameView, coordinator: ()) { uiView.stop() }

    final class FrameView: UIView {
        private var ready: (() -> Void)?
        private var displayLink: CADisplayLink?
        private var frames = 0

        init(ready: @escaping () -> Void) {
            self.ready = ready
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { return nil }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, ready != nil, displayLink == nil, bounds.width > 0, bounds.height > 0 else { return }
            let link = CADisplayLink(target: self, selector: #selector(frameDisplayed))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
        @objc private func frameDisplayed() {
            guard window != nil else { stop(); return }
            frames += 1
            guard frames >= 2 else { return }
            let completion = ready
            ready = nil
            stop()
            completion?()
        }
        func stop() { displayLink?.invalidate(); displayLink = nil }
    }
}

/// Preview, launch and screenshot clients all use SceneSession + SceneCatalog.
@MainActor
private struct CatalogPreview: View {
    @State private var session: SceneSession?
    @State private var failure: (any Error)?
    var body: some View {
        Group {
            if let session { SceneCatalog(session: session).id(session.identity) }
            else if let failure { SceneFailure(error: failure) }
            else { ProgressView() }
        }
        .task {
            guard session == nil, failure == nil else { return }
            do { session = try SceneSession(configuration: SceneConfiguration(scene: .clockWorld)) }
            catch { failure = error }
        }
        .onDisappear { session?.dispose() }
    }
}

#Preview("Scene registry · World Clock") { CatalogPreview() }
#endif
