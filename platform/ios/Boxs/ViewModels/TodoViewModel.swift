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
            do {
                let db = try AppDatabase.shared.getDB()
                let records: [TodoRecord] = try db.read { db in
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
            do {
                let db = try AppDatabase.shared.getDB()
                try db.write { db in
                    if var record = try TodoRecord.fetchOne(db, key: id) {
                        record.isCompleted = true
                        record.completedAt = Date()
                        try record.save(db)
                    }
                }
                loadTodos()
            } catch {
                print("完成待办失败: \(error)")
            }
        }
    }

    func deleteTodo(id: String) {
        Task {
            do {
                let db = try AppDatabase.shared.getDB()
                try db.write { db in
                    if var record = try TodoRecord.fetchOne(db, key: id) {
                        record.isDeleted = true
                        record.deletedAt = Date()
                        try record.save(db)
                    }
                }
                loadTodos()
            } catch {
                print("删除待办失败: \(error)")
            }
        }
    }
}
