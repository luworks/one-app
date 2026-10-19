#if os(iOS)
import SwiftUI

/// Small building blocks for the Settings rows added with `Preferences`, so every section looks the same:
/// a switch with its own one-line explanation, and a choice (pills for 2-4 options, a menu for more) with a label above.

/// A switch with a short explanation right under it (a Section footer can only describe the whole group).
@MainActor
public struct ExplainedToggle: View {
    let title: String
    @Binding var isOn: Bool
    var caption: String?

    public init(title: String, isOn: Binding<Bool>, caption: String? = nil) {
        self.title = title
        self._isOn = isOn
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 2-4 options as the shared pills, with the row's name above and an optional explanation below.
@MainActor
public struct PillChoiceRow<Item: Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    var caption: String?
    let label: (Item) -> String
    let identifier: (Item) -> String

    public init(title: String, items: [Item], selection: Binding<Item>, caption: String? = nil,
                label: @escaping (Item) -> String, identifier: @escaping (Item) -> String) {
        self.title = title
        self.items = items
        self._selection = selection
        self.caption = caption
        self.label = label
        self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            PillSwitcher(items: items, selection: $selection, distribution: .equal, title: label, identifier: identifier)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// A menu choice (more than four options) with an optional explanation below.
@MainActor
public struct MenuChoiceRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    var caption: String?
    var identifier: String
    @ViewBuilder var options: Options

    public init(title: String, selection: Binding<Value>, caption: String? = nil,
                identifier: String, @ViewBuilder options: () -> Options) {
        self.title = title
        self._selection = selection
        self.caption = caption
        self.identifier = identifier
        self.options = options()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: $selection) { options }
                .accessibilityIdentifier(identifier)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
