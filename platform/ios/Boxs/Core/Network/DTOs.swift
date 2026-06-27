import Foundation

// MARK: - Sync 通用信封

struct BatchRequest<C: Encodable & Sendable>: Encodable, Sendable {
    let changes: [C]
}

struct ChangesResponse<D: Decodable & Sendable>: Decodable, Sendable {
    let items: [D]
    let next_cursor: String?
}

struct BatchResult<D: Decodable & Sendable>: Decodable, Sendable {
    let status: String   // "applied" | "conflict" | "error"
    let record: D?
}

// MARK: - Expense DTOs

struct ExpenseDTO: Decodable, Sendable {
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

struct CreateExpenseRequest: Encodable {
    let record_type: String
    let amount_cents: Int
    let category: String
    let note: String?
    let record_date: String
}

struct ExpenseListDTO: Decodable, Sendable {
    let items: [ExpenseDTO]
    let total: Int
    let page: Int
    let page_size: Int
}

struct ExpenseStatsDTO: Decodable, Sendable {
    let total_income: Int
    let total_expense: Int
    let categories: [CategoryStatsDTO]
}

struct CategoryStatsDTO: Decodable, Sendable {
    let category: String
    let total_cents: Int
    let count: Int
}

// MARK: - Habit DTOs

struct HabitDefinitionDTO: Decodable, Sendable {
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

struct CreateHabitRequest: Encodable {
    let name: String
    let emoji: String?
    let frequency: String?
    let target_value: Double?
    let unit: String?
}

struct HabitRecordDTO: Decodable, Sendable {
    let id: String
    let habit_id: String
    let user_id: String
    let value: Double?
    let note: String?
    let record_date: String
    let created_at: String
    let updated_at: String?
}

struct CheckinRequest: Encodable {
    let habit_id: String
    let value: Double?
    let note: String?
    let record_date: String
}

struct CalendarResponseDTO: Decodable, Sendable {
    let habit: HabitDefinitionDTO
    let records: [HabitRecordDTO]
}

// MARK: - Todo DTOs

struct TodoDTO: Decodable, Sendable {
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

struct CreateTodoRequest: Encodable {
    let title: String
    let note: String?
    let due_date: String?
    let due_time: String?
    let priority: String?
}
