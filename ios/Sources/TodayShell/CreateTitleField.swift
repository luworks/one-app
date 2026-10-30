#if os(iOS)
  import SwiftUI
  import UIKit

  /// The composer's title. Like Apple Reminders, the words understood as a date or time are highlighted
  /// in place; tapping a highlight keeps those words as plain text. A SwiftUI TextField cannot colour
  /// ranges, so this wraps UITextView. Return calls `onReturn` instead of inserting a line break.
  struct CreateTitleField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: String
    var highlights: [NSRange]
    var enabled: Bool
    var onReturn: () -> Void
    var onTapHighlight: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
      let view = UITextView()
      view.delegate = context.coordinator
      view.isScrollEnabled = false
      view.backgroundColor = .clear
      view.textContainerInset = .zero
      view.textContainer.lineFragmentPadding = 0
      view.returnKeyType = .done
      view.font = Self.font
      view.adjustsFontForContentSizeCategory = true
      view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      view.accessibilityIdentifier = "create.title"
      let label = UILabel()
      label.font = Self.font
      label.adjustsFontForContentSizeCategory = true
      label.textColor = .placeholderText
      label.translatesAutoresizingMaskIntoConstraints = false
      label.isAccessibilityElement = false
      view.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        label.topAnchor.constraint(equalTo: view.topAnchor),
      ])
      context.coordinator.placeholder = label
      let tap = UITapGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
      tap.delegate = context.coordinator
      view.addGestureRecognizer(tap)
      return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
      context.coordinator.parent = self
      if view.text != text, view.markedTextRange == nil { view.text = text }
      view.accessibilityLabel = placeholder
      context.coordinator.placeholder?.text = placeholder
      context.coordinator.placeholder?.isHidden = !text.isEmpty
      context.coordinator.highlight(view)
      context.coordinator.enabled = enabled
      // Only a change requested by SwiftUI (appear, chips, Create) moves focus, once, after this update.
      // Focus changes made by the user are recorded by the delegate, so the two never fight.
      guard focused != context.coordinator.requestedFocus else { return }
      context.coordinator.requestedFocus = focused
      DispatchQueue.main.async {
        if focused, enabled, !view.isFirstResponder, view.window != nil {
          view.becomeFirstResponder()
        } else if !focused, view.isFirstResponder {
          view.resignFirstResponder()
        }
      }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize?
    {
      let width = proposal.width ?? 300
      let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
      return CGSize(width: width, height: max(size.height, Self.font.lineHeight))
    }

    static var font: UIFont {
      let base = UIFont.preferredFont(forTextStyle: .title3)
      return UIFontMetrics(forTextStyle: .title3).scaledFont(
        for: .systemFont(ofSize: base.pointSize, weight: .medium))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
      var parent: CreateTitleField
      weak var placeholder: UILabel?
      var requestedFocus = false
      var enabled = true
      init(_ parent: CreateTitleField) { self.parent = parent }

      func textViewDidChange(_ view: UITextView) {
        parent.text = view.text
        placeholder?.isHidden = !view.text.isEmpty
      }

      func textViewShouldBeginEditing(_ view: UITextView) -> Bool { enabled }

      func textViewDidBeginEditing(_ view: UITextView) {
        requestedFocus = true
        if !parent.focused { parent.focused = true }
      }

      func textViewDidEndEditing(_ view: UITextView) {
        requestedFocus = false
        if parent.focused { parent.focused = false }
      }

      func textView(
        _ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
      ) -> Bool {
        guard text == "\n" else { return true }
        // Act after the text system finishes this edit, not inside its callback.
        let onReturn = parent.onReturn
        DispatchQueue.main.async { onReturn() }
        return false
      }

      /// Colours only attributes, so the cursor and any in-progress (marked) input stay as they are.
      func highlight(_ view: UITextView) {
        guard view.markedTextRange == nil else { return }
        let storage = view.textStorage
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: all)
        storage.addAttribute(.foregroundColor, value: UIColor.label, range: all)
        storage.addAttribute(.font, value: CreateTitleField.font, range: all)
        for range in parent.highlights where NSMaxRange(range) <= storage.length {
          storage.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: range)
          storage.addAttribute(
            .backgroundColor, value: UIColor.systemGreen.withAlphaComponent(0.16), range: range)
        }
        storage.endEditing()
        view.typingAttributes = [.font: CreateTitleField.font, .foregroundColor: UIColor.label]
      }

      @objc func tapped(_ gesture: UITapGestureRecognizer) {
        // Only a tap on the highlighted glyphs themselves, so placing the cursor after them still works.
        guard let view = gesture.view as? UITextView else { return }
        let point = gesture.location(in: view)
        let hit = parent.highlights.contains { range in
          guard let start = view.position(from: view.beginningOfDocument, offset: range.location),
            let end = view.position(from: start, offset: range.length),
            let textRange = view.textRange(from: start, to: end)
          else { return false }
          return view.selectionRects(for: textRange).contains {
            $0.rect.insetBy(dx: 0, dy: -6).contains(point)
          }
        }
        if hit { parent.onTapHighlight() }
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
      ) -> Bool { true }
    }
  }
#endif
