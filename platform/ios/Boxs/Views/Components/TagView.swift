import SwiftUI

/// 自定义标签 — 22dp 高度
struct TagView: View {
    let text: String
    let isSelected: Bool

    @Environment(\.appColors) private var c

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isSelected ? c.primary : c.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, S.tag)
            .background(
                isSelected
                    ? c.primary.opacity(0.15)
                    : c.border
            )
            .clipShape(RoundedRectangle(cornerRadius: R.tag))
            .frame(height: Sz.tag)
    }
}
