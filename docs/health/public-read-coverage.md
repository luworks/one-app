# Public Health read coverage

This is an implementation inventory, not a promise that every field visible in Apple Health is accessible to Today. Health values remain transient local view state; only metric visibility/order is persisted. No HealthKit writes, uploads, new entitlements, clinical accounts, or signing changes are introduced.

## SDK and official sources

Checked 2026-10-19 against the installed iPhoneOS SDK `HealthKit.framework/Headers/HKTypeIdentifiers.h`, `HKCategoryValues.h`, `HKCharacteristicValues.h` and `HKUnit.h`. The SDK includes iOS 27 additions; runtime version guards omit unavailable types before authorization/query construction. SDK presence does not establish sensor, region, account or recorded-data availability.

Official references: [data types](https://developer.apple.com/documentation/healthkit/data-types), [statistics options](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions), [privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [read authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [sample limits](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor/limit), [route reading](https://developer.apple.com/documentation/healthkit/reading-route-data).

## Implemented families

- **121 public quantity types**: `HealthCatalog.quantities`, including activity/mobility, body measurements, heart/respiratory/hearing, nutrition, blood glucose, blood pressure quantities, temperature, effort and environmental data. Daily cumulative sums use HealthKit statistics rather than summing overlapping iPhone/Watch raw samples. Newly added discrete quantities use HealthKit daily averages (including its appropriate weighting for the type), explicitly described as daily averages. Original weight/resting-heart-rate/body-fat histories retain individual readings and sample-weighted moving averages. Percent quantities scale fractions to 0–100; electrodermal conductance displays µS; micronutrients use mg/µg; rates retain rate units. No medical interpretation or target ranges are added.
- **71 public category types**: `HealthCatalog.categories`, with explicit SDK category-code meanings. Includes symptoms, reproductive health, sleep stages, heart/hearing notifications, mindfulness, hygiene and walking steadiness. Displayed as dated text events/durations, never categorical codes on numeric charts. Unknown future values are skipped. Existing sleep night totals retain their dedicated stage/overlap logic; mindfulness totals union overlapping sessions and split at calendar midnights.
- **Workouts**: all public workout samples are readable as sessions with activity code, start/end and actual `duration` (rather than elapsed wall time). Common activity types have names; unfamiliar/new activities retain an explicit activity code instead of an invented name. Paused duration is therefore not accidentally counted as exercise. This is session history, not a workout-route/ECG renderer.
- **Correlations**: blood pressure preserves systolic/diastolic readings from the same correlation. Only exactly one finite, positive quantity of each kind is rendered. Independently recorded readings are never paired by a nearby timestamp. Nutrition quantities are independently supported; food correlation metadata/grouping is not rendered.
- **Characteristics**: all six public characteristic types: date of birth, biological sex, blood type, Fitzpatrick skin type, wheelchair use and activity move mode. Missing/not-set/unreadable values are omitted. Observable errors other than no-data/authorization-denied propagate through the optional records capability.

## Bounds and authorization

Numeric and record queries clamp to 1–180 calendar days; the existing 90-day previous-period comparison therefore keeps its full 180-day history. Numeric quantities use four scheduling slots; a per-source actor limiter also bounds actual underlying operations to four, including after a UI timeout. Record reads share the same limiter. Queued operations are cancellation-aware; native descriptor tasks receive cancellation after query timeouts. Cumulative and daily-average queries return at most 180 daily points. Original low-frequency raw readings and sleep/mindfulness category queries keep at most 20,000 newest samples per selected type/window. Records return at most 1,000 newest samples per type; the combined category event list retains the newest 1,000. These caps are intentional bounded previews, not a complete raw archive or export. Query descriptors are asynchronous and cooperative cancellation is checked before/after queries and batches. No unbounded Health dump or server transport exists.

Metric read permissions are requested only for user-selected metrics through the existing user action. Record families have a separate explicit action; the category family explanation identifies sensitive symptom/reproductive data before requesting those types. Characteristics and workouts are separate choices. Nothing expands authorization on launch or refresh. A successful permission request does not establish read approval. HealthKit intentionally makes read denial and no matching data indistinguishable; the UI must say no readable data, never infer that permission was denied from an empty result. `authorizationStatus(for:)` is not used to infer read authorization.

## Explicit boundaries

- Heartbeat series, raw quantity-series internals, ECG voltage traces and workout routes require dedicated data models, bounded series queries and renderers. They are not represented as generic numeric samples by this implementation. Route data is public to authorized apps but not requested here; it is not incorrectly described as intrinsically restricted.
- State of mind, audiograms, vision prescriptions, medication/dose records, documents/attachments, activity summaries and clinical FHIR records are distinct public families with specialized semantics and availability; no reader/renderer is added in this change. Clinical records may require additional capabilities and required-type declarations; no clinical/research entitlement is requested.
- HealthKit availability and simulator synthetic data do not prove physical-device recording, permissions or live read behavior. Real-device HealthKit authorization/coverage remains unverified until Yuan explicitly authorizes that test.

## Logic evidence

`HealthCatalogTests` covers unchanged persisted identifiers/defaults and extended selection round trips, cumulative nutrition versus discrete rate semantics, percentage/glucose/nutrient formatting, categorical code meaning/unknown values, overlapping session deduplication, clipping and DST midnight splitting. Existing Health tests retain 180-day comparisons, units and sample-weighted moving averages. Native adapter compilation and simulator UI checks are separate root-owned gates; mock records are not HealthKit evidence.

## Quantity inventory

| Metric ID | HealthKit identifier | Aggregation | Display unit | Minimum iOS |
| --- | --- | --- | --- | --- |
| `appleSleepingWristTemperature` | `HKQuantityTypeIdentifierAppleSleepingWristTemperature` | dailyAverage | °C | 16.0 |
| `bodyFat` | `HKQuantityTypeIdentifierBodyFatPercentage` | samples | % | 8.0 |
| `weight` | `HKQuantityTypeIdentifierBodyMass` | samples | kg | 8.0 |
| `bodyMassIndex` | `HKQuantityTypeIdentifierBodyMassIndex` | dailyAverage | count/index | 8.0 |
| `electrodermalActivity` | `HKQuantityTypeIdentifierElectrodermalActivity` | dailyAverage | µS | 8.0 |
| `height` | `HKQuantityTypeIdentifierHeight` | dailyAverage | m | 8.0 |
| `leanBodyMass` | `HKQuantityTypeIdentifierLeanBodyMass` | dailyAverage | kg | 8.0 |
| `waistCircumference` | `HKQuantityTypeIdentifierWaistCircumference` | dailyAverage | m | 11.0 |
| `activeEnergy` | `HKQuantityTypeIdentifierActiveEnergyBurned` | dailySum | kcal | 8.0 |
| `exerciseMinutes` | `HKQuantityTypeIdentifierAppleExerciseTime` | dailySum | min | 9.3 |
| `appleMoveTime` | `HKQuantityTypeIdentifierAppleMoveTime` | dailySum | min | 14.5 |
| `appleStandTime` | `HKQuantityTypeIdentifierAppleStandTime` | dailySum | min | 13.0 |
| `basalEnergyBurned` | `HKQuantityTypeIdentifierBasalEnergyBurned` | dailySum | kcal | 8.0 |
| `crossCountrySkiingSpeed` | `HKQuantityTypeIdentifierCrossCountrySkiingSpeed` | dailyAverage | m/s | 18.0 |
| `cyclingCadence` | `HKQuantityTypeIdentifierCyclingCadence` | dailyAverage | /min | 17.0 |
| `cyclingFunctionalThresholdPower` | `HKQuantityTypeIdentifierCyclingFunctionalThresholdPower` | dailyAverage | W | 17.0 |
| `cyclingPower` | `HKQuantityTypeIdentifierCyclingPower` | dailyAverage | W | 17.0 |
| `cyclingSpeed` | `HKQuantityTypeIdentifierCyclingSpeed` | dailyAverage | m/s | 17.0 |
| `distanceCrossCountrySkiing` | `HKQuantityTypeIdentifierDistanceCrossCountrySkiing` | dailySum | m | 18.0 |
| `distanceCycling` | `HKQuantityTypeIdentifierDistanceCycling` | dailySum | m | 8.0 |
| `distanceDownhillSnowSports` | `HKQuantityTypeIdentifierDistanceDownhillSnowSports` | dailySum | m | 11.2 |
| `distancePaddleSports` | `HKQuantityTypeIdentifierDistancePaddleSports` | dailySum | m | 18.0 |
| `distanceRowing` | `HKQuantityTypeIdentifierDistanceRowing` | dailySum | m | 18.0 |
| `distanceSkatingSports` | `HKQuantityTypeIdentifierDistanceSkatingSports` | dailySum | m | 18.0 |
| `distanceSwimming` | `HKQuantityTypeIdentifierDistanceSwimming` | dailySum | m | 10.0 |
| `distance` | `HKQuantityTypeIdentifierDistanceWalkingRunning` | dailySum | m | 8.0 |
| `distanceWheelchair` | `HKQuantityTypeIdentifierDistanceWheelchair` | dailySum | m | 10.0 |
| `estimatedWorkoutEffortScore` | `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore` | dailyAverage | points | 18.0 |
| `flightsClimbed` | `HKQuantityTypeIdentifierFlightsClimbed` | dailySum | count/index | 8.0 |
| `nikeFuel` | `HKQuantityTypeIdentifierNikeFuel` | dailySum | count/index | 8.0 |
| `paddleSportsSpeed` | `HKQuantityTypeIdentifierPaddleSportsSpeed` | dailyAverage | m/s | 18.0 |
| `physicalEffort` | `HKQuantityTypeIdentifierPhysicalEffort` | dailyAverage | kcal/kg/hr | 17.0 |
| `pushCount` | `HKQuantityTypeIdentifierPushCount` | dailySum | count/index | 10.0 |
| `rowingSpeed` | `HKQuantityTypeIdentifierRowingSpeed` | dailyAverage | m/s | 18.0 |
| `runningPower` | `HKQuantityTypeIdentifierRunningPower` | dailyAverage | W | 16.0 |
| `runningSpeed` | `HKQuantityTypeIdentifierRunningSpeed` | dailyAverage | m/s | 16.0 |
| `steps` | `HKQuantityTypeIdentifierStepCount` | dailySum | count/index | 8.0 |
| `swimmingStrokeCount` | `HKQuantityTypeIdentifierSwimmingStrokeCount` | dailySum | count/index | 10.0 |
| `underwaterDepth` | `HKQuantityTypeIdentifierUnderwaterDepth` | dailyAverage | m | 16.0 |
| `workoutEffortScore` | `HKQuantityTypeIdentifierWorkoutEffortScore` | dailyAverage | points | 18.0 |
| `environmentalAudioExposure` | `HKQuantityTypeIdentifierEnvironmentalAudioExposure` | dailyAverage | dB | 13.0 |
| `environmentalSoundReduction` | `HKQuantityTypeIdentifierEnvironmentalSoundReduction` | dailyAverage | dB | 16.0 |
| `headphoneAudioExposure` | `HKQuantityTypeIdentifierHeadphoneAudioExposure` | dailyAverage | dB | 13.0 |
| `atrialFibrillationBurden` | `HKQuantityTypeIdentifierAtrialFibrillationBurden` | dailyAverage | % | 16.0 |
| `heartRate` | `HKQuantityTypeIdentifierHeartRate` | dailyAverage | /min | 8.0 |
| `heartRateRecoveryOneMinute` | `HKQuantityTypeIdentifierHeartRateRecoveryOneMinute` | dailyAverage | /min | 16.0 |
| `heartRateVariabilityRMSSD` | `HKQuantityTypeIdentifierHeartRateVariabilityRMSSD` | dailyAverage | ms | 27.0 |
| `heartRateVariabilitySDNN` | `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | dailyAverage | ms | 11.0 |
| `peripheralPerfusionIndex` | `HKQuantityTypeIdentifierPeripheralPerfusionIndex` | dailyAverage | % | 8.0 |
| `restingHeartRate` | `HKQuantityTypeIdentifierRestingHeartRate` | samples | /min | 11.0 |
| `vO2Max` | `HKQuantityTypeIdentifierVO2Max` | dailyAverage | mL/kg/min | 11.0 |
| `walkingHeartRateAverage` | `HKQuantityTypeIdentifierWalkingHeartRateAverage` | dailyAverage | /min | 11.0 |
| `appleWalkingSteadiness` | `HKQuantityTypeIdentifierAppleWalkingSteadiness` | dailyAverage | % | 15.0 |
| `runningGroundContactTime` | `HKQuantityTypeIdentifierRunningGroundContactTime` | dailyAverage | ms | 16.0 |
| `runningStrideLength` | `HKQuantityTypeIdentifierRunningStrideLength` | dailyAverage | m | 16.0 |
| `runningVerticalOscillation` | `HKQuantityTypeIdentifierRunningVerticalOscillation` | dailyAverage | cm | 16.0 |
| `sixMinuteWalkTestDistance` | `HKQuantityTypeIdentifierSixMinuteWalkTestDistance` | dailyAverage | m | 14.0 |
| `stairAscentSpeed` | `HKQuantityTypeIdentifierStairAscentSpeed` | dailyAverage | m/s | 14.0 |
| `stairDescentSpeed` | `HKQuantityTypeIdentifierStairDescentSpeed` | dailyAverage | m/s | 14.0 |
| `walkingAsymmetryPercentage` | `HKQuantityTypeIdentifierWalkingAsymmetryPercentage` | dailyAverage | % | 14.0 |
| `walkingDoubleSupportPercentage` | `HKQuantityTypeIdentifierWalkingDoubleSupportPercentage` | dailyAverage | % | 14.0 |
| `walkingSpeed` | `HKQuantityTypeIdentifierWalkingSpeed` | dailyAverage | m/s | 14.0 |
| `walkingStepLength` | `HKQuantityTypeIdentifierWalkingStepLength` | dailyAverage | m | 14.0 |
| `dietaryBiotin` | `HKQuantityTypeIdentifierDietaryBiotin` | dailySum | µg | 8.0 |
| `dietaryCaffeine` | `HKQuantityTypeIdentifierDietaryCaffeine` | dailySum | mg | 8.0 |
| `dietaryCalcium` | `HKQuantityTypeIdentifierDietaryCalcium` | dailySum | mg | 8.0 |
| `dietaryCarbohydrates` | `HKQuantityTypeIdentifierDietaryCarbohydrates` | dailySum | g | 8.0 |
| `dietaryChloride` | `HKQuantityTypeIdentifierDietaryChloride` | dailySum | mg | 8.0 |
| `dietaryCholesterol` | `HKQuantityTypeIdentifierDietaryCholesterol` | dailySum | mg | 8.0 |
| `dietaryChromium` | `HKQuantityTypeIdentifierDietaryChromium` | dailySum | µg | 8.0 |
| `dietaryCopper` | `HKQuantityTypeIdentifierDietaryCopper` | dailySum | mg | 8.0 |
| `dietaryEnergyConsumed` | `HKQuantityTypeIdentifierDietaryEnergyConsumed` | dailySum | kcal | 8.0 |
| `dietaryFatMonounsaturated` | `HKQuantityTypeIdentifierDietaryFatMonounsaturated` | dailySum | g | 8.0 |
| `dietaryFatPolyunsaturated` | `HKQuantityTypeIdentifierDietaryFatPolyunsaturated` | dailySum | g | 8.0 |
| `dietaryFatSaturated` | `HKQuantityTypeIdentifierDietaryFatSaturated` | dailySum | g | 8.0 |
| `dietaryFatTotal` | `HKQuantityTypeIdentifierDietaryFatTotal` | dailySum | g | 8.0 |
| `dietaryFiber` | `HKQuantityTypeIdentifierDietaryFiber` | dailySum | g | 8.0 |
| `dietaryFolate` | `HKQuantityTypeIdentifierDietaryFolate` | dailySum | µg | 8.0 |
| `dietaryIodine` | `HKQuantityTypeIdentifierDietaryIodine` | dailySum | µg | 8.0 |
| `dietaryIron` | `HKQuantityTypeIdentifierDietaryIron` | dailySum | mg | 8.0 |
| `dietaryMagnesium` | `HKQuantityTypeIdentifierDietaryMagnesium` | dailySum | mg | 8.0 |
| `dietaryManganese` | `HKQuantityTypeIdentifierDietaryManganese` | dailySum | mg | 8.0 |
| `dietaryMolybdenum` | `HKQuantityTypeIdentifierDietaryMolybdenum` | dailySum | µg | 8.0 |
| `dietaryNiacin` | `HKQuantityTypeIdentifierDietaryNiacin` | dailySum | mg | 8.0 |
| `dietaryPantothenicAcid` | `HKQuantityTypeIdentifierDietaryPantothenicAcid` | dailySum | mg | 8.0 |
| `dietaryPhosphorus` | `HKQuantityTypeIdentifierDietaryPhosphorus` | dailySum | mg | 8.0 |
| `dietaryPotassium` | `HKQuantityTypeIdentifierDietaryPotassium` | dailySum | mg | 8.0 |
| `dietaryProtein` | `HKQuantityTypeIdentifierDietaryProtein` | dailySum | g | 8.0 |
| `dietaryRiboflavin` | `HKQuantityTypeIdentifierDietaryRiboflavin` | dailySum | mg | 8.0 |
| `dietarySelenium` | `HKQuantityTypeIdentifierDietarySelenium` | dailySum | µg | 8.0 |
| `dietarySodium` | `HKQuantityTypeIdentifierDietarySodium` | dailySum | mg | 8.0 |
| `dietarySugar` | `HKQuantityTypeIdentifierDietarySugar` | dailySum | g | 8.0 |
| `dietaryThiamin` | `HKQuantityTypeIdentifierDietaryThiamin` | dailySum | mg | 8.0 |
| `dietaryVitaminA` | `HKQuantityTypeIdentifierDietaryVitaminA` | dailySum | µg | 8.0 |
| `dietaryVitaminB12` | `HKQuantityTypeIdentifierDietaryVitaminB12` | dailySum | µg | 8.0 |
| `dietaryVitaminB6` | `HKQuantityTypeIdentifierDietaryVitaminB6` | dailySum | mg | 8.0 |
| `dietaryVitaminC` | `HKQuantityTypeIdentifierDietaryVitaminC` | dailySum | mg | 8.0 |
| `dietaryVitaminD` | `HKQuantityTypeIdentifierDietaryVitaminD` | dailySum | µg | 8.0 |
| `dietaryVitaminE` | `HKQuantityTypeIdentifierDietaryVitaminE` | dailySum | mg | 8.0 |
| `dietaryVitaminK` | `HKQuantityTypeIdentifierDietaryVitaminK` | dailySum | µg | 8.0 |
| `dietaryWater` | `HKQuantityTypeIdentifierDietaryWater` | dailySum | mL | 9.0 |
| `dietaryZinc` | `HKQuantityTypeIdentifierDietaryZinc` | dailySum | mg | 8.0 |
| `bloodAlcoholContent` | `HKQuantityTypeIdentifierBloodAlcoholContent` | dailyAverage | % | 8.0 |
| `bloodPressureDiastolic` | `HKQuantityTypeIdentifierBloodPressureDiastolic` | dailyAverage | mmHg | 8.0 |
| `bloodPressureSystolic` | `HKQuantityTypeIdentifierBloodPressureSystolic` | dailyAverage | mmHg | 8.0 |
| `insulinDelivery` | `HKQuantityTypeIdentifierInsulinDelivery` | dailySum | IU | 11.0 |
| `numberOfAlcoholicBeverages` | `HKQuantityTypeIdentifierNumberOfAlcoholicBeverages` | dailySum | count/index | 15.0 |
| `numberOfTimesFallen` | `HKQuantityTypeIdentifierNumberOfTimesFallen` | dailySum | count/index | 8.0 |
| `daylight` | `HKQuantityTypeIdentifierTimeInDaylight` | dailySum | min | 17.0 |
| `uVExposure` | `HKQuantityTypeIdentifierUVExposure` | dailyAverage | count/index | 9.0 |
| `waterTemperature` | `HKQuantityTypeIdentifierWaterTemperature` | dailyAverage | °C | 16.0 |
| `basalBodyTemperature` | `HKQuantityTypeIdentifierBasalBodyTemperature` | dailyAverage | °C | 9.0 |
| `appleSleepingBreathingDisturbances` | `HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances` | dailyAverage | count/index | 18.0 |
| `forcedExpiratoryVolume1` | `HKQuantityTypeIdentifierForcedExpiratoryVolume1` | dailyAverage | L | 8.0 |
| `forcedVitalCapacity` | `HKQuantityTypeIdentifierForcedVitalCapacity` | dailyAverage | L | 8.0 |
| `inhalerUsage` | `HKQuantityTypeIdentifierInhalerUsage` | dailySum | count/index | 8.0 |
| `oxygenSaturation` | `HKQuantityTypeIdentifierOxygenSaturation` | dailyAverage | % | 8.0 |
| `peakExpiratoryFlowRate` | `HKQuantityTypeIdentifierPeakExpiratoryFlowRate` | dailyAverage | L/min | 8.0 |
| `respiratoryRate` | `HKQuantityTypeIdentifierRespiratoryRate` | dailyAverage | /min | 8.0 |
| `bloodGlucose` | `HKQuantityTypeIdentifierBloodGlucose` | dailyAverage | mg/dL | 8.0 |
| `bodyTemperature` | `HKQuantityTypeIdentifierBodyTemperature` | dailyAverage | °C | 8.0 |

## Category inventory

| HealthKit identifier | Minimum iOS | Value interpretation |
| --- | --- | --- |
| `HKCategoryTypeIdentifierAppleStandHour` | 9.0 | 0: "Stood", 1: "Idle" |
| `HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent` | 14.0 | 1: "Momentary Limit" |
| `HKCategoryTypeIdentifierHeadphoneAudioExposureEvent` | 14.2 | 1: "Seven Day Limit" |
| `HKCategoryTypeIdentifierHighHeartRateEvent` | 12.2 | 0: "Recorded" |
| `HKCategoryTypeIdentifierHypertensionEvent` | 26.2 | 0: "Recorded" |
| `HKCategoryTypeIdentifierIrregularHeartRhythmEvent` | 12.2 | 0: "Recorded" |
| `HKCategoryTypeIdentifierLowCardioFitnessEvent` | 14.3 | 1: "Low Fitness" |
| `HKCategoryTypeIdentifierLowHeartRateEvent` | 12.2 | 0: "Recorded" |
| `HKCategoryTypeIdentifierMindfulSession` | 10.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierAppleWalkingSteadinessEvent` | 15.0 | 1: "Initial Low", 2: "Initial Very Low", 3: "Repeat Low", 4: "Repeat Very Low" |
| `HKCategoryTypeIdentifierHandwashingEvent` | 14.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierToothbrushingEvent` | 13.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierBleedingAfterMenopause` | 27.0 | 1: "Unspecified", 2: "Light", 3: "Medium", 4: "Heavy", 5: "None" |
| `HKCategoryTypeIdentifierBleedingAfterPregnancy` | 18.0 | 1: "Unspecified", 2: "Light", 3: "Medium", 4: "Heavy", 5: "None" |
| `HKCategoryTypeIdentifierBleedingDuringPregnancy` | 18.0 | 1: "Unspecified", 2: "Light", 3: "Medium", 4: "Heavy", 5: "None" |
| `HKCategoryTypeIdentifierCervicalMucusQuality` | 9.0 | 1: "Dry", 2: "Sticky", 3: "Creamy", 4: "Watery", 5: "Egg White" |
| `HKCategoryTypeIdentifierContraceptive` | 14.3 | 1: "Unspecified", 2: "Implant", 3: "Injection", 4: "Intrauterine Device", 5: "Intravaginal Ring", 6: "Oral", 7: "Patch" |
| `HKCategoryTypeIdentifierInfrequentMenstrualCycles` | 16.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierIntermenstrualBleeding` | 9.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierIrregularMenstrualCycles` | 16.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierLactation` | 14.3 | 0: "Recorded" |
| `HKCategoryTypeIdentifierMenopausalState` | 27.0 | 1: "Menopause", 2: "Perimenopause", 3: "None" |
| `HKCategoryTypeIdentifierMenstrualFlow` | 9.0 | 1: "Unspecified", 2: "Light", 3: "Medium", 4: "Heavy", 5: "None" |
| `HKCategoryTypeIdentifierOvulationTestResult` | 9.0 | 1: "Negative", 2: "Luteinizing Hormone Surge", 3: "Indeterminate", 4: "Estrogen Surge" |
| `HKCategoryTypeIdentifierPersistentIntermenstrualBleeding` | 16.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierPregnancy` | 14.3 | 0: "Recorded" |
| `HKCategoryTypeIdentifierPregnancyTestResult` | 15.0 | 1: "Negative", 2: "Positive", 3: "Indeterminate" |
| `HKCategoryTypeIdentifierProgesteroneTestResult` | 15.0 | 1: "Negative", 2: "Positive", 3: "Indeterminate" |
| `HKCategoryTypeIdentifierProlongedMenstrualPeriods` | 16.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierSexualActivity` | 9.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierSleepApneaEvent` | 18.0 | 0: "Recorded" |
| `HKCategoryTypeIdentifierSleepAnalysis` | 8.0 | 0: "In Bed", 1: "Asleep Unspecified", 2: "Awake", 3: "Asleep Core", 4: "Asleep Deep", 5: "Asleep REM" |
| `HKCategoryTypeIdentifierAbdominalCramps` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierAcne` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierAppetiteChanges` | 13.6 | 0: "Unspecified", 1: "No Change", 2: "Decreased", 3: "Increased" |
| `HKCategoryTypeIdentifierBladderIncontinence` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierBloating` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierBreastPain` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierChestTightnessOrPain` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierChills` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierConstipation` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierCoughing` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierDiarrhea` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierDizziness` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierDrySkin` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierFainting` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierFatigue` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierFever` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierGeneralizedBodyAche` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierHairLoss` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierHeadache` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierHeartburn` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierHotFlashes` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierLossOfSmell` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierLossOfTaste` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierLowerBackPain` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierMemoryLapse` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierMoodChanges` | 13.6 | 0: "Present", 1: "Not Present" |
| `HKCategoryTypeIdentifierNausea` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierNightSweats` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierPelvicPain` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierRunnyNose` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierShortnessOfBreath` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierSinusCongestion` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierSkippedHeartbeat` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierSleepChanges` | 13.6 | 0: "Present", 1: "Not Present" |
| `HKCategoryTypeIdentifierSoreThroat` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierVaginalDryness` | 14.0 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierVomiting` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
| `HKCategoryTypeIdentifierWheezing` | 13.6 | 0: "Unspecified", 1: "Not Present", 2: "Mild", 3: "Moderate", 4: "Severe" |
