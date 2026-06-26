import Foundation

// MARK: - Date Formatter 工具

extension DateFormatter {
    /// "2026-06-12"
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "2026-06-12T14:30:00.123456+00:00" 或 "2026-06-12T14:30:00Z"
    static let iso8601Full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "15:00:00"
    static let HHmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// 从 ISO 8601 字符串解析 Date（兼容带/不带毫秒、带/不带时区）
func parseISO8601(_ string: String) -> Date? {
    // 尝试 ISO8601DateFormatter（iOS 11+）
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: string) { return date }
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: string) { return date }
    // 兜底：手动截断
    let truncated = String(string.prefix(19))
    return DateFormatter.iso8601Full.date(from: truncated)
}

/// Date → "2026-06-12"
func formatDateYMD(_ date: Date) -> String {
    DateFormatter.yyyyMMdd.string(from: date)
}

/// Date → "15:00:00"
func formatTimeHMS(_ date: Date) -> String {
    DateFormatter.HHmmss.string(from: date)
}

/// Date → ISO8601 字符串 "2026-06-12T14:30:00Z"
func formatISO8601(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: date)
}

// MARK: - Expense Mapper

enum ExpenseMapper {
    /// 本地 ExpenseRecord → 后端 CreateExpenseRequest
    static func toCreateDTO(_ local: ExpenseRecord) -> CreateExpenseRequest {
        CreateExpenseRequest(
            record_type: local.type,
            amount_cents: local.amountCents,
            category: local.category,
            note: local.note,
            record_date: formatDateYMD(local.recordDate)
        )
    }

    /// 后端 ExpenseDTO → 本地 ExpenseRecord
    static func toLocal(_ dto: ExpenseDTO) -> ExpenseRecord {
        ExpenseRecord(
            id: dto.id,
            userId: dto.user_id,
            type: dto.record_type,
            amountCents: dto.amount_cents,
            currency: "CNY",
            category: dto.category,
            merchant: nil,
            note: dto.note,
            recordDate: DateFormatter.yyyyMMdd.date(from: dto.record_date) ?? Date(),
            source: "sync",
            isDeleted: dto.deleted_at != nil,
            createdAt: parseISO8601(dto.created_at) ?? Date(),
            updatedAt: dto.updated_at.flatMap { parseISO8601($0) },
            deletedAt: dto.deleted_at.flatMap { parseISO8601($0) }
        )
    }
}

// MARK: - Habit Mapper

enum HabitMapper {
    /// 本地 HabitDefinition → 后端 CreateHabitRequest
    static func toCreateDTO(_ local: HabitDefinition) -> CreateHabitRequest {
        CreateHabitRequest(
            name: local.name,
            emoji: local.icon,
            frequency: "daily",
            target_value: local.goalValue.flatMap { Double($0) },
            unit: local.unit
        )
    }

    /// 后端 HabitDefinitionDTO → 本地 HabitDefinition
    static func toLocal(_ dto: HabitDefinitionDTO) -> HabitDefinition {
        HabitDefinition(
            id: dto.id,
            userId: dto.user_id,
            name: dto.name,
            icon: dto.emoji,
            unit: dto.unit,
            goalValue: dto.target_value.map { String($0) },
            sortOrder: 0,
            isActive: dto.is_active,
            createdAt: parseISO8601(dto.created_at) ?? Date(),
            updatedAt: dto.updated_at.flatMap { parseISO8601($0) }
        )
    }
}

// MARK: - HabitRecord Mapper

enum HabitRecordMapper {
    /// 本地 HabitRecord → 后端 CheckinRequest
    static func toCheckinDTO(_ local: HabitRecord) -> CheckinRequest {
        CheckinRequest(
            habit_id: local.habitId,
            value: local.value.flatMap { Double($0) },
            note: nil,
            record_date: formatDateYMD(local.recordDate)
        )
    }

    /// 后端 HabitRecordDTO → 本地 HabitRecord
    static func toLocal(_ dto: HabitRecordDTO) -> HabitRecord {
        HabitRecord(
            id: dto.id,
            userId: dto.user_id,
            habitId: dto.habit_id,
            value: dto.value.map { String($0) },
            recordDate: DateFormatter.yyyyMMdd.date(from: dto.record_date) ?? Date(),
            createdAt: parseISO8601(dto.created_at) ?? Date(),
            updatedAt: dto.updated_at.flatMap { parseISO8601($0) }
        )
    }
}

// MARK: - Todo Mapper

