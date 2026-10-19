import FeatureClock
import FeatureHealth
import SnapshotTesting
import SwiftUI
import TodayCore
import TodayDesignSystem
import UIKit
import XCTest

/// iOS-hosted tests of exported production views. No private replacement screens.
@MainActor
final class NativeSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_338_060) // 2026-10-18 15:41 UTC
    private let locale = Locale(identifier: "en_US_POSIX")
    private var oldTimeZone: TimeZone!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        // Preserve all image failures in one explicit recording/comparison batch.
        continueAfterFailure = true
        // HealthFormat and StopwatchState also consult process Locale.current.
        XCTAssertEqual(Locale.current.identifier, locale.identifier,
                       "Launch the snapshot host with -AppleLocale en_US_POSIX -AppleLanguages (en).")
        oldTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        suite = "TodaySnapshotTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        if let suite { defaults?.removePersistentDomain(forName: suite) }
        if let oldTimeZone { NSTimeZone.default = oldTimeZone }
        defaults = nil
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = locale
        value.firstWeekday = 1
        return value
    }

    private var series: HealthSeries {
        HealthSeries(points: (0..<35).map { day in
            HealthPoint(date: calendar.date(byAdding: .day, value: -day, to: now)!,
                        value: Double(4_000 + (day % 7) * 650))
        })
    }

    private var runtime: PlannerRuntime {
        PlannerRuntime(now: { [now] in now },
                       nextID: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
                       calendar: calendar, locale: locale)
    }

    private func health(_ series: HealthSeries) -> some View {
        HealthMetricDetail(metric: .steps, series: series, now: runtime.now(),
                           units: HealthUnits(poundsForWeight: false, milesForDistance: false),
                           calendar: runtime.calendar, locale: runtime.locale)
    }

    func testHealthStepsLight() {
        check(health(series), named: "steps-light")
    }

    func testHealthEmptyDarkLargeType() {
        check(health(HealthSeries(points: [])), named: "empty-dark-accessibility3",
              dark: true, largeType: true)
    }

    func testStopwatchStoppedAnalog() {
        let model = StopwatchModel(defaults: defaults, now: runtime.now,
                                   initialState: StopwatchState(startedAt: nil, accumulated: 21.55,
                                                                laps: [4.2, 6.5, 5.1]),
                                   initialPage: .analog)
        check(StopwatchView(model: model), named: "analog-stopped-laps")
    }

    func testStopwatchRunningDigitalDark() {
        let model = StopwatchModel(defaults: defaults, now: runtime.now,
                                   initialState: StopwatchState(startedAt: now.addingTimeInterval(-5.75),
                                                                accumulated: 0, laps: []),
                                   initialPage: .digital)
        check(StopwatchView(model: model), named: "digital-running-dark", dark: true)
    }

    func testNativePillSwitcherLargeType() {
        check(PillSwitcher(items: [7, 30, 90], selection: .constant(30),
                           title: { "\($0) Days" }, identifier: { "health.range.\($0)" }),
              named: "range-accessibility3", largeType: true)
    }

    /// Proves the real render/diff pipeline notices changed production data without writing baselines.
    func testHealthDataPerturbationChangesPixels() throws {
        let populated = try render(health(series))
        let repeated = try render(health(series))
        let empty = try render(health(HealthSeries(points: [])))
        let diffing = Snapshotting<UIImage, UIImage>.image(precision: 1, perceptualPrecision: 1).diffing
        XCTAssertNil(diffing.diffV2(populated, repeated), "Identical frozen inputs must render identically.")
        XCTAssertNotNil(diffing.diffV2(populated, empty), "Removing real Health samples must change the image.")
    }

    private var recording: SnapshotTestingConfiguration.Record {
        let env = ProcessInfo.processInfo.environment
        // Presence alone blocks recording, even CI=0 or CI=false.
        let hasCIKey = env.keys.contains { $0.uppercased() == "CI" || $0.uppercased().hasPrefix("CI_") }
        return !hasCIKey && env["TODAY_RECORD_SNAPSHOTS"] == "1" ? .all : .never
    }

    private func check<V: View>(_ view: V, named name: String, dark: Bool = false,
                                largeType: Bool = false, file: StaticString = #filePath,
                                testName: String = #function, line: UInt = #line) {
        do {
            let image = try render(view, dark: dark, largeType: largeType)
            assertSnapshot(of: image, as: .image(precision: 1, perceptualPrecision: 1),
                           named: name, record: recording, file: file, testName: testName, line: line)
        } catch {
            XCTFail("Native snapshot render failed: \(error)", file: file, line: line)
        }
    }

    private func render<V: View>(_ view: V, dark: Bool = false, largeType: Bool = false) throws -> UIImage {
        let size = CGSize(width: 393, height: 852)
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.preferredContentSizeCategory = largeType ? .accessibilityExtraLarge : .large
            traits.displayScale = 3
            traits.userInterfaceIdiom = .phone
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
        }
        let root = view
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large)
            .environment(\.layoutDirection, .leftToRight)
            .defaultAppStorage(defaults)
            .transaction { $0.disablesAnimations = true; $0.animation = nil }
        let controller = UIHostingController(rootView: root)
        // One containment tree for the entire render. The UIViewController snapshot strategy
        // creates another window; passing an already-mounted host to it reparents SwiftUI.
        let container = UIViewController()
        container.addChild(controller)
        container.view.addSubview(controller.view)
        container.setOverrideTraitCollection(traits, forChild: controller)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: container)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        window.layoutIfNeeded()
        // Normalize the host's safe area without replacing its real SwiftUI layout.
        let actualInsets = controller.view.safeAreaInsets
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59 - actualInsets.top,
                                                          left: -actualInsets.left,
                                                          bottom: 34 - actualInsets.bottom,
                                                          right: -actualInsets.right)
        window.layoutIfNeeded()
        // Mount before waiting: StopwatchView's real pager task waits 50 ms before its initial scroll.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drawn, "The mounted window hierarchy must render successfully.")
        XCTAssertEqual(image.size, size)
        XCTAssertEqual(image.scale, 3)
        return image
    }
}
