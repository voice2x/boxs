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

        // 从后端同步数据
        if TokenManager.shared.isLoggedIn {
            await SyncEngine.shared.sync(force: true)
        }

        do {
            let db = try AppDatabase.shared.getDB()
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

            // 一次读取聚合四项统计(避免多次 db.read)
            let stats = try await db.read { db in
                let todos = try TodoRecord
                    .filter(Column("isDeleted") == false)
                    .filter(Column("createdAt") >= startOfDay)
                    .fetchAll(db)
                let expenses = try ExpenseRecord
                    .filter(Column("isDeleted") == false)
                    .filter(Column("type") == "expense")
                    .filter(Column("recordDate") >= startOfMonth)
                    .fetchAll(db)
                let habits = try HabitDefinition.filter(Column("isActive") == true).fetchAll(db)
                let habitRecords = try HabitRecord.filter(Column("recordDate") >= startOfDay).fetchAll(db)
                return (todoCount: todos.count,
                        todoDone: todos.filter(\.isCompleted).count,
                        expenseCents: expenses.reduce(0) { $0 + $1.amountCents },
                        habitTotal: habits.count,
                        habitChecked: habitRecords.count)
            }

            self.todayTodoCount = stats.todoCount
            self.todayTodoCompleted = stats.todoDone
            self.monthExpenseCents = stats.expenseCents
            self.todayHabitTotal = stats.habitTotal
            self.todayHabitChecked = stats.habitChecked

            try await loadRecentRecords(db: db)
        } catch {
            logger.error("加载主页数据失败: \(error)")
        }
    }

    private func loadRecentRecords(db: DatabaseQueue) async throws {
        // 一次读取:记账/打卡/待办 + 全部习惯定义(批量建名表,消除 N+1)
        let fetched = try await db.read { db -> ([ExpenseRecord], [HabitRecord], [TodoRecord], [String: String]) in
            let expenses = try ExpenseRecord
                .filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc)
                .limit(10)
                .fetchAll(db)
            let habitRecords = try HabitRecord.order(Column("createdAt").desc).limit(5).fetchAll(db)
            let todos = try TodoRecord
                .filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc)
                .limit(5)
                .fetchAll(db)
            let habits = try HabitDefinition.fetchAll(db)
            let nameMap = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
            return (expenses, habitRecords, todos, nameMap)
        }
        let (expenses, habitRecords, todos, habitNames) = fetched

        var items: [RecordItem] = []
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
        for record in habitRecords {
            items.append(RecordItem(
                id: record.id, emoji: "✓", title: habitNames[record.habitId] ?? "习惯",
                subtitle: record.value ?? "已打卡", trailing: "✓",
                trailingColor: "primary", type: .habit, createdAt: record.createdAt
            ))
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
