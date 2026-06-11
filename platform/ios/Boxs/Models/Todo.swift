import Foundation

/// 待办领域模型
struct Todo: Identifiable {
    let id: String
    let type: String           // todo / memo / idea
    let content: String
    let remindAt: Date?
    let priority: String       // high / medium / low
    let isCompleted: Bool
    let createdAt: Date

    var priorityEmoji: String {
        switch priority {
        case "high": return "🔴"
        case "medium": return "🟡"
        case "low": return "🟢"
        default: return "⚪️"
        }
    }

    static func from(_ record: TodoRecord) -> Todo {
        Todo(
            id: record.id,
            type: record.type,
            content: record.content,
            remindAt: record.remindAt,
            priority: record.priority,
            isCompleted: record.isCompleted,
            createdAt: record.createdAt
        )
    }
}
