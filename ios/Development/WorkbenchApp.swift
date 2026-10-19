#if DEBUG && TODAY_WORKBENCH
import SwiftUI
import TodayScenes

/// Separate executable: never opens OneStore, HomeView, AppDelegate or production lifecycle tasks.
@main
@MainActor
struct WorkbenchApp: App {
    private let launch: Result<SceneConfiguration, any Error>
    private let runtime: SceneCatalogRuntime

    init() {
        launch = Result { try SceneRegistry.configuration(arguments: ProcessInfo.processInfo.arguments) }
        // Fail closed until root provides prepare/makeServices/dispose for the real sandbox.
        runtime = .isolatedFeatures
    }

    var body: some Scene {
        WindowGroup { WorkbenchRoot(launch: launch, runtime: runtime) }
    }
}
#endif

#if DEBUG
import SwiftUI
import TodayScenes

@MainActor
struct WorkbenchRoot: View {
    let launch: Result<SceneConfiguration, any Error>
    let runtime: SceneCatalogRuntime
    @State private var selected: TodaySceneID
    @State private var scenario: SceneScenario
    @State private var appearance = "system"
    @State private var typeSize: DynamicTypeSize = .large
    @State private var locale: String
    @State private var result: Result<SceneSession, any Error>?
    @State private var controls = false
    @State private var started = false

    init(launch: Result<SceneConfiguration, any Error>, runtime: SceneCatalogRuntime = .isolatedFeatures) {
        self.launch = launch
        self.runtime = runtime
        let config = try? launch.get()
        _selected = State(initialValue: config?.scene ?? .today)
        _scenario = State(initialValue: config?.scenario ?? .normal)
        _locale = State(initialValue: config?.localeIdentifier ?? "en_US")
    }

    var body: some View {
        Group {
            if let result {
                switch result {
                case .success(let session): SceneCatalog(session: session).id(session.identity)
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
            switch launch {
            case .success: rebuild()
            case .failure(let error): result = .failure(error)
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
            return try SceneSession(configuration: configuration, runtime: runtime)
        }
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
