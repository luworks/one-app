import Foundation

/// Optional nonnumeric Health capability. Existing HealthSource clients remain source compatible.
public protocol HealthRecordSource: Sendable {
  func requestRecordAccess(for families: [HealthRecordFamily]) async throws
  func records(for families: [HealthRecordFamily], days: Int, now: Date) async throws -> [HealthRecordFamily: [HealthRecord]]
}

public enum HealthRecordFamily: String, CaseIterable, Identifiable, Sendable {
  case categories, workouts, bloodPressure, characteristics
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .categories: "Health Events"
    case .workouts: "Workouts"
    case .bloodPressure: "Blood Pressure"
    case .characteristics: "Health Profile"
    }
  }
  public var summary: String {
    switch self {
    case .categories: "Recorded symptoms, reproductive health, sleep stages, heart notifications and other categorical Health events."
    case .workouts: "Recorded workout sessions, activity types and durations."
    case .bloodPressure: "Systolic and diastolic readings recorded together."
    case .characteristics: "Date of birth, biological sex, blood type, wheelchair use and skin type."
    }
  }
}

public struct HealthCategoryRecord: Equatable, Sendable {
  public let identifier: String
  public let title: String
  public let value: String
  public let start: Date
  public let end: Date
  public init(identifier: String, title: String, value: String, start: Date, end: Date) {
    self.identifier = identifier; self.title = title; self.value = value; self.start = start; self.end = end
  }
}
public struct HealthWorkoutRecord: Equatable, Sendable {
  public let activityCode: UInt
  public let title: String
  public let start: Date
  public let end: Date
  public let durationSeconds: Double
  public init(activityCode: UInt, title: String, start: Date, end: Date, durationSeconds: Double) {
    self.activityCode = activityCode; self.title = title; self.start = start; self.end = end
    self.durationSeconds = durationSeconds
  }
}
public struct HealthBloodPressureRecord: Equatable, Sendable {
  public let systolic: Double
  public let diastolic: Double
  public let date: Date
  public init(systolic: Double, diastolic: Double, date: Date) {
    self.systolic = systolic; self.diastolic = diastolic; self.date = date
  }
}
public struct HealthCharacteristicRecord: Equatable, Sendable {
  public let field: String
  public let value: String
  public init(field: String, value: String) { self.field = field; self.value = value }
}
public enum HealthRecord: Equatable, Sendable {
  case category(HealthCategoryRecord)
  case workout(HealthWorkoutRecord)
  case bloodPressure(HealthBloodPressureRecord)
  case characteristic(HealthCharacteristicRecord)
}

public enum HealthRecordError: Error, Equatable { case unavailable }
public enum HealthRecordLimits {
  /// Newest records per public type within the selected calendar window, explicitly disclosed by the record UI.
  public static let maximumRecordsPerType = 1_000
}
