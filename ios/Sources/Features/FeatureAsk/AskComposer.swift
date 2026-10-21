#if os(iOS)
  import SwiftUI
  import UIKit
  import TodayPlatform

  /// A native multiline editor whose input events, not text contents, own keyboard submission.
  struct AskComposer: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var isPresented = true
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Editor {
      let view = Editor()
      view.delegate = context.coordinator
      view.pasteDelegate = context.coordinator
      view.font = .preferredFont(forTextStyle: .body)
      view.adjustsFontForContentSizeCategory = true
      view.backgroundColor = .clear
      view.textColor = .label
      view.textContainerInset = .zero
      view.textContainer.lineFragmentPadding = 0
      view.returnKeyType = .send
      view.accessibilityLabel = "Ask AI or add anything"
      view.accessibilityIdentifier = "ask-input"
      view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return view
    }

    func updateUIView(_ view: Editor, context: Context) {
      context.coordinator.parent = self
      if PerformanceTrace.enabled, view.tracedPresentation != isPresented {
        view.tracedPresentation = isPresented
        PerformanceTrace.shared.mark(isPresented ? "chat.native_shown" : "chat.native_hidden")
      }
      view.isHidden = !isPresented
      view.isUserInteractionEnabled = isPresented
      view.isAccessibilityElement = isPresented
      view.accessibilityElementsHidden = !isPresented
      // SwiftUI redraws must never replace an in-progress IME composition.
      if view.markedTextRange == nil, view.text != text { view.text = text }
      if focused, !view.isFirstResponder {
        if PerformanceTrace.enabled { PerformanceTrace.shared.mark("chat.focus_begin") }
        view.becomeFirstResponder()
        if PerformanceTrace.enabled { PerformanceTrace.shared.mark("chat.focus_end") }
      }
      if !focused, view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Editor, context: Context) -> CGSize? {
      guard let width = proposal.width else { return nil }
      let line = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
      let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
      return CGSize(width: width, height: min(max(line, fit.height), line * 5))
    }

    final class Editor: UITextView {
      private var tracedGeneration = -1
      var tracedPresentation: Bool?

      override func layoutSubviews() {
        super.layoutSubviews()
        guard PerformanceTrace.enabled, window != nil, bounds.width > 0, bounds.height > 0,
          isEditable, isUserInteractionEnabled,
          tracedGeneration != PerformanceTrace.shared.generation
        else { return }
        tracedGeneration = PerformanceTrace.shared.generation
        PerformanceTrace.shared.mark("chat.composer_laid_out")
      }

      var insertingPaste = false
      var insertingLineBreak = false

      override var keyCommands: [UIKeyCommand]? {
        let newline = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(lineBreak))
        newline.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [newline]
      }

      override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(lineBreak) { return markedTextRange == nil }
        return super.canPerformAction(action, withSender: sender)
      }

      @objc private func lineBreak() {
        guard markedTextRange == nil else { return }
        insertingLineBreak = true
        defer { insertingLineBreak = false }
        insertText("\n")
      }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
      var parent: AskComposer
      init(_ parent: AskComposer) { self.parent = parent }

      // UIKit calls these synchronously during programmatic updates too; avoid reentrant state writes.
      func textViewDidBeginEditing(_ textView: UITextView) {
        if !parent.focused { parent.focused = true }
      }
      func textViewDidEndEditing(_ textView: UITextView) {
        if parent.focused { parent.focused = false }
      }
      func textViewDidChange(_ textView: UITextView) {
        parent.text = textView.text
        textView.invalidateIntrinsicContentSize()
      }

      func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
      ) -> Bool {
        guard let editor = textView as? Editor, text == "\n", editor.markedTextRange == nil,
          !editor.insertingPaste, !editor.insertingLineBreak
        else { return true }
        parent.text = editor.text
        editor.text = ""
        parent.onSubmit()
        return false
      }

      func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
        performPasteOf attributedString: NSAttributedString, to textRange: UITextRange
      ) -> UITextRange {
        guard let editor = textPasteConfigurationSupporting as? Editor else { return textRange }
        // UIKit has finished loading item providers and supplies the current replacement range.
        // This also distinguishes a paste containing only one newline from keyboard Return.
        editor.insertingPaste = true
        defer { editor.insertingPaste = false }
        editor.replace(textRange, withText: attributedString.string)
        textViewDidChange(editor)
        return editor.selectedTextRange ?? textRange
      }
    }
  }
#endif
