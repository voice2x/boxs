import SwiftUI

/// 横向滑动概览卡片
struct OverviewCard: View {
    let emoji: String
    let title: String
    let mainValue: String
    let subtitle: String
    let progress: CGFloat?   // 0...1，可选进度条

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：emoji + 标题
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: Sz.emoji))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }

            // 第二行：主数据
            Text(mainValue)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .monospacedDigit()
                .lineLimit(1)

            // 第三行：辅助信息
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)

            // 第四行：进度条（可选）
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(c.border)
                        Rectangle()
                            .fill(c.primary)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
                .clipShape(Capsule())
            }
        }
        .padding(S.card)
        .frame(width: 120, height: 80, alignment: .leading)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: R.card))
    }
}
