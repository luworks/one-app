import SwiftUI
import SwiftData

/// Left drawer, like the ChatGPT / Claude iOS apps: the page slides right and the drawer shows
/// the views with live counts, a new-chat button and settings.
struct Sidebar: View {
    @Binding var tab: HomeTab
    var onNewChat: () -> Void
    var onToday: () -> Void
    var onDeleteAll: () -> Void
    var close: () -> Void

    @Query private var tasks: [OneTask]
    @Query private var events: [OneEvent]
    @Query private var habits: [Habit]

    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Y")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Yuan").font(.headline)
                    Text("one.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            Button {
                onNewChat()
                close()
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(PressScale())
            .tint(.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(HomeTab.allCases) { item in
                        SidebarRow(icon: item.icon, title: item.title, detail: detail(for: item), selected: item == tab) {
                            tab = item
                            close()
                        }
                    }

                    Text("Settings")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 6)
                    SidebarRow(icon: "arrow.uturn.backward", title: "Calendar: go to today", detail: nil, selected: false) {
                        onToday()
                        close()
                    }
                    SidebarRow(icon: "trash", title: "Delete all data", detail: nil, selected: false, role: .destructive) {
                        close()
                        onDeleteAll()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }

    private func detail(for tab: HomeTab) -> String? {
        let n: Int
        switch tab {
        case .today:
            n = tasks.filter { t in
                guard !t.isDone else { return false }
                if t.isOverdue { return true }
                if let s = t.plannedStart, cal.isDateInToday(s) { return true }
                if let d = t.due, cal.isDateInToday(d) { return true }
                return false
            }.count
        case .calendar:
            n = events.filter { cal.isDateInToday($0.start) }.count
        case .tasks:
            n = tasks.filter { !$0.isDone }.count
        case .habits:
            let done = habits.filter { $0.isDone(on: .now) }.count
            return habits.isEmpty ? nil : "\(done)/\(habits.count)"
        case .alarms:
            n = tasks.filter { $0.reminderDate.map { $0 > .now && cal.isDateInToday($0) } ?? false }.count
                + events.filter { $0.reminderDate.map { $0 > .now && cal.isDateInToday($0) } ?? false }.count
        }
        return n == 0 ? nil : "\(n)"
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    let detail: String?
    let selected: Bool
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 22)
                Text(title)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(selected ? Color(.secondarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .padding(.horizontal, 6)
    }
}
