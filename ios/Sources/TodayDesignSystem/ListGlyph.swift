#if os(iOS)
import SwiftUI

/// The colored circle with a white glyph that stands for a list (cards, rows, the editor preview).
package struct ListGlyph: View {
    let color: Color
    let symbol: String
    var size: CGFloat

    package init(color: Color, symbol: String, size: CGFloat = 30) {
        self.color = color
        self.symbol = symbol
        self.size = size
    }

    package var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}


#endif
