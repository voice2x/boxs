import SwiftUI

/// 自定义按钮样式
struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case text
    }

    let kind: Kind
    @Environment(\.appColors) private var c

    func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .primary:
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: Sz.button)
                .background(c.primary)
                .clipShape(RoundedRectangle(cornerRadius: R.button))

        case .secondary:
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: Sz.button)
                .overlay(
                    RoundedRectangle(cornerRadius: R.button)
                        .stroke(c.primary, lineWidth: 1)
                )

        case .text:
            HStack(spacing: 2) {
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(c.info)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(c.info)
            }
        }
    }
}
