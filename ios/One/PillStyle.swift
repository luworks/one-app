import SwiftUI

/// The one place that defines how a pill looks. The top tab pills (`TabPill`) and every secondary choice of
/// capsules (Week / Month / Year, Alarms / World Clock / ..., filters, scopes, ranges) read their size, font and
/// colors from here, so the two rows on the Calendar tab stay the reference and nothing drifts.
enum PillStyle {
    // MARK: Colors (all adaptive: black on white in light mode, white on black in dark mode)

    static let selectedFill = Color(.label)
    static let selectedText = Color(.systemBackground)
    static let unselectedFill = Color(.secondarySystemFill)
    static let unselectedText = Color.primary

    static func fill(selected: Bool) -> Color { selected ? selectedFill : unselectedFill }
    static func text(selected: Bool) -> Color { selected ? selectedText : unselectedText }

    // MARK: Layout

    /// Gap between neighbouring pills (both rows).
    static let spacing: CGFloat = 8
    /// Minimum height of a tappable pill; the visible capsule of a control pill may be shorter.
    static let tapHeight: CGFloat = 44

    /// Row 1: the tab pills. Selected = icon + label, others = icon only.
    enum Tab {
        static let font = Font.subheadline.weight(.semibold)
        static let iconLabelSpacing: CGFloat = 6
        static let selectedPadding: CGFloat = 16
        static let minWidth: CGFloat = 54
        static let height: CGFloat = 44
    }

    /// Row 2 and every other selector: a text pill, one size down from the tab pills.
    enum Control {
        static let font = Font.footnote.weight(.semibold)
        static let iconLabelSpacing: CGFloat = 5
        static let padding: CGFloat = 14
        /// The visible capsule; the hit area stays `tapHeight`.
        static let height: CGFloat = 34
    }

    /// The selection animation every pill row uses.
    static let selectionAnimation = Animation.snappy
}

/// One control pill: the visible look of Week / Month / Year. A label, optionally with a symbol.
/// Use it directly for a single on/off pill, or through `PillSwitcher` for a choice.
struct PillButton: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var identifier: String? = nil
    var fillsWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PillStyle.Control.iconLabelSpacing) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1).fixedSize()
            }
            .font(PillStyle.Control.font)
            .padding(.horizontal, PillStyle.Control.padding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: PillStyle.Control.height)
            .background(PillStyle.fill(selected: isSelected), in: Capsule())
            .foregroundStyle(PillStyle.text(selected: isSelected))
            .frame(minHeight: PillStyle.tapHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A single choice shown as pills: left-aligned with an equal gap, or spread to equal width, and it scrolls
/// sideways when the pills do not fit. Selecting animates and gives a selection tick.
struct PillSwitcher<Item: Hashable>: View {
    enum Distribution { case leading, equal }

    let items: [Item]
    @Binding var selection: Item
    var distribution: Distribution = .leading
    let title: (Item) -> String
    var icon: ((Item) -> String?)? = nil
    var identifier: ((Item) -> String)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(fixedWidth: true)
            ScrollView(.horizontal, showsIndicators: false) { row(fixedWidth: false) }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(fixedWidth: Bool) -> some View {
        HStack(spacing: PillStyle.spacing) {
            ForEach(items, id: \.self) { item in
                PillButton(title: title(item), icon: icon?(item), isSelected: item == selection,
                           identifier: identifier?(item), fillsWidth: fixedWidth && distribution == .equal) {
                    withAnimation(PillStyle.selectionAnimation) { selection = item }
                }
            }
            if fixedWidth && distribution == .leading { Spacer(minLength: 0) }
        }
    }
}
