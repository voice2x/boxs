import SwiftUI

/// 习惯打卡日历页
struct HabitCalendarPage: View {
    @State private var viewModel = HabitViewModel()
    @State private var selectedMonth = Date()

    @Environment(\.appColors) private var c

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 0) {
            // 月份选择
            monthSelector

            AppDivider()

            // 习惯列表
            habitList

            AppDivider()

            // 日历热力图
            calendarGrid
        }
        .background(c.background)
        .navigationTitle("打卡")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadHabits()
            if let first = viewModel.habits.first {
                viewModel.selectedHabitId = first.id
                await viewModel.loadCalendar(habitId: first.id, month: selectedMonth)
            }
        }
    }

    // MARK: - 月份选择

    private var monthSelector: some View {
        HStack {
            Button(action: { changeMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(c.textSecondary)
            }

            Spacer()

            Text(monthTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textPrimary)

            Spacer()

            Button(action: { changeMonth(1) }) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(c.textSecondary)
            }
        }
        .padding(.horizontal, S.page)
        .frame(height: Sz.compactRow)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: selectedMonth)
    }

    private func changeMonth(_ offset: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = newMonth
            if let habitId = viewModel.selectedHabitId {
                Task { await viewModel.loadCalendar(habitId: habitId, month: newMonth) }
            }
        }
    }

    // MARK: - 习惯列表

    private var habitList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: S.row) {
                ForEach(viewModel.habits) { habit in
                    Button(action: {
                        viewModel.selectedHabitId = habit.id
                        Task { await viewModel.loadCalendar(habitId: habit.id, month: selectedMonth) }
                    }) {
                        HStack(spacing: 4) {
                            Text(habit.icon ?? "🏃")
                            Text(habit.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(viewModel.selectedHabitId == habit.id ? .white : c.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.selectedHabitId == habit.id ? c.primary : c.surface
                        )
                        .clipShape(RoundedRectangle(cornerRadius: R.tag))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, S.page)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 日历

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            // 星期标题
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(c.textHint)
                        .frame(height: 20)
                }
            }

            // 日期格子
            LazyVGrid(columns: columns, spacing: 4) {
                // 前置空格
                let firstWeekday = Calendar.current.component(.weekday, from: startOfMonth) - 1
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Color.clear.frame(height: 32)
                }

                // 日期
                ForEach(viewModel.calendarRecords) { day in
                    let cal = Calendar.current
                    let dayNum = cal.component(.day, from: day.date)
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.isChecked ? c.primary.opacity(0.2) : Color.clear)
                            .frame(height: 32)

                        Text("\(dayNum)")
                            .font(.system(size: 12, weight: day.isChecked ? .semibold : .regular))
                            .foregroundStyle(day.isChecked ? c.primary : c.textPrimary)
                    }
                }
            }
        }
        .padding(S.page)
    }

    private var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedMonth))!
    }
}
