import Foundation

/// Production wall clock retained while callers migrate to explicit PlannerRuntime values.
public enum TodayClock {
  public static var now: Date { .now }
}
