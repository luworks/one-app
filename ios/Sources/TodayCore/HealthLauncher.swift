import Foundation

/// Opening Apple's Health app, the place for everything Today's Health sheet doesn't show. `x-apple-health://` is the
/// supported way in; there is no public per-metric deep link, so every "Open Health" button lands on Health's home.
public enum HealthLauncher {
  public static let url = URL(string: "x-apple-health://")!
  public static let failureMessage = "Couldn't open Health"
}
