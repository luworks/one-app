#if os(iOS)
import SwiftUI
import TodayCore

/// Colors for event blocks: a tint of the calendar's color behind text in a darker (or, in dark mode, lighter) shade of it.
package enum EventTint {
    package static func fill(_ color: Color) -> Color {
        Color(UIColor { trait in
            UIColor(color).withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.32 : 0.20)
        })
    }

    package static func text(_ color: Color) -> Color {
        Color(UIColor { trait in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: trait).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return trait.userInterfaceStyle == .dark
                ? UIColor(hue: h, saturation: max(0, s * 0.55), brightness: min(1, b + 0.35), alpha: 1)
                : UIColor(hue: h, saturation: min(1, s * 1.05), brightness: b * 0.55, alpha: 1)
        })
    }
}

#endif
