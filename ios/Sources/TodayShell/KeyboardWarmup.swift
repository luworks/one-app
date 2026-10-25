#if os(iOS)
  import UIKit
  import TodayPlatform

  /// The first keyboard a process shows loads the keyboard and input method, which makes the first Chat tap slower
  /// than later ones. Focusing and releasing an offscreen editor once, while the app is idle after launch, does that
  /// work early; nothing is shown because the field gives focus back in the same run loop turn.
  @MainActor
  enum KeyboardWarmup {
    /// Keyboard notifications posted during the warm-up are not a real keyboard.
    private(set) static var isRunning = false
    private static var done = false

    static func run() {
      guard !done,
        let window = UIApplication.shared.connectedScenes
          .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
      else { return }
      done = true
      if PerformanceTrace.enabled { PerformanceTrace.shared.mark("keyboard_warmup_begin") }
      // The same kind of editor and Return key as Chat's composer.
      let field = UITextView(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
      field.returnKeyType = .send
      field.isAccessibilityElement = false
      window.addSubview(field)
      isRunning = true
      field.becomeFirstResponder()
      field.resignFirstResponder()
      field.removeFromSuperview()
      // UIKit may post the keyboard notifications a little later.
      Task {
        try? await Task.sleep(for: .milliseconds(500))
        isRunning = false
      }
      if PerformanceTrace.enabled { PerformanceTrace.shared.mark("keyboard_warmup_end") }
    }
  }
#endif
