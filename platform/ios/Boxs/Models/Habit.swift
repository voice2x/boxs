import Foundation

/// 习惯领域模型
struct Habit: Identifiable {
    let id: String
    let name: String
    let icon: String?
    let unit: String?
    let goalValue: String?
    let isActive: Bool
    let todayChecked: Bool
    let streak: Int            // 连续打卡天数

    static func from(_ definition: HabitDefinition, todayChecked: Bool = false, streak: Int = 0) -> Habit {
        Habit(
            id: definition.id,
            name: definition.name,
            icon: definition.icon,
            unit: definition.unit,
            goalValue: definition.goalValue,
            isActive: definition.isActive,
            todayChecked: todayChecked,
            streak: streak
        )
    }
}
