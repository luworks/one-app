import Foundation

/// Pure ordering logic for a row of pills that the user can rearrange (the Reminders smart lists and pinned lists).
/// No SwiftUI or SwiftData, so it runs under `swift test`.
public enum PillOrder {
    /// Moves the element at `from` so it ends up at index `to` of the result. Both indexes are clamped to the array,
    /// so a Move Right on the last pill (or a drop past the end) changes nothing.
    public static func move<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from) else { return items }
        var result = items
        let item = result.remove(at: from)
        result.insert(item, at: min(max(to, 0), result.count))
        return result
    }

    /// Moves `item` one place or more left (negative) or right (positive); clamps at both ends.
    public static func move<T: Equatable>(_ items: [T], _ item: T, by offset: Int) -> [T] {
        guard let from = items.firstIndex(of: item) else { return items }
        return move(items, from: from, to: from + offset)
    }

    /// A drop of `item` on `target`: it takes the target's place, so dragging right lands after the target and dragging
    /// left lands before it (and a drop on itself, or on something that isn't in the row, changes nothing).
    public static func move<T: Equatable>(_ items: [T], _ item: T, onto target: T) -> [T] {
        guard item != target, let from = items.firstIndex(of: item), let to = items.firstIndex(of: target) else { return items }
        return move(items, from: from, to: to)
    }

    /// `full` is a stored order that also holds entries that are not shown (hidden smart lists, lists that are not
    /// pinned). `visible` is the shown subset in its new order: it fills the slots the shown entries had, and the
    /// entries that are not shown keep their places.
    public static func merge<T: Hashable>(visible: [T], into full: [T]) -> [T] {
        let shown = Set(visible)
        var next = visible.makeIterator()
        return full.map { shown.contains($0) ? (next.next() ?? $0) : $0 }
    }

    /// The stored form: raw values joined with commas, so it fits in `@AppStorage`.
    public static func encode<T: RawRepresentable>(_ items: [T]) -> String where T.RawValue == String {
        items.map(\.rawValue).joined(separator: ",")
    }

    /// Reads a stored order: unknown values and repeats are dropped, and cases added in a later version go at the end.
    public static func decode<T: RawRepresentable & Hashable>(_ raw: String, all: [T]) -> [T] where T.RawValue == String {
        var seen = Set<T>()
        var result: [T] = []
        for item in raw.split(separator: ",").compactMap({ T(rawValue: String($0)) }) where seen.insert(item).inserted {
            result.append(item)
        }
        return result + all.filter { !seen.contains($0) }
    }
}
