import SwiftUI

/// 紧凑分割线 — 左侧留出 emoji 空间
struct AppDivider: View {
    @Environment(\.appColors) private var c

    var body: some View {
        Rectangle()
            .fill(c.border)
            .frame(height: 0.5)
            .padding(.leading, S.page + Sz.emoji + 10) // 左偏到 emoji 右侧
            .padding(.trailing, S.page)
    }
}
