import Foundation
import Observation
import GRDB

/// 习惯打卡 ViewModel
@Observable
@MainActor
final class HabitViewModel {
    var habits: [Habit] = []
    var calendarRecords: [HabitCalendarDay] = []
    var selectedHabitId: String?
    var isLoading = false

    struct HabitCalendarDay: Identifiable {
        let id = UUID()
        let date: Date
        let isChecked: Bool
        let value: String?
    }

    func loadHabits() {
        isLoading = true
        Task {
            defer { isLoading = false }

            // 从后端同步习惯数据
            if TokenManager.shared.isLoggedIn {
                await SyncService.shared.syncHabits()
            }

            do {
                let db = try AppDatabase.shared.getDB()
                let definitions: [HabitDefinition] = try await db.read { db in
                    try HabitDefinition
                        .filter(Column("isActive") == true)
                        .order(Column("sortOrder").asc)
                        .fetchAll(db)
                }
                let today = Calendar.current.startOfDay(for: Date())
                let todayRecords: [HabitRecord] = try await db.read { db in
                    try HabitRecord
                        .filter(Column("recordDate") >= today)
                        .fetchAll(db)
                }
                self.habits = definitions.map { def in
                    let checked = todayRecords.contains { $0.habitId == def.id }
                    return Habit.from(def, todayChecked: checked)
                }
            } catch {
                print("加载习惯列表失败: \(error)")
            }
        }
    }

    func checkin(habitId: String, value: String? = nil) {
        Task {
            do {
                let db = try AppDatabase.shared.getDB()
                var record = HabitRecord.create(habitId: habitId, value: value)
                try db.write { db in
                    try record.save(db)
                }
                Task { await SyncService.shared.pushHabitCheckin(record) }
                loadHabits()
            } catch {
                print("打卡失败: \(error)")
            }
        }
    }

    func loadCalendar(habitId: String, month: Date) {
        Task {
            do {
                let db = try AppDatabase.shared.getDB()
                let calendar = Calendar.current
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
                let range = calendar.range(of: .day, in: .month, for: month)!

                let records: [HabitRecord] = try await db.read { db in
                    try HabitRecord
                        .filter(Column("habitId") == habitId)
                        .filter(Column("recordDate") >= startOfMonth)
                        .fetchAll(db)
                }

                self.calendarRecords = range.map { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
                    let record = records.first { calendar.isDate($0.recordDate, inSameDayAs: date) }
                    return HabitCalendarDay(
                        date: date,
                        isChecked: record != nil,
                        value: record?.value
                    )
                }
            } catch {
                print("加载日历失败: \(error)")
            }
        }
    }
}
