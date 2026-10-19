import SwiftUI

/// Native rendering host without app storage, external services or production lifecycle.
@main
struct TestHostApp: App {
  var body: some Scene {
    WindowGroup { Color.clear }
  }
}
