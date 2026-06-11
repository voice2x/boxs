import Foundation
import GRDB

/// 待办/备忘记录（本地 SQLite 模型）
struct TodoRecord: Codable, Sendable, Identifiable {
    var id: String
    var userId: String
    var type: String
    var content: String
    var remindAt: Date?
    var priority: String
    var isCompleted: Bool
    var completedAt: Date?
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId, type, content, remindAt, priority
        case isCompleted, completedAt, isDeleted, createdAt, updatedAt, deletedAt
    }
}

extension TodoRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "todo_record"

    mutating func willUpdate(_ db: Database, columns: Set<String>) {
        updatedAt = Date()
    }
}

extension TodoRecord {
    /// 创建一条新待办
    static func create(
        userId: String = "local",
        type: String = "todo",
        content: String,
        remindAt: Date? = nil,
        priority: String = "medium"
    ) -> TodoRecord {
        TodoRecord(
            id: UUID().uuidString,
            userId: userId,
            type: type,
            content: content,
            remindAt: remindAt,
            priority: priority,
            isCompleted: false,
            completedAt: nil,
            isDeleted: false,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil
        )
    }
}
