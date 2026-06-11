import SwiftUI

/// 记账统计页 — 分类排行、趋势图、月/周/日切换
struct ExpenseStatsPage: View {
    @State private var viewModel = ExpenseStatsViewModel()

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            // 总览
            overviewSection

            AppDivider()

            // 月份切换
            periodSelector

            AppDivider()

            // 分类排行
            categoryList

            AppDivider()

            // 每日趋势
            dailyTrend
        }
        .background(c.background)
        .navigationTitle("记账统计")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - 总览

    private var overviewSection: some View {
        HStack(spacing: S.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text("支出")
                    .font(.system(size: 10))
                    .foregroundStyle(c.textSecondary)
                Text(viewModel.monthExpenseDisplay)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(c.expense)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("收入")
                    .font(.system(size: 10))
                    .foregroundStyle(c.textSecondary)
                Text(viewModel.monthIncomeDisplay)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(c.income)
            }

            Spacer()
        }
        .padding(S.page)
    }

    // MARK: - 周期选择

    private var periodSelector: some View {
        HStack(spacing: S.row) {
            ForEach(ExpenseStatsViewModel.Period.allCases, id: \.self) { period in
                Button(action: { viewModel.selectedPeriod = period }) {
                    Text(period.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.selectedPeriod == period ? .white : c.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.selectedPeriod == period ? c.primary : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: R.tag))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, S.page)
        .padding(.vertical, 8)
    }

    // MARK: - 分类排行

    private var categoryList: some View {
        VStack(spacing: 0) {
            Text("分类排行")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, S.page)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(viewModel.categoryBreakdown) { stat in
                HStack(spacing: 8) {
                    Text(stat.emoji)
                        .font(.system(size: 14))
                    Text(stat.category)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textPrimary)
                        .frame(width: 40, alignment: .leading)

                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(c.border)
                            Rectangle()
                                .fill(c.primary.opacity(0.6))
                                .frame(width: geo.size.width * CGFloat(stat.percentage))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())

                    Text(String(format: "%.0f%%", stat.percentage * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .frame(height: 28)
                .padding(.horizontal, S.page)
            }
        }
    }

    // MARK: - 每日趋势

    private var dailyTrend: some View {
        VStack(spacing: 8) {
            Text("日支出趋势")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.dailyTrend.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textHint)
                    .frame(height: 80)
            } else {
                Canvas { context, size in
                    let maxAmount = viewModel.dailyTrend.map(\.amountCents).max() ?? 1
                    let barWidth = size.width / CGFloat(viewModel.dailyTrend.count)

                    for (index, day) in viewModel.dailyTrend.enumerated() {
                        let barHeight = CGFloat(day.amountCents) / CGFloat(maxAmount) * (size.height - 20)
                        let rect = CGRect(
                            x: CGFloat(index) * barWidth + 2,
                            y: size.height - barHeight,
                            width: barWidth - 4,
                            height: barHeight
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 2),
                            with: .color(c.primary.opacity(0.6))
                        )
                    }
                }
                .frame(height: 80)
            }
        }
        .padding(S.page)
    }
}
