#if os(iOS)
  import SwiftUI

  /// The colored circle with a contrasting glyph that stands for a list (cards, rows, the editor preview).
  package struct ListGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    package let color: Color
    package let symbol: String
    package var size: CGFloat

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
            .foregroundStyle(symbolColor)
        }
        .accessibilityHidden(true)
    }

    private var symbolColor: Color {
      color.contrastForeground(for: colorScheme)
    }
  }

#endif
