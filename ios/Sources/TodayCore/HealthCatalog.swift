import Foundation

/// The bounded, read-only public numeric catalog. Identifiers are stable HealthKit identifiers; the platform
/// adapter validates runtime availability before constructing a type. Values never leave view state.
public enum HealthAggregation: Equatable, Sendable { case dailySum, dailyAverage, samples }

public enum HealthCanonicalUnit: Equatable, Sendable {
  case celsius, percent, kilograms, count, siemens, meters, kilocalories, minutes, metersPerSecond
  case perMinute, watts, effortScore, metabolicRate, decibels, milliseconds, oxygenUptake, centimeters
  case grams, milliliters, millimetersOfMercury, internationalUnits, liters, litersPerMinute, glucose
}

public struct HealthQuantityDescriptor: Sendable {
  public let identifier: String
  public let title: String
  public let group: HealthGroup
  public let unit: HealthCanonicalUnit
  public let label: String
  public let digits: Int
  public let aggregation: HealthAggregation
  public let scale: Double
  public let minimumIOS: Double

  public var summary: String {
    switch aggregation {
    case .dailySum: "Daily totals from Apple Health."
    case .dailyAverage: "Daily averages from Apple Health; availability depends on your devices and sources."
    case .samples: "Recorded readings from Apple Health."
    }
  }
}

