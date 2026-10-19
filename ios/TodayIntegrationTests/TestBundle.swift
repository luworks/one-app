#if !SWIFT_PACKAGE
import Foundation

private final class TestResourceAnchor: NSObject {}

extension Bundle {
    /// Same versioned fixtures as the SwiftPM tests, copied into the native test bundle.
    static var module: Bundle { Bundle(for: TestResourceAnchor.self) }
}
#endif
