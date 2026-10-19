#if os(iOS)
import SwiftUI
import UIKit

/// The wheel picker of Apple's Timers screen: three wheels (hours 0-23, min 0-59, sec 0-59) with the unit written
/// inside the highlighted row next to the chosen number ("0 hours  7 min  0 sec"). A real `UIPickerView`, so the
/// highlight, the fade, the haptics and the light and dark looks are the system's. Numbers are right-aligned in each
/// wheel so the unit can sit just after them; the units are fixed labels laid over the highlighted row.
struct TimerWheel: UIViewRepresentable {
    @Binding var seconds: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TimerWheelView {
        let view = TimerWheelView()
        view.picker.dataSource = context.coordinator
        view.picker.delegate = context.coordinator
        view.picker.accessibilityIdentifier = "timer.wheel"
        view.show(seconds: seconds)
        return view
    }

    func updateUIView(_ view: TimerWheelView, context: Context) {
        context.coordinator.parent = self
        view.show(seconds: seconds)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, UIPickerViewAccessibilityDelegate {
        var parent: TimerWheel
        init(_ parent: TimerWheel) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            TimerWheelView.rowCounts[component]
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            TimerWheelView.componentWidth(in: pickerView.bounds.width)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? NumberLabel) ?? NumberLabel()
            label.text = "\(row)"
            label.rightInset = TimerWheelView.numberInset(width: TimerWheelView.componentWidth(in: pickerView.bounds.width))
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let rows = (0..<3).map { pickerView.selectedRow(inComponent: $0) }
            let value = rows[0] * 3600 + rows[1] * 60 + rows[2]  // up to 23:59:59; a start is capped at 23:59:00
            (pickerView.superview as? TimerWheelView)?.updateUnits(rows: rows)
            if value != parent.seconds { parent.seconds = value }
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            ["hours", "minutes", "seconds"][component]
        }
    }
}

/// A row's number: 22 pt, right-aligned with a fixed gap on the right (where the unit goes).
private final class NumberLabel: UILabel {
    var rightInset: CGFloat = 59 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 22, weight: .regular)
        textColor = .label
        textAlignment = .right
    }

    required init?(coder: NSCoder) { fatalError() }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: rightInset)))
    }
}

/// The picker with its three unit labels on top.
final class TimerWheelView: UIView {
    static let rowCounts = [24, 60, 60]
    /// Measured from Apple's screen (440 pt wide): three 110 pt wheels, number right edges 51 pt into each wheel,
    /// the unit starting 5 pt after the number.
    static let wheelWidth: CGFloat = 110
    static let numberRightEdge: CGFloat = 51
    static let unitGap: CGFloat = 5

    let picker = UIPickerView()
    private let units = (0..<3).map { _ in UILabel() }

    static func componentWidth(in width: CGFloat) -> CGFloat {
        width > 0 ? min(wheelWidth, width / 3.2) : wheelWidth
    }

    static func numberInset(width: CGFloat) -> CGFloat {
        width - width * numberRightEdge / wheelWidth
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(picker)
        for label in units {
            label.font = .systemFont(ofSize: 20, weight: .semibold)
            label.textColor = .label
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            addSubview(label)
        }
        updateUnits(rows: [0, 0, 0])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 216) }

    /// Moves the wheels to `seconds` (a recent loaded into the picker), only where they differ.
    func show(seconds: Int) {
        let s = max(seconds, 0)
        let rows = [min(s / 3600, 23), (s % 3600) / 60, s % 60]
        for c in 0..<3 where picker.selectedRow(inComponent: c) != rows[c] { picker.selectRow(rows[c], inComponent: c, animated: false) }
        updateUnits(rows: rows)
    }

    func updateUnits(rows: [Int]) {
        let names = [rows[0] == 1 ? "hour" : "hours", "min", "sec"]
        for (label, name) in zip(units, names) { label.text = name }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        let width = Self.componentWidth(in: bounds.width)
        let scale = width / Self.wheelWidth
        let left = (bounds.width - 3 * width) / 2
        for (c, label) in units.enumerated() {
            label.sizeToFit()
            let x = left + CGFloat(c) * width + Self.numberRightEdge * scale + Self.unitGap
            label.frame.origin = CGPoint(x: x, y: (bounds.height - label.bounds.height) / 2)
        }
    }
}
#endif
