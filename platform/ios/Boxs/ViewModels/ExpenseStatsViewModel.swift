import Foundation
import Observation
import GRDB

/// 记账统计 ViewModel
@Observable
@MainActor
final class ExpenseStatsViewModel {
    var monthExpenseCents: Int = 0
    var monthIncomeCents: Int = 0
    var categoryBreakdown: [CategoryStat] = []
    var dailyTrend: [DailyExpense] = []
    var selectedPeriod: Period = .month
    var isLoading = false

    enum Period: String, CaseIterable {
        case day = "日"
        case week = "周"
        case month = "月"
    }

    struct CategoryStat: Identifiable {
        let id = UUID()
        let category: String
        let emoji: String
        let amountCents: Int
        let percentage: Double
    }

    struct DailyExpense: Identifiable {
        let id = UUID()
        let day: Int
        let amountCents: Int
    }

    func loadData() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let db = try AppDatabase.shared.getDB()
                let calendar = Calendar.current
                let now = Date()
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

                let expenses: [ExpenseRecord] = try db.read { db in
                    try ExpenseRecord
                        .filter(Column("isDeleted") == false)
                        .filter(Column("recordDate") >= startOfMonth)
                        .fetchAll(db)
                }

                // 总支出/收入
                self.monthExpenseCents = expenses
                    .filter { $0.type == "expense" }
                    .reduce(0) { $0 + $1.amountCents }
                self.monthIncomeCents = expenses
                    .filter { $0.type == "income" }
                    .reduce(0) { $0 + $1.amountCents }

                // 分类统计
                let expenseOnly = expenses.filter { $0.type == "expense" }
                let total = self.monthExpenseCents
                let grouped = Dictionary(grouping: expenseOnly, by: \.category)
                self.categoryBreakdown = grouped.map { cat, records in
                    let sum = records.reduce(0) { $0 + $1.amountCents }
                    let emoji = ExpenseCategory(rawValue: cat)?.emoji ?? "📦"
                    return CategoryStat(
                        category: cat,
                        emoji: emoji,
                        amountCents: sum,
                        percentage: total > 0 ? Double(sum) / Double(total) : 0
                    )
                }.sorted { $0.amountCents > $1.amountCents }

                // 每日趋势
                let dailyGrouped = Dictionary(grouping: expenseOnly) { record in
                    calendar.component(.day, from: record.recordDate)
                }
                self.dailyTrend = dailyGrouped.map { day, records in
                    DailyExpense(day: day, amountCents: records.reduce(0) { $0 + $1.amountCents })
                }.sorted { $0.day < $1.day }
            } catch {
                print("加载统计数据失败: \(error)")
            }
        }
    }

    var monthExpenseDisplay: String {
        "¥\(String(format: "%.0f", Double(monthExpenseCents) / 100.0))"
    }

    var monthIncomeDisplay: String {
        "¥\(String(format: "%.0f", Double(monthIncomeCents) / 100.0))"
    }
}
