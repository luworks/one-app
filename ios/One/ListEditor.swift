import SwiftUI
import SwiftData

/// The colored circle with a white glyph that stands for a list (cards, rows, the editor preview).
struct ListGlyph: View {
    let color: Color
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// "1 reminder", "5 reminders".
func reminderCountText(_ n: Int) -> String { n == 1 ? "1 reminder" : "\(n) reminders" }

/// What a list delete is about to do, so the alert can say how many reminders go with it.
struct PendingListDeletion {
    let list: OneList
    let name: String
    let count: Int
    var afterDelete: (() -> Void)?

    @MainActor
    static func make(_ list: OneList, context: ModelContext, afterDelete: (() -> Void)? = nil) -> PendingListDeletion {
        PendingListDeletion(list: list, name: ListName.display(list.name),
                            count: ListActions.taskCount(in: list.name, context: context), afterDelete: afterDelete)
    }

    var message: String {
        count == 0 ? "This list is empty." : "This also deletes \(reminderCountText(count)) in it. This can't be undone."
    }
}

extension View {
    /// Confirmation before deleting a list and the reminders in it.
    func deleteListAlert(_ pending: Binding<PendingListDeletion?>) -> some View {
        modifier(DeleteListAlert(pending: pending))
    }
}

private struct DeleteListAlert: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var pending: PendingListDeletion?

    func body(content: Content) -> some View {
        content.alert(
            Text(pending.map { "Delete “\($0.name)”?" } ?? "Delete List?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { item in
            Button("Delete", role: .destructive) {
                ListActions.delete(item.list, in: context)
                item.afterDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }
}

/// New List / Name & Appearance: a big preview circle, the name, 12 colors and a grid of symbols.
/// Creates a list when `list` is nil, otherwise edits it.
struct ListEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \OneList.order) private var lists: [OneList]

    let list: OneList?
    /// Called with the list that was just created.
    var onCreated: ((OneList) -> Void)?

    @State private var name: String
    @State private var colorIndex: Int
    @State private var symbol: String
    @State private var pendingDelete: PendingListDeletion?
    @FocusState private var nameFocused: Bool

    init(list: OneList? = nil, onCreated: ((OneList) -> Void)? = nil) {
        self.list = list
        self.onCreated = onCreated
        // Copied once: the sheet must not read the model again, it may be deleted while the sheet closes.
        _name = State(initialValue: list?.name ?? "")
        _colorIndex = State(initialValue: list?.colorIndex ?? 6)
        _symbol = State(initialValue: list?.symbol ?? "list.bullet")
    }

    private static let colorNames = ["Red", "Orange", "Yellow", "Green", "Mint", "Sky blue", "Blue", "Indigo", "Purple", "Pink", "Brown", "Gray"]

    private var color: Color { ReminderPalette.color(colorIndex) }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var problem: String? { ListActions.nameProblem(name, existing: lists, excluding: list) }
    private var canSave: Bool { problem == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ListGlyph(color: color, symbol: symbol, size: 92)
                        .shadow(color: color.opacity(0.35), radius: 12, y: 6)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        TextField("List Name", text: $name)
                            .focused($nameFocused)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(color)
                            .multilineTextAlignment(.center)
                            .submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 36)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .trailing) {
                                if !name.isEmpty {
                                    Button { name = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.trailing, 12)
                                    .accessibilityLabel("Clear name")
                                }
                            }
                        if !trimmed.isEmpty, let problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .accessibilityIdentifier("listNameProblem")
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 14) {
                        ForEach(ReminderPalette.colors.indices, id: \.self) { i in
                            Button { colorIndex = i } label: {
                                Circle()
                                    .fill(ReminderPalette.colors[i])
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if i == colorIndex {
                                            Circle().strokeBorder(Color(.systemGray3), lineWidth: 3).padding(-5)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(i < Self.colorNames.count ? Self.colorNames[i] : "Color \(i + 1)")
                            .accessibilityAddTraits(i == colorIndex ? .isSelected : [])
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                        ForEach(ReminderPalette.symbols, id: \.self) { s in
                            Button { symbol = s } label: {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 38, height: 38)
                                    .overlay {
                                        Image(systemName: s)
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(Color(.label).opacity(0.75))
                                    }
                                    .overlay {
                                        if s == symbol {
                                            Circle().strokeBorder(Color(.systemGray3), lineWidth: 3).padding(-4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(s == symbol ? .isSelected : [])
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let list {
                        Button(role: .destructive) {
                            pendingDelete = .make(list, context: context) { dismiss() }
                        } label: {
                            Text("Delete List")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(list == nil ? "New List" : "Name & Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save).fontWeight(.semibold).disabled(!canSave)
                }
            }
            .onAppear { if list == nil { nameFocused = true } }
            .deleteListAlert($pendingDelete)
        }
        .tint(color)
        .presentationDetents([.large])
    }

    private func save() {
        if let list {
            guard ListActions.rename(list, to: name, in: context) else { return }
            list.colorIndex = colorIndex
            list.symbol = symbol
        } else if let created = ListActions.create(name: name, colorIndex: colorIndex, symbol: symbol, in: context) {
            onCreated?(created)
        } else {
            return
        }
        dismiss()
    }
}
