import Foundation
import GRDB

/// 习惯定义（本地 SQLite 模型）
struct HabitDefinition: Codable, Sendable, Identifiable {
    var id: String
    var userId: String
    var name: String
    var icon: String?
    var unit: String?
    var goalValue: String?
    var sortOrder: Int
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId, name, icon, unit, goalValue
        case sortOrder, isActive, createdAt, updatedAt
    }
}

extension HabitDefinition: FetchableRecord, PersistableRecord {
    static let databaseTableName = "habit_definition"
}

extension HabitDefinition {
    /// 创建一条新习惯定义
    static func create(
        userId: String = "local",
        name: String,
        icon: String? = nil,
        unit: String? = nil,
        goalValue: String? = nil
    ) -> HabitDefinition {
        HabitDefinition(
            id: UUID().uuidString,
            userId: userId,
            name: name,
            icon: icon,
            unit: unit,
            goalValue: goalValue,
            sortOrder: 0,
            isActive: true,
            createdAt: Date(),
            updatedAt: nil
        )
    }
}
