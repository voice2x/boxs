import Foundation
import Observation
import GRDB
import os.log

/// 主页 ViewModel — 概览数据 + 记录列表
@Observable
@MainActor
final class HomeViewModel {

    private let logger = Logger(subsystem: "com.boxs.app", category: "HomeViewModel")

    // MARK: - 概览数据
    var todayTodoCount: Int = 0
    var todayTodoCompleted: Int = 0
    var monthExpenseCents: Int = 0
    var monthExpenseChange: Double = 0
    var todayHabitChecked: Int = 0
    var todayHabitTotal: Int = 0

    // MARK: - 记录列表
    var recentRecords: [RecordItem] = []
    var isLoading = false

    // MARK: - 加载数据

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let db = try AppDatabase.shared.getDB()
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

            let todos: [TodoRecord] = try await db.read { db in
                try TodoRecord
                    .filter(Column("isDeleted") == false)
                    .filter(Column("createdAt") >= startOfDay)
                    .fetchAll(db)
            }
            let expenses: [ExpenseRecord] = try await db.read { db in
                try ExpenseRecord
                    .filter(Column("isDeleted") == false)
                    .filter(Column("type") == "expense")
                    .filter(Column("recordDate") >= startOfMonth)
                    .fetchAll(db)
            }
            let habits: [HabitDefinition] = try await db.read { db in
                try HabitDefinition.filter(Column("isActive") == true).fetchAll(db)
            }
            let habitRecords: [HabitRecord] = try await db.read { db in
                try HabitRecord.filter(Column("recordDate") >= startOfDay).fetchAll(db)
            }

            self.todayTodoCount = todos.count
            self.todayTodoCompleted = todos.filter(\.isCompleted).count
            self.monthExpenseCents = expenses.reduce(0) { $0 + $1.amountCents }
            self.todayHabitTotal = habits.count
            self.todayHabitChecked = habitRecords.count

            try await loadRecentRecords(db: db)
        } catch {
            logger.error("加载主页数据失败: \(error)")
        }
    }

    private func loadRecentRecords(db: DatabaseQueue) async throws {
        var items: [RecordItem] = []

        let expenses: [ExpenseRecord] = try await db.read { db in
            try ExpenseRecord
                .filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc)
                .limit(10)
                .fetchAll(db)
        }
        for expense in expenses {
            let category = ExpenseCategory(rawValue: expense.category) ?? .other
            items.append(RecordItem(
                id: expense.id, emoji: category.emoji,
                title: expense.note ?? expense.category,
                subtitle: formatExpenseSubtitle(expense),
                trailing: expense.signedDisplayAmount,
                trailingColor: expense.type == "expense" ? "expense" : "income",
                type: .expense, createdAt: expense.createdAt
            ))
        }

        let habitRecords: [HabitRecord] = try await db.read { db in
            try HabitRecord.order(Column("createdAt").desc).limit(5).fetchAll(db)
        }
        for record in habitRecords {
            let habitName: String = (try? await db.read { db in
                try HabitDefinition.filter(id: record.habitId).fetchOne(db)?.name
            }) ?? "习惯"
            items.append(RecordItem(
                id: record.id, emoji: "✓", title: habitName,
                subtitle: record.value ?? "已打卡", trailing: "✓",
                trailingColor: "primary", type: .habit, createdAt: record.createdAt
            ))
        }

        let todos: [TodoRecord] = try await db.read { db in
            try TodoRecord
                .filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc)
                .limit(5)
                .fetchAll(db)
        }
        for todo in todos {
            items.append(RecordItem(
                id: todo.id, emoji: "📝", title: todo.content,
                subtitle: formatTodoSubtitle(todo),
                trailing: todo.isCompleted ? "✓" : "○",
                trailingColor: todo.isCompleted ? "primary" : "hint",
                type: .todo, createdAt: todo.createdAt
            ))
        }

        items.sort { $0.createdAt > $1.createdAt }
        self.recentRecords = Array(items.prefix(20))
    }

    // MARK: - 格式化

    var monthExpenseDisplay: String {
        let amount = Double(monthExpenseCents) / 100.0
        return "¥\(formatNumber(amount))"
    }

    var todoProgress: CGFloat {
        guard todayTodoCount > 0 else { return 0 }
        return CGFloat(todayTodoCompleted) / CGFloat(todayTodoCount)
    }

    var habitEmojiStatus: String {
        let checked = min(todayHabitChecked, 5)
        let unchecked = max(todayHabitTotal - todayHabitChecked, 0)
        var result = String(repeating: "✓", count: min(checked, 5))
        if unchecked > 0 { result += String(repeating: "○", count: min(unchecked, 5 - checked)) }
        return result
    }

    private func formatExpenseSubtitle(_ expense: ExpenseRecord) -> String {
        var parts = [expense.category]
        if let merchant = expense.merchant { parts.append(merchant) }
        parts.append(DateFormatter.shortTime.string(from: expense.createdAt))
        return parts.joined(separator: " · ")
    }

    private func formatTodoSubtitle(_ todo: TodoRecord) -> String {
        var parts = ["待办"]
        if let remindAt = todo.remindAt { parts.append("提醒 \(DateFormatter.shortTime.string(from: remindAt))") }
        return parts.joined(separator: " · ")
    }

    private func formatNumber(_ value: Double) -> String {
        if value >= 10000 { return String(format: "%.1f万", value / 10000) }
        return String(format: "%.0f", value)
    }
}

struct RecordItem: Identifiable {
    let id: String; let emoji: String; let title: String; let subtitle: String
    let trailing: String; let trailingColor: String; let type: RecordType; let createdAt: Date
    enum RecordType { case expense, habit, todo }
}

extension DateFormatter {
    static let shortTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let shortDate: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d"; return f }()
}
