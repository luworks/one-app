import Foundation
import XCTest

@testable import TodayCore

final class TodayButtonColorTests: XCTestCase {
  func testAbsentAndDamagedChoicesUseGreen() {
    for stored in [nil, "", "red", "#FFFFFF", "1234567", "GGGGGG"] {
      XCTAssertEqual(TodayButtonColor(stored: stored), .green)
    }
  }

  func testCustomAndPresetColorsSurviveDefaultsRelaunch() throws {
    let suite = "TodayButtonColorTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(
      TodayButtonColor(stored: defaults.string(forKey: TodayButtonColor.storageKey)), .green)
    for color in TodayButtonColor.presets.map(\.color) + [
      TodayButtonColor(rgb: 0x13ABEF), TodayButtonColor(rgb: 0), TodayButtonColor(rgb: 0xFFFFFF),
    ] {
      defaults.set(color.stored, forKey: TodayButtonColor.storageKey)
      let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
      XCTAssertEqual(
        TodayButtonColor(stored: reopened.string(forKey: TodayButtonColor.storageKey)), color)
    }
    XCTAssertEqual(TodayButtonColor(stored: "13abef").stored, "13ABEF")
  }
}