enum TodoMapper {
    /// 本地 TodoRecord → 后端 CreateTodoRequest
    static func toCreateDTO(_ local: TodoRecord) -> CreateTodoRequest {
        var dueDate: String? = nil
        var dueTime: String? = nil
        if let remindAt = local.remindAt {
            dueDate = formatDateYMD(remindAt)
            dueTime = formatTimeHMS(remindAt)
        }
        return CreateTodoRequest(
            title: local.content,
            note: nil,
            due_date: dueDate,
            due_time: dueTime,
            priority: local.priority
        )
    }

    /// 后端 TodoDTO → 本地 TodoRecord
    static func toLocal(_ dto: TodoDTO) -> TodoRecord {
        // 合并 due_date + due_time 为 remindAt
        var remindAt: Date? = nil
        if let dueDate = dto.due_date {
            let hasTime = dto.due_time != nil
            var dateString = dueDate
            if let dueTime = dto.due_time {
                dateString += "T\(dueTime)"
            }
            let formatter = DateFormatter()
            formatter.dateFormat = hasTime ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            remindAt = formatter.date(from: dateString)
        }

        return TodoRecord(
            id: dto.id,
            userId: dto.user_id,
            type: "todo",
            content: dto.title,
            remindAt: remindAt,
            priority: dto.priority ?? "medium",
            isCompleted: dto.status == "completed",
            completedAt: dto.completed_at.flatMap { parseISO8601($0) },
            isDeleted: dto.deleted_at != nil,
            createdAt: parseISO8601(dto.created_at) ?? Date(),
            updatedAt: dto.updated_at.flatMap { parseISO8601($0) },
            deletedAt: dto.deleted_at.flatMap { parseISO8601($0) }
        )
    }
}

// MARK: - Sync Batch Changes (本地 → /batch)

struct ExpenseChange: Codable {
    let id: String
    let user_id: String
    let record_type: String
    let amount_cents: Int
    let category: String
    let note: String?
    let record_date: String
    let deleted_at: String?
    let created_at: String
    let updated_at: String?
}

extension ExpenseMapper {
    static func toChange(_ r: ExpenseRecord) -> ExpenseChange {
        ExpenseChange(
            id: r.id, user_id: r.userId, record_type: r.type, amount_cents: r.amountCents,
            category: r.category, note: r.note, record_date: formatDateYMD(r.recordDate),
            deleted_at: r.deletedAt.map { formatISO8601($0) },
            created_at: formatISO8601(r.createdAt),
            updated_at: r.updatedAt.map { formatISO8601($0) }
        )
    }
}

struct HabitChange: Codable {
    let id: String
    let user_id: String
    let name: String
    let emoji: String?
    let frequency: String
    let target_value: Double?
    let unit: String?
    let is_active: Bool
    let created_at: String
    let updated_at: String?
}

extension HabitMapper {
    static func toChange(_ r: HabitDefinition) -> HabitChange {
        HabitChange(
            id: r.id, user_id: r.userId, name: r.name, emoji: r.icon,
            frequency: "daily", target_value: r.goalValue.flatMap { Double($0) },
            unit: r.unit, is_active: r.isActive,
            created_at: formatISO8601(r.createdAt),
            updated_at: r.updatedAt.map { formatISO8601($0) }
        )
    }
}

struct TodoChange: Codable {
    let id: String
    let user_id: String
    let title: String
    let note: String?
    let due_date: String?
    let due_time: String?
    let priority: String?
    let status: String
    let completed_at: String?
    let deleted_at: String?
    let created_at: String
    let updated_at: String?
}

extension TodoMapper {
    static func toChange(_ r: TodoRecord) -> TodoChange {
        TodoChange(
            id: r.id, user_id: r.userId, title: r.content, note: nil,
            due_date: r.remindAt.map { formatDateYMD($0) },
            due_time: r.remindAt.map { formatTimeHMS($0) },
            priority: r.priority,
            status: r.isCompleted ? "completed" : "pending",
            completed_at: r.completedAt.map { formatISO8601($0) },
            deleted_at: r.deletedAt.map { formatISO8601($0) },
            created_at: formatISO8601(r.createdAt),
            updated_at: r.updatedAt.map { formatISO8601($0) }
        )
    }
}

struct CheckinChange: Codable {
    let habit_id: String
    let record_date: String
    let value: Double?
    let note: String?
    let updated_at: String
}

extension HabitRecordMapper {
    static func toChange(_ r: HabitRecord) -> CheckinChange {
        CheckinChange(
            habit_id: r.habitId,
            record_date: formatDateYMD(r.recordDate),
            value: r.value.flatMap { Double($0) },
            note: nil,
            updated_at: formatISO8601(r.updatedAt ?? r.createdAt)
        )
    }
}
