import Foundation
import GRDB

/// 习惯打卡记录（本地 SQLite 模型）
struct HabitRecord: Codable, Sendable, Identifiable {
    var id: String
    var userId: String
    var habitId: String
    var value: String?
    var recordDate: Date
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId, habitId, value, recordDate, createdAt, updatedAt
    }
}

extension HabitRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "habit_record"
}

extension HabitRecord {
    /// 创建一条打卡记录
    static func create(
        userId: String = "local",
        habitId: String,
        value: String? = nil,
        recordDate: Date = Date()
    ) -> HabitRecord {
        HabitRecord(
            id: UUID().uuidString,
            userId: userId,
            habitId: habitId,
            value: value,
            recordDate: recordDate,
            createdAt: Date(),
            updatedAt: nil
        )
    }
}
