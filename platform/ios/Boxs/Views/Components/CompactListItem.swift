import SwiftUI

/// 紧凑列表项 — 44pt 行高记录行
struct CompactListItem: View {
    let emoji: String
    let title: String
    let subtitle: String?
    let trailing: String?
    let trailingColor: String?
    let onTap: (() -> Void)?

    @Environment(\.appColors) private var c

    init(
        emoji: String,
        title: String,
        subtitle: String? = nil,
        trailing: String? = nil,
        trailingColor: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingColor = trailingColor
        self.onTap = onTap
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .center, spacing: 10) {
                // emoji
                Text(emoji)
                    .font(.system(size: Sz.emoji))

                // 主内容
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textPrimary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 右侧
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(resolveColor(trailingColor))
                }
            }
            .padding(.horizontal, S.page)
            .padding(.vertical, 10)
            .frame(minHeight: Sz.listItem, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    private func resolveColor(_ name: String?) -> Color {
        guard let name else { return c.textPrimary }
        switch name {
        case "expense": return c.expense
        case "income": return c.income
        case "primary": return c.primary
        case "hint": return c.textHint
        default: return c.textPrimary
        }
    }
}
