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
        continueAfterFailure = false
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

    private func health(_ series: HealthSeries) -> some View {
        HealthMetricDetail(metric: .steps, series: series, now: now,
                           units: HealthUnits(poundsForWeight: false, milesForDistance: false),
                           calendar: calendar)
    }

    func testHealthStepsLight() {
        check(health(series), named: "steps-light")
    }

    func testHealthEmptyDarkLargeType() {
        check(health(HealthSeries(points: [])), named: "empty-dark-accessibility3",
              dark: true, largeType: true)
    }

    func testStopwatchStoppedAnalog() {
        StopwatchState(startedAt: nil, accumulated: 21.55, laps: [4.2, 6.5, 5.1]).save(to: defaults)
        let model = StopwatchModel(defaults: defaults, now: { [now] in now }, arguments: [])
        model.page = .analog
        check(StopwatchView(model: model), named: "analog-stopped-laps")
    }

    func testStopwatchRunningDigitalDark() {
        StopwatchState(startedAt: now.addingTimeInterval(-5.75), accumulated: 0, laps: []).save(to: defaults)
        let model = StopwatchModel(defaults: defaults, now: { [now] in now }, arguments: [])
        model.page = .digital
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
        return env["CI"] == nil && env["TODAY_RECORD_SNAPSHOTS"] == "1" ? .all : .never
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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        // Mount before waiting: StopwatchView's real pager task waits 50 ms before its initial scroll.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let config = ViewImageConfig(safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
                                     size: size, traits: traits)
        let strategy = Snapshotting<UIViewController, UIImage>.image(
            on: config, precision: 1, perceptualPrecision: 1, traits: traits)
        var result: UIImage?
        let captured = expectation(description: "Captured production SwiftUI view")
        strategy.snapshot(controller).run { image in result = image; captured.fulfill() }
        wait(for: [captured], timeout: 5)
        let image = try XCTUnwrap(result)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        return image
    }
}
