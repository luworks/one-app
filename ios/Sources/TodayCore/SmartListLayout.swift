import Foundation

/// Which smart lists show at the top of Reminders, and in what order. Changed in Settings (a switch per list;
/// press, hold and drag to reorder) or with Hide in a smart list's long-press menu.
/// Stored as comma-separated raw values so it fits in `@AppStorage`.
package struct SmartListLayout {
  package static let orderKey = "reminders.smartOrder"
  package static let hiddenKey = "reminders.smartHidden"

  package var order: [SmartList]
  package var hidden: Set<SmartList>

  package init(order raw: String, hidden rawHidden: String) {
    // Smart lists added in a later version show up at the end.
    order = PillOrder.decode(raw, all: SmartList.allCases)
    hidden = Set(rawHidden.split(separator: ",").compactMap { SmartList(rawValue: String($0)) })
  }

  package var visible: [SmartList] { order.filter { !hidden.contains($0) } }
  package var orderString: String { PillOrder.encode(order) }

  /// A pill was moved in the row of shown smart lists (a drag, or Move Left / Move Right). Hidden lists keep their
  /// places, so Settings shows the same order.
  package mutating func reorderVisible(_ newVisible: [SmartList]) {
    order = PillOrder.merge(visible: newVisible, into: order)
  }
  package var hiddenString: String { hidden.map(\.rawValue).sorted().joined(separator: ",") }
}
