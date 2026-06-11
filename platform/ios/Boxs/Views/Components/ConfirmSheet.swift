import SwiftUI

/// NLU 确认弹窗 — 显示解析结果，可编辑后确认
struct ConfirmSheet: View {
    @Bindable var viewModel: NLUViewModel
    @State private var editedNote: String = ""
    @State private var editedAmount: String = ""
    @State private var editedCategory: String = ""

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(spacing: S.section) {
            // 标题
            Text("已识别")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, S.page)

            // 识别结果卡片
            resultCard

            // 来源标识
            if let source = viewModel.nluResult?.source {
                HStack(spacing: 4) {
                    Image(systemName: source == "voice" ? "mic.fill" : "textformat")
                    Text(source == "voice" ? "语音识别" : "规则引擎")
                }
                .font(.system(size: 10))
                .foregroundStyle(c.textSecondary)
                .padding(.horizontal, S.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 错误提示
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(c.expense)
                    .padding(.horizontal, S.page)
            }

            // 按钮
            HStack(spacing: S.row) {
                Button(action: { viewModel.dismiss() }) {
                    Text("取消")
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))

                Spacer()

                Button(action: { Task { await viewModel.confirmAndSave() } }) {
                    HStack(spacing: 4) {
                        Text("确认")
                        Image(systemName: "checkmark")
                    }
                }
                .buttonStyle(ActionButtonStyle(kind: .primary))
            }
            .padding(.horizontal, S.page)
            .padding(.bottom, 20)
        }
        .padding(.top, 4)
        .onAppear {
            setupInitialValues()
        }
    }

    // MARK: - 结果卡片

    @ViewBuilder
    private var resultCard: some View {
        if let result = viewModel.nluResult {
            VStack(alignment: .leading, spacing: 8) {
                switch result.intent {
                case "expense":
                    expenseCard(result)
                case "habit_checkin":
                    habitCheckinCard(result)
                case "todo_add":
                    todoCard(result)
                case "multiple":
                    multipleCard(result)
                default:
                    unknownCard(result)
                }
            }
            .padding(S.card)
            .background(c.background)
            .clipShape(RoundedRectangle(cornerRadius: R.card))
            .padding(.horizontal, S.page)
        }
    }

    // MARK: - 各意图卡片

    private func expenseCard(_ result: NLUResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let category = ExpenseCategory(rawValue: result.category ?? "其他") ?? .other
                Text(category.emoji)
                    .font(.system(size: Sz.emoji))
                Text(result.note ?? result.category ?? "记账")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                Spacer()
                Text(String(format: "-¥%.2f", result.amount ?? 0))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(c.expense)
            }

            HStack(spacing: S.item) {
                TagView(text: result.category ?? "其他", isSelected: true)
                if let source = viewModel.nluResult?.source {
                    TagView(text: source == "voice" ? "🎤 语音" : "✏️ 文字", isSelected: false)
                }
            }
        }
    }

    private func habitCheckinCard(_ result: NLUResult) -> some View {
        HStack {
            Text("✓")
                .font(.system(size: Sz.emoji, weight: .bold))
                .foregroundStyle(c.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.habitName ?? "习惯打卡")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                if let value = result.habitValue {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                }
            }
            Spacer()
        }
    }

    private func todoCard(_ result: NLUResult) -> some View {
        HStack {
            Text("📝")
                .font(.system(size: Sz.emoji))
            Text(result.content ?? "待办")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textPrimary)
            Spacer()
        }
    }

    private func multipleCard(_ result: NLUResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((result.items ?? []).enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(intentEmoji(item.intent))
                        .font(.system(size: 14))
                    Text(item.note ?? item.content ?? item.habitName ?? item.intent)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textPrimary)
                    Spacer()
                    if let amount = item.amount {
                        Text(String(format: "¥%.0f", amount))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(c.expense)
                    }
                }
            }
        }
    }

    private func unknownCard(_ result: NLUResult) -> some View {
        Text(result.rawText)
            .font(.system(size: 14))
            .foregroundStyle(c.textSecondary)
    }

    // MARK: - 辅助

    private func intentEmoji(_ intent: String) -> String {
        switch intent {
        case "expense": return ExpenseCategory.other.emoji
        case "habit_checkin": return "✓"
        case "todo_add": return "📝"
        default: return "❓"
        }
    }

    private func setupInitialValues() {
        guard let result = viewModel.nluResult else { return }
        editedNote = result.note ?? ""
        if let amount = result.amount {
            editedAmount = String(format: "%.2f", amount)
        }
        editedCategory = result.category ?? "其他"
    }
}
