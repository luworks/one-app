#if os(iOS)
  import One
  import SwiftUI

  package struct UndoToastView: View {
    package init() {}
    @Environment(UndoToast.self) private var toast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
      if let message = toast.message {
        Group {
          if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
              caption(message)
              if toast.canUndo {
                HStack {
                  Spacer(minLength: 0)
                  undoButton
                }
              }
            }
          } else {
            HStack(spacing: 12) {
              caption(message)
              if toast.canUndo { undoButton }
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, typeSize.isAccessibilitySize || !toast.canUndo ? 12 : 2)
        .frame(minHeight: 48)
        .foregroundStyle(Color(.systemBackground))
        .background(Color(.label), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
        .padding(.horizontal, 20)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }

    private func caption(_ message: String) -> some View {
      Text(message)
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("undoToast.message")
    }

    private var undoButton: some View {
      Button {
        toast.performUndo()
      } label: {
        Text("Undo")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.accentColor)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .fixedSize()
    }
  }
#endif
