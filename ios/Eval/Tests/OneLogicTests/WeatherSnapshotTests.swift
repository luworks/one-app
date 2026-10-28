import Foundation
import XCTest

@testable import TodayCore

final class WeatherSnapshotTests: XCTestCase {
  func testTemperaturesUseRegionalUnitsAndHandleFreezing() {
    XCTAssertEqual(WeatherFormat.temperature(0, locale: Locale(identifier: "en_US")), "32°")
    XCTAssertEqual(WeatherFormat.temperature(20, locale: Locale(identifier: "en_US")), "68°")
    XCTAssertEqual(WeatherFormat.temperature(-5, locale: Locale(identifier: "en_GB")), "-5°")
  }
}
