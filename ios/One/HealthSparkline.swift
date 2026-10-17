import SwiftUI

/// The one accent Health uses (the heart on the Today line). System pink adapts to dark mode.
enum HealthStyle {
    static let accent = Color.pink
    /// The muted look of a missing day or an empty row.
    static let muted = Color(.tertiaryLabel)
}

/// A tiny sparkline of the last 7 days, drawn by hand (no chart per row). `values` come from `HealthSpark.normalised`:
/// 0…1, nil for a day without data. Bars for totals, dots joined by a thin line for readings. The latest day is solid
/// and the others softer; a missing day is a small muted dot, and with no data at all the row is seven muted dots.
struct HealthSparkline: View {
    let values: [Double?]
    let shape: HealthShape

    var body: some View {
        Canvas { context, size in
            let count = max(values.count, 1)
            let slot = size.width / CGFloat(count)
            let last = values.lastIndex { $0 != nil }
            let empty = last == nil

            func center(_ i: Int) -> CGFloat { slot * (CGFloat(i) + 0.5) }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }

            switch shape {
            case .bars:
                let barWidth = min(7, slot * 0.58)
                for (i, v) in values.enumerated() {
                    guard let v else { dot(center(i), size.height - 1.5, 1.5, HealthStyle.muted); continue }
                    let h = 3 + CGFloat(v) * (size.height - 3)
                    let rect = CGRect(x: center(i) - barWidth / 2, y: size.height - h, width: barWidth, height: h)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                                 with: .color(HealthStyle.accent.opacity(i == last ? 1 : 0.4)))
                }
            case .dots:
                func y(_ v: Double) -> CGFloat { 3 + CGFloat(1 - v) * (size.height - 6) }
                if empty {
                    for i in values.indices { dot(center(i), size.height / 2, 1.5, HealthStyle.muted) }
                    return
                }
                var line = Path()
                var open = false
                for (i, v) in values.enumerated() {
                    guard let v else { open = false; continue }
                    let p = CGPoint(x: center(i), y: y(v))
                    if open { line.addLine(to: p) } else { line.move(to: p) }
                    open = true
                }
                context.stroke(line, with: .color(HealthStyle.accent.opacity(0.35)), lineWidth: 1)
                for (i, v) in values.enumerated() {
                    guard let v else { dot(center(i), size.height - 1.5, 1.5, HealthStyle.muted); continue }
                    dot(center(i), y(v), i == last ? 3 : 2, HealthStyle.accent.opacity(i == last ? 1 : 0.6))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
