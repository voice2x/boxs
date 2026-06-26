import Foundation
import Observation
import GRDB

/// 待办 ViewModel
@Observable
@MainActor
final class TodoViewModel {
    var todos: [Todo] = []
    var isLoading = false
    var filter: TodoFilter = .all

    enum TodoFilter: String, CaseIterable {
        case all = "全部"
        case pending = "待完成"
        case completed = "已完成"
    }

    var filteredTodos: [Todo] {
        switch filter {
        case .all: return todos
        case .pending: return todos.filter { !$0.isCompleted }
        case .completed: return todos.filter { $0.isCompleted }
        }
    }

    func loadTodos() {
        isLoading = true
        Task {
            defer { isLoading = false }

            // 从后端同步待办数据
            if TokenManager.shared.isLoggedIn {
                await SyncEngine.shared.sync()
            }

            do {
                let db = try AppDatabase.shared.getDB()
                let records: [TodoRecord] = try await db.read { db in
                    try TodoRecord
                        .filter(Column("isDeleted") == false)
                        .order(Column("createdAt").desc)
                        .fetchAll(db)
                }
                self.todos = records.map { Todo.from($0) }
            } catch {
                print("加载待办列表失败: \(error)")
            }
        }
    }

    func completeTodo(id: String) {
        Task {
            await SyncEngine.shared.enqueueTodoComplete(id: id)
            await SyncEngine.shared.sync()
            loadTodos()
        }
    }

    func deleteTodo(id: String) {
        Task {
            await SyncEngine.shared.enqueueTodoDelete(id: id)
            await SyncEngine.shared.sync()
            loadTodos()
        }
    }
}
