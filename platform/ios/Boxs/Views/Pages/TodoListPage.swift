import SwiftUI

/// 待办列表页
struct TodoListPage: View {
    @State private var viewModel = TodoViewModel()

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            // 筛选器
            filterBar

            AppDivider()

            // 待办列表
            if viewModel.filteredTodos.isEmpty {
                emptyView
            } else {
                todoList
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.background)
        .navigationTitle("待办")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTodos()
        }
    }

    // MARK: - 筛选器

    private var filterBar: some View {
        HStack(spacing: S.row) {
            ForEach(TodoViewModel.TodoFilter.allCases, id: \.self) { filter in
                Button(action: { viewModel.filter = filter }) {
                    Text(filter.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.filter == filter ? .white : c.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.filter == filter ? c.primary : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: R.tag))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, S.page)
        .padding(.vertical, 8)
    }

    // MARK: - 列表

    private var todoList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredTodos) { todo in
                    HStack(spacing: 10) {
                        // 完成按钮
                        Button(action: { Task { await viewModel.completeTodo(id: todo.id) } }) {
                            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: Sz.icon))
                                .foregroundStyle(todo.isCompleted ? c.primary : c.textHint)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(todo.content)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(todo.isCompleted ? c.textHint : c.textPrimary)
                                .strikethrough(todo.isCompleted)

                            if let remindAt = todo.remindAt {
                                Text("提醒 \(DateFormatter.shortTime.string(from: remindAt))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(c.textSecondary)
                            }
                        }

                        Spacer()

                        Text(todo.priorityEmoji)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, S.page)
                    .frame(minHeight: Sz.listItem)

                    if todo.id != viewModel.filteredTodos.last?.id {
                        AppDivider()
                    }
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("📝")
                .font(.system(size: 32))
            Text("暂无待办")
                .font(.system(size: 14))
                .foregroundStyle(c.textHint)
            Text("试试说「记得买牛奶」")
                .font(.system(size: 12))
                .foregroundStyle(c.textHint)
            Spacer()
        }
    }
}
