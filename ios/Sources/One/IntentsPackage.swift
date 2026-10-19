#if os(iOS)
import AppIntents

/// Keeps identity-bound intents in One while declaring them to the executable's metadata collector.
public struct OneIntentsPackage: AppIntentsPackage {}
#endif
