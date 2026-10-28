import Foundation
import TodayCore

/// Deterministic weather used only by Mock and Workbench; it makes no location or network request.
public enum WeatherTestData {
  public static func snapshot(now: Date) -> WeatherSnapshot {
    WeatherSnapshot(
      location: "Current location", temperatureCelsius: 20, apparentTemperatureCelsius: 19,
      highCelsius: 23, lowCelsius: 12, condition: "Partly cloudy", symbol: "cloud.sun.fill",
      precipitationProbability: 20, updatedAt: now,
      hours: [
        WeatherSnapshot.Hour(
          date: now.addingTimeInterval(3600), temperatureCelsius: 21,
          symbol: "cloud.sun.fill", precipitationProbability: 10)
      ],
      attribution: WeatherAttribution(
        lightMark: nil, darkMark: nil,
        legalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!))
  }
}
