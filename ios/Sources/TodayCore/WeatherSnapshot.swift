import Foundation

/// Read-only weather for the location requested by the user. Temperatures are stored in Celsius.
public struct WeatherSnapshot: Equatable, Sendable {
  public struct Hour: Equatable, Sendable, Identifiable {
    public let date: Date
    public let temperatureCelsius: Double
    public let symbol: String
    public let precipitationProbability: Int?
    public var id: Date { date }

    public init(
      date: Date, temperatureCelsius: Double, symbol: String, precipitationProbability: Int?
    ) {
      self.date = date
      self.temperatureCelsius = temperatureCelsius
      self.symbol = symbol
      self.precipitationProbability = precipitationProbability
    }
  }

  public let location: String
  public let temperatureCelsius: Double
  public let apparentTemperatureCelsius: Double
  public let highCelsius: Double
  public let lowCelsius: Double
  public let condition: String
  public let symbol: String
  public let precipitationProbability: Int?
  public let updatedAt: Date
  public let hours: [Hour]
  public let attribution: WeatherAttribution

  public init(
    location: String, temperatureCelsius: Double, apparentTemperatureCelsius: Double,
    highCelsius: Double, lowCelsius: Double, condition: String, symbol: String,
    precipitationProbability: Int?, updatedAt: Date, hours: [Hour], attribution: WeatherAttribution
  ) {
    self.location = location
    self.temperatureCelsius = temperatureCelsius
    self.apparentTemperatureCelsius = apparentTemperatureCelsius
    self.highCelsius = highCelsius
    self.lowCelsius = lowCelsius
    self.condition = condition
    self.symbol = symbol
    self.precipitationProbability = precipitationProbability
    self.updatedAt = updatedAt
    self.hours = hours
    self.attribution = attribution
  }
}

/// Apple Weather's current marks and legal notice, supplied by WeatherKit.
public struct WeatherAttribution: Equatable, Sendable {
  public let lightMark: URL?
  public let darkMark: URL?
  public let legalURL: URL

  public init(lightMark: URL?, darkMark: URL?, legalURL: URL) {
    self.lightMark = lightMark
    self.darkMark = darkMark
    self.legalURL = legalURL
  }
}

public enum WeatherFormat {
  /// Follows the region's usual temperature unit; all weather calculations use Celsius.
  public static func temperature(_ celsius: Double, locale: Locale) -> String {
    let value = locale.measurementSystem == .us ? celsius * 9 / 5 + 32 : celsius
    return value.formatted(.number.precision(.fractionLength(0)).locale(locale)) + "°"
  }
}
