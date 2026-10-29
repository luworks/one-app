#if os(iOS)
  import SwiftUI
  import TodayCore

  /// "Open Health": one tap into Apple's Health app, shared by every place Today shows Health. If iOS refuses the URL
  /// the label says so for a moment ("Couldn't open Health"); nothing else happens.
  public struct OpenHealthButton: View {
    @Environment(\.openURL) private var openURL
    @State private var failed = false

    public init() {}

    public var body: some View {
      Button {
        openURL(HealthLauncher.url) { accepted in
          guard !accepted else { return }
          failed = true
          AccessibilityNotification.Announcement(HealthLauncher.failureMessage).post()
          Task {
            try? await Task.sleep(for: .seconds(2.5))
            failed = false
          }
        }
      } label: {
        Label(
          failed ? HealthLauncher.failureMessage : "Open Health",
          systemImage: failed ? "exclamationmark.circle" : "heart.text.square"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(failed ? Color.secondary : HealthStyle.accent)
        .frame(minHeight: 44, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityHint("Opens Apple's Health app")
      .accessibilityIdentifier("health.open")
    }
  }
#endif
