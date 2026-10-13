import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]

    var body: some View {
        List {
            section("未安排", tasks.filter { !$0.isDone && $0.plannedStart == nil })
            section("已安排", tasks
                .filter { !$0.isDone && $0.plannedStart != nil }
                .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) })
            section("已完成", tasks.filter(\.isDone))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("任务")
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("还没有任务", systemImage: "checklist",
                                       description: Text("在首页底部输入一件事就能添加。"))
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [OneTask]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { TaskRow(task: $0) }
                    .onDelete { offsets in
                        for i in offsets { context.delete(items[i]) }
                    }
            }
        }
    }
}
