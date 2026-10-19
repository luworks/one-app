#if os(iOS)
import SwiftUI

/// The wide, closely stacked card surface shared by World Clock and My Lists.
/// Content and color belong to each screen; corners, inner padding and row gutters stay in one place.
@MainActor
public struct StackedCard<Fill: ShapeStyle, Content: View>: View {
    package let fill: Fill
    package let horizontalPadding: CGFloat
    package let flat: Bool
    private let content: Content

    public init(fill: Fill, horizontalPadding: CGFloat = 16, flat: Bool = false, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.horizontalPadding = horizontalPadding
        self.flat = flat
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(fill)
                    .opacity(flat ? 0 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .circular))
    }
}

extension View {
    /// Retains native List navigation, swipe actions and reordering around the shared card surface.
    @MainActor
    public func stackedCardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 15, bottom: 1, trailing: 15))
    }
}
#endif