public enum HealthCatalog {
  /// Maximum request range keeps 90-day comparisons and moving averages intact without an unbounded dump.
  public static let maximumHistoryDays = 180
  public static let maximumConcurrentQueries = 4
  public static let quantities: [HealthMetric: HealthQuantityDescriptor] = [
    .appleSleepingWristTemperature: .init(identifier: "HKQuantityTypeIdentifierAppleSleepingWristTemperature", title: "Sleeping Wrist Temperature", group: .recovery, unit: .celsius, label: "°C", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .bodyFat: .init(identifier: "HKQuantityTypeIdentifierBodyFatPercentage", title: "Body Fat Percentage", group: .body, unit: .percent, label: "%", digits: 1, aggregation: .samples, scale: 100, minimumIOS: 8.0),
    .weight: .init(identifier: "HKQuantityTypeIdentifierBodyMass", title: "Body Mass", group: .body, unit: .kilograms, label: "kg", digits: 1, aggregation: .samples, scale: 1, minimumIOS: 8.0),
    .bodyMassIndex: .init(identifier: "HKQuantityTypeIdentifierBodyMassIndex", title: "Body Mass Index", group: .body, unit: .count, label: "", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .electrodermalActivity: .init(identifier: "HKQuantityTypeIdentifierElectrodermalActivity", title: "Electrodermal Activity", group: .recovery, unit: .siemens, label: "µS", digits: 2, aggregation: .dailyAverage, scale: 1000000, minimumIOS: 8.0),
    .height: .init(identifier: "HKQuantityTypeIdentifierHeight", title: "Height", group: .body, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .leanBodyMass: .init(identifier: "HKQuantityTypeIdentifierLeanBodyMass", title: "Lean Body Mass", group: .body, unit: .kilograms, label: "kg", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .waistCircumference: .init(identifier: "HKQuantityTypeIdentifierWaistCircumference", title: "Waist Circumference", group: .body, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 11.0),
    .activeEnergy: .init(identifier: "HKQuantityTypeIdentifierActiveEnergyBurned", title: "Active Energy Burned", group: .activity, unit: .kilocalories, label: "kcal", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .exerciseMinutes: .init(identifier: "HKQuantityTypeIdentifierAppleExerciseTime", title: "Exercise Time", group: .activity, unit: .minutes, label: "min", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 9.3),
    .appleMoveTime: .init(identifier: "HKQuantityTypeIdentifierAppleMoveTime", title: "Move Time", group: .activity, unit: .minutes, label: "min", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 14.5),
    .appleStandTime: .init(identifier: "HKQuantityTypeIdentifierAppleStandTime", title: "Stand Time", group: .activity, unit: .minutes, label: "min", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 13.0),
    .basalEnergyBurned: .init(identifier: "HKQuantityTypeIdentifierBasalEnergyBurned", title: "Basal Energy Burned", group: .activity, unit: .kilocalories, label: "kcal", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .crossCountrySkiingSpeed: .init(identifier: "HKQuantityTypeIdentifierCrossCountrySkiingSpeed", title: "Cross Country Skiing Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .cyclingCadence: .init(identifier: "HKQuantityTypeIdentifierCyclingCadence", title: "Cycling Cadence", group: .activity, unit: .perMinute, label: "rpm", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 17.0),
    .cyclingFunctionalThresholdPower: .init(identifier: "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower", title: "Cycling Functional Threshold Power", group: .activity, unit: .watts, label: "W", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 17.0),
    .cyclingPower: .init(identifier: "HKQuantityTypeIdentifierCyclingPower", title: "Cycling Power", group: .activity, unit: .watts, label: "W", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 17.0),
    .cyclingSpeed: .init(identifier: "HKQuantityTypeIdentifierCyclingSpeed", title: "Cycling Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 17.0),
    .distanceCrossCountrySkiing: .init(identifier: "HKQuantityTypeIdentifierDistanceCrossCountrySkiing", title: "Distance Cross Country Skiing", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 18.0),
    .distanceCycling: .init(identifier: "HKQuantityTypeIdentifierDistanceCycling", title: "Distance Cycling", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .distanceDownhillSnowSports: .init(identifier: "HKQuantityTypeIdentifierDistanceDownhillSnowSports", title: "Distance Downhill Snow Sports", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 11.2),
    .distancePaddleSports: .init(identifier: "HKQuantityTypeIdentifierDistancePaddleSports", title: "Distance Paddle Sports", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 18.0),
    .distanceRowing: .init(identifier: "HKQuantityTypeIdentifierDistanceRowing", title: "Distance Rowing", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 18.0),
    .distanceSkatingSports: .init(identifier: "HKQuantityTypeIdentifierDistanceSkatingSports", title: "Distance Skating Sports", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 18.0),
    .distanceSwimming: .init(identifier: "HKQuantityTypeIdentifierDistanceSwimming", title: "Distance Swimming", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 10.0),
    .distance: .init(identifier: "HKQuantityTypeIdentifierDistanceWalkingRunning", title: "Distance Walking Running", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .distanceWheelchair: .init(identifier: "HKQuantityTypeIdentifierDistanceWheelchair", title: "Distance Wheelchair", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 10.0),
    .estimatedWorkoutEffortScore: .init(identifier: "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore", title: "Estimated Workout Effort Score", group: .activity, unit: .effortScore, label: "points", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .flightsClimbed: .init(identifier: "HKQuantityTypeIdentifierFlightsClimbed", title: "Flights Climbed", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .nikeFuel: .init(identifier: "HKQuantityTypeIdentifierNikeFuel", title: "Nike Fuel", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .paddleSportsSpeed: .init(identifier: "HKQuantityTypeIdentifierPaddleSportsSpeed", title: "Paddle Sports Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .physicalEffort: .init(identifier: "HKQuantityTypeIdentifierPhysicalEffort", title: "Physical Effort", group: .activity, unit: .metabolicRate, label: "kcal/kg/hr", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 17.0),
    .pushCount: .init(identifier: "HKQuantityTypeIdentifierPushCount", title: "Push Count", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 10.0),
    .rowingSpeed: .init(identifier: "HKQuantityTypeIdentifierRowingSpeed", title: "Rowing Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .runningPower: .init(identifier: "HKQuantityTypeIdentifierRunningPower", title: "Running Power", group: .activity, unit: .watts, label: "W", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .runningSpeed: .init(identifier: "HKQuantityTypeIdentifierRunningSpeed", title: "Running Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .steps: .init(identifier: "HKQuantityTypeIdentifierStepCount", title: "Step Count", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .swimmingStrokeCount: .init(identifier: "HKQuantityTypeIdentifierSwimmingStrokeCount", title: "Swimming Stroke Count", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 10.0),
    .underwaterDepth: .init(identifier: "HKQuantityTypeIdentifierUnderwaterDepth", title: "Underwater Depth", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .workoutEffortScore: .init(identifier: "HKQuantityTypeIdentifierWorkoutEffortScore", title: "Workout Effort Score", group: .activity, unit: .effortScore, label: "points", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .environmentalAudioExposure: .init(identifier: "HKQuantityTypeIdentifierEnvironmentalAudioExposure", title: "Environmental Audio Exposure", group: .recovery, unit: .decibels, label: "dB", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 13.0),
    .environmentalSoundReduction: .init(identifier: "HKQuantityTypeIdentifierEnvironmentalSoundReduction", title: "Environmental Sound Reduction", group: .recovery, unit: .decibels, label: "dB", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .headphoneAudioExposure: .init(identifier: "HKQuantityTypeIdentifierHeadphoneAudioExposure", title: "Headphone Audio Exposure", group: .recovery, unit: .decibels, label: "dB", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 13.0),
    .atrialFibrillationBurden: .init(identifier: "HKQuantityTypeIdentifierAtrialFibrillationBurden", title: "Atrial Fibrillation Burden", group: .recovery, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 16.0),
    .heartRate: .init(identifier: "HKQuantityTypeIdentifierHeartRate", title: "Heart Rate", group: .recovery, unit: .perMinute, label: "bpm", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .heartRateRecoveryOneMinute: .init(identifier: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", title: "Heart Rate Recovery One Minute", group: .recovery, unit: .perMinute, label: "bpm", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .heartRateVariabilityRMSSD: .init(identifier: "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD", title: "Heart Rate Variability (RMSSD)", group: .recovery, unit: .milliseconds, label: "ms", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 27.0),
    .heartRateVariabilitySDNN: .init(identifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", title: "Heart Rate Variability (SDNN)", group: .recovery, unit: .milliseconds, label: "ms", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 11.0),
    .peripheralPerfusionIndex: .init(identifier: "HKQuantityTypeIdentifierPeripheralPerfusionIndex", title: "Peripheral Perfusion Index", group: .recovery, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 8.0),
    .restingHeartRate: .init(identifier: "HKQuantityTypeIdentifierRestingHeartRate", title: "Resting Heart Rate", group: .recovery, unit: .perMinute, label: "/min", digits: 0, aggregation: .samples, scale: 1, minimumIOS: 11.0),
    .vO2Max: .init(identifier: "HKQuantityTypeIdentifierVO2Max", title: "VO2 Max", group: .recovery, unit: .oxygenUptake, label: "mL/kg/min", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 11.0),
    .walkingHeartRateAverage: .init(identifier: "HKQuantityTypeIdentifierWalkingHeartRateAverage", title: "Walking Heart Rate Average", group: .recovery, unit: .perMinute, label: "bpm", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 11.0),
    .appleWalkingSteadiness: .init(identifier: "HKQuantityTypeIdentifierAppleWalkingSteadiness", title: "Walking Steadiness", group: .activity, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 15.0),
    .runningGroundContactTime: .init(identifier: "HKQuantityTypeIdentifierRunningGroundContactTime", title: "Running Ground Contact Time", group: .activity, unit: .milliseconds, label: "ms", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .runningStrideLength: .init(identifier: "HKQuantityTypeIdentifierRunningStrideLength", title: "Running Stride Length", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .runningVerticalOscillation: .init(identifier: "HKQuantityTypeIdentifierRunningVerticalOscillation", title: "Running Vertical Oscillation", group: .activity, unit: .centimeters, label: "cm", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .sixMinuteWalkTestDistance: .init(identifier: "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", title: "Six Minute Walk Test Distance", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 14.0),
    .stairAscentSpeed: .init(identifier: "HKQuantityTypeIdentifierStairAscentSpeed", title: "Stair Ascent Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 14.0),
    .stairDescentSpeed: .init(identifier: "HKQuantityTypeIdentifierStairDescentSpeed", title: "Stair Descent Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 14.0),
    .walkingAsymmetryPercentage: .init(identifier: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage", title: "Walking Asymmetry Percentage", group: .activity, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 14.0),
    .walkingDoubleSupportPercentage: .init(identifier: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", title: "Walking Double Support Percentage", group: .activity, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 14.0),
    .walkingSpeed: .init(identifier: "HKQuantityTypeIdentifierWalkingSpeed", title: "Walking Speed", group: .activity, unit: .metersPerSecond, label: "m/s", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 14.0),
    .walkingStepLength: .init(identifier: "HKQuantityTypeIdentifierWalkingStepLength", title: "Walking Step Length", group: .activity, unit: .meters, label: "m", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 14.0),
    .dietaryBiotin: .init(identifier: "HKQuantityTypeIdentifierDietaryBiotin", title: "Biotin", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryCaffeine: .init(identifier: "HKQuantityTypeIdentifierDietaryCaffeine", title: "Caffeine", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryCalcium: .init(identifier: "HKQuantityTypeIdentifierDietaryCalcium", title: "Calcium", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryCarbohydrates: .init(identifier: "HKQuantityTypeIdentifierDietaryCarbohydrates", title: "Carbohydrates", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryChloride: .init(identifier: "HKQuantityTypeIdentifierDietaryChloride", title: "Chloride", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryCholesterol: .init(identifier: "HKQuantityTypeIdentifierDietaryCholesterol", title: "Cholesterol", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryChromium: .init(identifier: "HKQuantityTypeIdentifierDietaryChromium", title: "Chromium", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryCopper: .init(identifier: "HKQuantityTypeIdentifierDietaryCopper", title: "Copper", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryEnergyConsumed: .init(identifier: "HKQuantityTypeIdentifierDietaryEnergyConsumed", title: "Energy Consumed", group: .body, unit: .kilocalories, label: "kcal", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFatMonounsaturated: .init(identifier: "HKQuantityTypeIdentifierDietaryFatMonounsaturated", title: "Fat Monounsaturated", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFatPolyunsaturated: .init(identifier: "HKQuantityTypeIdentifierDietaryFatPolyunsaturated", title: "Fat Polyunsaturated", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFatSaturated: .init(identifier: "HKQuantityTypeIdentifierDietaryFatSaturated", title: "Fat Saturated", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFatTotal: .init(identifier: "HKQuantityTypeIdentifierDietaryFatTotal", title: "Fat Total", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFiber: .init(identifier: "HKQuantityTypeIdentifierDietaryFiber", title: "Fiber", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryFolate: .init(identifier: "HKQuantityTypeIdentifierDietaryFolate", title: "Folate", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryIodine: .init(identifier: "HKQuantityTypeIdentifierDietaryIodine", title: "Iodine", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryIron: .init(identifier: "HKQuantityTypeIdentifierDietaryIron", title: "Iron", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryMagnesium: .init(identifier: "HKQuantityTypeIdentifierDietaryMagnesium", title: "Magnesium", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryManganese: .init(identifier: "HKQuantityTypeIdentifierDietaryManganese", title: "Manganese", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryMolybdenum: .init(identifier: "HKQuantityTypeIdentifierDietaryMolybdenum", title: "Molybdenum", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryNiacin: .init(identifier: "HKQuantityTypeIdentifierDietaryNiacin", title: "Niacin", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryPantothenicAcid: .init(identifier: "HKQuantityTypeIdentifierDietaryPantothenicAcid", title: "Pantothenic Acid", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryPhosphorus: .init(identifier: "HKQuantityTypeIdentifierDietaryPhosphorus", title: "Phosphorus", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryPotassium: .init(identifier: "HKQuantityTypeIdentifierDietaryPotassium", title: "Potassium", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryProtein: .init(identifier: "HKQuantityTypeIdentifierDietaryProtein", title: "Protein", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryRiboflavin: .init(identifier: "HKQuantityTypeIdentifierDietaryRiboflavin", title: "Riboflavin", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietarySelenium: .init(identifier: "HKQuantityTypeIdentifierDietarySelenium", title: "Selenium", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietarySodium: .init(identifier: "HKQuantityTypeIdentifierDietarySodium", title: "Sodium", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietarySugar: .init(identifier: "HKQuantityTypeIdentifierDietarySugar", title: "Sugar", group: .body, unit: .grams, label: "g", digits: 2, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .dietaryThiamin: .init(identifier: "HKQuantityTypeIdentifierDietaryThiamin", title: "Thiamin", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryVitaminA: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminA", title: "Vitamin A", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryVitaminB12: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminB12", title: "Vitamin B12", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryVitaminB6: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminB6", title: "Vitamin B6", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryVitaminC: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminC", title: "Vitamin C", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryVitaminD: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminD", title: "Vitamin D", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryVitaminE: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminE", title: "Vitamin E", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .dietaryVitaminK: .init(identifier: "HKQuantityTypeIdentifierDietaryVitaminK", title: "Vitamin K", group: .body, unit: .grams, label: "µg", digits: 2, aggregation: .dailySum, scale: 1000000, minimumIOS: 8.0),
    .dietaryWater: .init(identifier: "HKQuantityTypeIdentifierDietaryWater", title: "Water", group: .body, unit: .milliliters, label: "mL", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 9.0),
    .dietaryZinc: .init(identifier: "HKQuantityTypeIdentifierDietaryZinc", title: "Zinc", group: .body, unit: .grams, label: "mg", digits: 2, aggregation: .dailySum, scale: 1000, minimumIOS: 8.0),
    .bloodAlcoholContent: .init(identifier: "HKQuantityTypeIdentifierBloodAlcoholContent", title: "Blood Alcohol Content", group: .body, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 8.0),
    .bloodPressureDiastolic: .init(identifier: "HKQuantityTypeIdentifierBloodPressureDiastolic", title: "Blood Pressure Diastolic", group: .body, unit: .millimetersOfMercury, label: "mmHg", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .bloodPressureSystolic: .init(identifier: "HKQuantityTypeIdentifierBloodPressureSystolic", title: "Blood Pressure Systolic", group: .body, unit: .millimetersOfMercury, label: "mmHg", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .insulinDelivery: .init(identifier: "HKQuantityTypeIdentifierInsulinDelivery", title: "Insulin Delivery", group: .body, unit: .internationalUnits, label: "IU", digits: 1, aggregation: .dailySum, scale: 1, minimumIOS: 11.0),
    .numberOfAlcoholicBeverages: .init(identifier: "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages", title: "Number Of Alcoholic Beverages", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 15.0),
    .numberOfTimesFallen: .init(identifier: "HKQuantityTypeIdentifierNumberOfTimesFallen", title: "Number Of Times Fallen", group: .activity, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .daylight: .init(identifier: "HKQuantityTypeIdentifierTimeInDaylight", title: "Time In Daylight", group: .activity, unit: .minutes, label: "min", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 17.0),
    .uVExposure: .init(identifier: "HKQuantityTypeIdentifierUVExposure", title: "UV Exposure", group: .activity, unit: .count, label: "", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 9.0),
    .waterTemperature: .init(identifier: "HKQuantityTypeIdentifierWaterTemperature", title: "Water Temperature", group: .recovery, unit: .celsius, label: "°C", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 16.0),
    .basalBodyTemperature: .init(identifier: "HKQuantityTypeIdentifierBasalBodyTemperature", title: "Basal Body Temperature", group: .body, unit: .celsius, label: "°C", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 9.0),
    .appleSleepingBreathingDisturbances: .init(identifier: "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances", title: "Sleeping Breathing Disturbances", group: .recovery, unit: .count, label: "", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 18.0),
    .forcedExpiratoryVolume1: .init(identifier: "HKQuantityTypeIdentifierForcedExpiratoryVolume1", title: "Forced Expiratory Volume1", group: .recovery, unit: .liters, label: "L", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .forcedVitalCapacity: .init(identifier: "HKQuantityTypeIdentifierForcedVitalCapacity", title: "Forced Vital Capacity", group: .recovery, unit: .liters, label: "L", digits: 2, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .inhalerUsage: .init(identifier: "HKQuantityTypeIdentifierInhalerUsage", title: "Inhaler Usage", group: .recovery, unit: .count, label: "", digits: 0, aggregation: .dailySum, scale: 1, minimumIOS: 8.0),
    .oxygenSaturation: .init(identifier: "HKQuantityTypeIdentifierOxygenSaturation", title: "Oxygen Saturation", group: .recovery, unit: .percent, label: "%", digits: 1, aggregation: .dailyAverage, scale: 100, minimumIOS: 8.0),
    .peakExpiratoryFlowRate: .init(identifier: "HKQuantityTypeIdentifierPeakExpiratoryFlowRate", title: "Peak Expiratory Flow Rate", group: .recovery, unit: .litersPerMinute, label: "L/min", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .respiratoryRate: .init(identifier: "HKQuantityTypeIdentifierRespiratoryRate", title: "Respiratory Rate", group: .recovery, unit: .perMinute, label: "breaths/min", digits: 0, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .bloodGlucose: .init(identifier: "HKQuantityTypeIdentifierBloodGlucose", title: "Blood Glucose", group: .body, unit: .glucose, label: "mg/dL", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
    .bodyTemperature: .init(identifier: "HKQuantityTypeIdentifierBodyTemperature", title: "Body Temperature", group: .body, unit: .celsius, label: "°C", digits: 1, aggregation: .dailyAverage, scale: 1, minimumIOS: 8.0),
  ]
}

public enum HealthDurationMath {
  /// Union overlaps before splitting at local calendar midnights. Duplicate sources never double the duration;
  /// calendar arithmetic preserves 23/25-hour DST days. Zero-length, reversed and future intervals add nothing.
  public static func dailyMinutes(
    _ intervals: [DateInterval], start: Date, end: Date, calendar: Calendar = .current
  ) -> [HealthPoint] {
    guard end > start else { return [] }
    let clipped = intervals.compactMap { interval -> DateInterval? in
      let lower = max(interval.start, start)
      let upper = min(interval.end, end)
      return upper > lower ? DateInterval(start: lower, end: upper) : nil
    }.sorted { $0.start < $1.start }
    var merged: [DateInterval] = []
    for interval in clipped {
      if let previous = merged.last, interval.start <= previous.end {
        merged[merged.count - 1] = DateInterval(start: previous.start, end: max(previous.end, interval.end))
      } else { merged.append(interval) }
    }
    var totals: [Date: Double] = [:]
    for interval in merged {
      var cursor = interval.start
      while cursor < interval.end {
        let day = calendar.startOfDay(for: cursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
        let upper = min(next, interval.end)
        totals[day, default: 0] += upper.timeIntervalSince(cursor) / 60
        cursor = upper
      }
    }
    return totals.map { HealthPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
  }
}
