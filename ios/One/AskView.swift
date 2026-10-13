import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, ai }
    let id = UUID()
    let role: Role
    let text: String
}

/// Full-screen AI page, modeled on ChatGPT / Claude mobile.
/// No live model yet: statements become a capture preview; questions get a local summary.
/// Nothing is created until the user taps 添加 on the preview card.
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]

    var onAdded: (Capture) -> Void = { _ in }

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var pending: Capture?
    @FocusState private var focused: Bool

    private let suggestions = [
        "明天下午3点 打电话给 Alex",
        "周五 交季度报告",
        "今天还有什么要做？",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { MessageView(message: $0).id($0.id) }
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputArea }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭")
                }
            }
            .task { focused = true }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("今天想安排点什么？")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(PressScale())
                    .tint(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            if let capture = pending {
                CaptureCard(capture: capture, onAdd: { add(capture) }, onCancel: { pending = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("问 AI 或记一件事", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.vertical, 8)
                if isEmpty {
                    Image(systemName: "mic.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("语音输入（暂未支持）")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .accessibilityLabel("发送")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.snappy, value: pending)
    }

    private var isEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        if isQuestion(text) {
            messages.append(ChatMessage(role: .ai, text: todaySummary))
        } else {
            pending = CaptureParser.parse(text)
            messages.append(ChatMessage(role: .ai, text: "我理解成下面这样，确认后再添加。"))
        }
    }

    private func add(_ capture: Capture) {
        context.insert(capture.makeTask())
        onAdded(capture)
        messages.append(ChatMessage(role: .ai, text: "已添加「\(capture.title)」，\(capture.summary)。"))
        pending = nil
    }

    private func isQuestion(_ text: String) -> Bool {
        text.hasSuffix("?") || text.hasSuffix("？") || ["什么", "怎么", "吗", "多少", "几"].contains { text.contains($0) }
    }

    private var todaySummary: String {
        let cal = Calendar.current
        let open = tasks.filter { task in
            guard !task.isDone else { return false }
            if task.isOverdue { return true }
            if let s = task.plannedStart, cal.isDateInToday(s) { return true }
            if let d = task.due, cal.isDateInToday(d) { return true }
            return false
        }
        let todayEvents = events.filter { cal.isDateInToday($0.start) && $0.start > .now }
        var lines = ["今天还有 \(open.count) 件任务、\(todayEvents.count) 个日程没过。"]
        lines += open.prefix(5).map { "· " + $0.title }
        lines += todayEvents.prefix(3).map { "· " + $0.start.formatted(date: .omitted, time: .shortened) + " " + $0.title }
        lines.append("（AI 模型还没接入，这是根据本地数据的汇总。）")
        return lines.joined(separator: "\n")
    }
}

/// User messages are bubbles on the right; AI replies are plain text, no bubble.
struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 20))
            }
        case .ai:
            Text(message.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
