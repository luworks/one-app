import SwiftUI

/// One item the AI proposes from the user's line. Nothing is written until it is added.
struct CaptureProposal: Identifiable, Equatable {
    enum State: Equatable { case open, added }
    let id = UUID()
    var capture: Capture
    var state: State = .open
    /// How many items the line produced; a line with several keeps the list layout as rows leave.
    var batchSize = 1
}

/// Every item from one line at once: a single item is the full preview card; several are compact rows with their own
/// Add and Skip, one "Add all", and a tap to open a row for editing. Added items briefly show a check, then leave.
struct CaptureStack: View {
    @Binding var proposals: [CaptureProposal]
    /// The user's Reminders lists, for the list menu on tasks.
    let lists: [String]
    var onAdd: (UUID) -> Void
    var onSkip: (UUID) -> Void
    var onAddAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: UUID?

    private var openCount: Int { proposals.filter { $0.state == .open }.count }
    private var addedCount: Int { proposals.filter { $0.state == .added }.count }

    var body: some View {
        Group {
            if proposals.count == 1, let only = proposals.first, only.batchSize == 1 {
                if only.state == .open {
                    CaptureCard(capture: binding(only.id), lists: lists,
                                onAdd: { onAdd(only.id) }, onCancel: { onSkip(only.id) })
                } else {
                    AddedRow(capture: only.capture)
                        .padding(14)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
                }
            } else {
                list
            }
        }
        .sensoryFeedback(.success, trigger: addedCount) { old, new in new > old }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-stack")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(openCount > 0 ? "\(openCount) new item\(openCount == 1 ? "" : "s")" : "Added", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if openCount > 1 {
                    Button("Add all", action: onAddAll)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("capture-add-all")
                }
            }
            // Up to three rows fit above the keyboard; more scroll inside the card.
            if proposals.count > 3 {
                ScrollView { rows }.frame(height: 300)
            } else {
                rows
            }
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(proposals) { p in
                row(p).transition(rowTransition)
            }
        }
    }

    @ViewBuilder
    private func row(_ p: CaptureProposal) -> some View {
        if p.state == .added {
            AddedRow(capture: p.capture)
                .padding(.vertical, 4)
        } else if expanded == p.id {
            CaptureCard(capture: binding(p.id), lists: lists,
                        onAdd: { onAdd(p.id) }, onCancel: { onSkip(p.id) }, cancelTitle: "Skip")
        } else {
            CompactCaptureRow(capture: binding(p.id), lists: lists,
                              onOpen: { withAnimation(.snappy) { expanded = p.id } },
                              onAdd: { onAdd(p.id) }, onSkip: { onSkip(p.id) })
        }
    }

    /// The card folds into its check: a small scale and fade, or a plain fade with Reduce Motion.
    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    private func binding(_ id: UUID) -> Binding<Capture> {
        Binding(
            get: { proposals.first { $0.id == id }?.capture ?? Capture(title: "", day: .now, hasDay: false) },
            set: { new in
                if let i = proposals.firstIndex(where: { $0.id == id }) { proposals[i].capture = new }
            })
    }
}

/// A proposed item in a list of several: title, when, list, and its own Skip and Add. Tap the text to edit it.
struct CompactCaptureRow: View {
    @Binding var capture: Capture
    let lists: [String]
    var onOpen: () -> Void
    var onAdd: () -> Void
    var onSkip: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(capture.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if capture.kind == .task, !capture.ringsAsAlarm, !lists.isEmpty {
                    ListMenu(capture: $capture, lists: lists).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit")
            Button(action: onSkip) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.secondary)
            .accessibilityLabel("Skip")
            Button(action: onAdd) {
                Image(systemName: "plus").font(.subheadline.weight(.semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Add")
            .accessibilityIdentifier("capture-row-add")
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Where a task will be filed. One tap opens the user's lists.
struct ListMenu: View {
    @Binding var capture: Capture
    let lists: [String]

    var body: some View {
        Menu {
            Picker("List", selection: Binding(get: { capture.listName == "Reminders" ? "" : capture.listName ?? "" },
                                              set: { capture.listName = $0.isEmpty ? nil : $0 })) {
                // The list with no name of its own is Apple's "Reminders" (`listName == ""`).
                Text("Reminders").tag("")
                ForEach(lists.filter { !$0.isEmpty && $0 != "Reminders" }, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Label(capture.listLabel, systemImage: "list.bullet")
                .lineLimit(1)
        }
        .tint(.secondary)
        .accessibilityLabel("List: \(capture.listLabel)")
        .accessibilityIdentifier("capture-list")
    }
}

/// What an added item turns into: a check that pops once (still with Reduce Motion: a symbol effect, not movement).
struct AddedRow: View {
    let capture: Capture
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: shown)
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.title).font(.subheadline).lineLimit(1)
                Text("Added · " + detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture-added")
    }

    private var detail: String {
        guard capture.kind == .task, !capture.ringsAsAlarm else { return capture.summary }
        return capture.summary + " · " + capture.listLabel
    }
}
