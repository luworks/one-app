import One
import TodayShell
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI
import SwiftData
#if TODAY_MOCK
import TodayTestSupport
#endif

@main
struct OneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let diagnostics = LocalDiagnostics()
    let healthModel: HealthModel
    let healthLineModel: HealthLineModel
    let container: ModelContainer

    init() {
        diagnostics.start()
        let source: any HealthSource
        #if TODAY_MOCK
        source = HealthTestSources.scripted(base: MockHealthSource(), arguments: ProcessInfo.processInfo.arguments)
        #else
        source = HealthKitSource()
        #endif
        healthModel = HealthModel(source: source)
        healthLineModel = HealthLineModel(source: source)
        if PerformanceTrace.enabled { PerformanceTrace.shared.beginLaunch() }
        #if TODAY_MOCK
        if PreviewFixtures.isAxe {
            container = PreviewFixtures.reminders
            return
        }
        #endif
        LaunchTimer.mark("app init")
        Appearance.applyLaunchOverride()
        Preferences.applyLaunchOverride()
        if PerformanceTrace.enabled { PerformanceTrace.shared.mark("store_start") }
        #if TODAY_MOCK
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { SampleData.resetFlags() }
        #endif
        container = OneStore.start()
        #if TODAY_MOCK
        HealthDebugSeed.runIfRequested()
        #endif
        if PerformanceTrace.enabled { PerformanceTrace.shared.mark("store_ready") }
        LaunchTimer.mark("store ready")
    }

    #if TODAY_MOCK
    private func prepareMockData(_ context: ModelContext) -> Bool {
        if let path = DevImport.requestedPath {
            do { _ = try DevImport.run(path: path, into: context); ListActions.ensureLists(in: context) }
            catch { print("IMPORT failed code: \((error as NSError).code)") }
            return false
        }
        if let path = TestDataset.requestedPath {
            do { try TestDataset.load(path: path, into: context) }
            catch { print("DATASET failed code: \((error as NSError).code)") }
        } else { SampleData.insertIfNeeded(context) }
        return true
    }
    #endif

    var body: some Scene {
        WindowGroup {
            #if TODAY_MOCK
            if PreviewFixtures.isAxe {
                Color.clear
            } else {
                HomeView(diagnostics: diagnostics, prepareData: prepareMockData).appearanceRoot().environment(healthModel).environment(healthLineModel)
            }
            #else
            HomeView(diagnostics: diagnostics).appearanceRoot().environment(healthModel).environment(healthLineModel)
            #endif
        }
        .modelContainer(container)
    }
}

