#if os(iOS)
  import One
  import SwiftUI

  package struct UndoToastView: View {
    package init() {}
    @Environment(UndoToast.self) private var toast

    package var body: some View {
      if let message = toast.message {
        HStack(spacing: 12) {
          Text(message)
            .font(.subheadline)
            .lineLimit(toast.canUndo ? 1 : 2)
          Spacer(minLength: 8)
          if toast.canUndo {
            Button("Undo") { toast.performUndo() }
              .font(.subheadline.weight(.semibold))
              .tint(Color.accentColor)
          }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .foregroundStyle(Color(.systemBackground))
        .background(Color(.label), in: Capsule())
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }
#endif
