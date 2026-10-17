import Foundation

/// Which chat messages offer a Copy button. The app's own status sentences ("Here's what I understood. Nothing is added
/// until you confirm.", "Updated…", "Added…", "OK, dropped it.") are templates: copying them is never useful.
/// Your own words, and answers that carry content (today's summary), can be copied.
/// Plain Swift (no SwiftUI) so it runs under `swift test`.
enum MessageCopy {
    /// An answer worth copying: the summary of today ("Today: 3 open tasks and 1 upcoming event." and its lines).
    /// A new kind of answer that carries content must be added here, or it is treated as a template.
    static func carriesContent(_ text: String) -> Bool {
        text.hasPrefix("Today:")
    }

    /// True for the app's own sentences. Every AI message is one unless it carries content.
    static func isTemplate(isUser: Bool, text: String) -> Bool {
        !isUser && !carriesContent(text)
    }
}
