#if os(iOS)
  import One
  import TodayCore
  import TodayData
  import TodayPlatform
  import TodayDesignSystem
  import SwiftUI
  import SwiftData

  /// "Tidy overdue" opened straight from Today's overdue line: the same suggestions and Apply as the Ask card.
  /// Nothing changes until Apply; the toast offers Undo.
  package struct TidySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var rows: [TidyRow]
    private let actions: PlannerActions
    private let ledger: Ledger
    private let toast: UndoToast?
    private let presentation: PlannerPresentation

    package init(
      overdue: [OneTask], actions: PlannerActions, ledger: Ledger,
      presentation: PlannerPresentation, toast: UndoToast?
    ) {
      self.presentation = presentation
      self.actions = actions
      self.ledger = ledger
      self.toast = toast
      _rows = State(
        initialValue: Self.suggestions(for: overdue, runtime: presentation.runtime))
    }

    /// One suggested date per overdue reminder (see `OverdueTidy`).
    static func suggestions(for overdue: [OneTask], runtime: PlannerRuntime) -> [TidyRow] {
      let items = overdue.enumerated().compactMap { i, t in
        t.due.map {
          OverdueTidy.Item(id: i, due: $0, flagged: t.flagged, repeats: t.repeats != nil)
        }
      }
      return OverdueTidy.suggest(items, now: runtime.now(), calendar: runtime.calendar)
        .compactMap { s in
          overdue[s.id].due.map { TidyRow(task: overdue[s.id], oldDue: $0, choice: s.choice) }
        }
    }

    package var body: some View {
      ScrollView {
        TidyCard(rows: $rows, onApply: apply, onCancel: { dismiss() })
          .padding()
      }
      .environment(presentation)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }

    private func apply() {
      let feedback = AskNativeActions.applyTidy(
        rows: &rows, context: context, actions: actions, ledger: ledger,
        runtime: presentation.runtime)
      if let undo = feedback.undo {
        toast?.show(undo.label, undo: undo.action)
      } else if let message = feedback.messages.last {
        toast?.showNotice(message.text)
      }
      if feedback.applied { dismiss() }
    }
  }
#endif
