import SwiftUI

// MARK: - EnvironmentKey 注入

struct AppColorsKey: EnvironmentKey {
    static let defaultValue: AppColors = .light
}

extension EnvironmentValues {
    var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

// MARK: - 主题色定义

struct AppColors {
    let background: Color
    let surface: Color
    let border: Color
    let primary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textHint: Color
    let income: Color
    let expense: Color
    let info: Color
    let warning: Color

    // MARK: 亮色

    static let light = AppColors(
        background:    Color(hex: "F8F7F4"),
        surface:       Color(hex: "FFFFFF"),
        border:        Color(hex: "EFEDE8"),
        primary:       Color(hex: "D4573E"),
        textPrimary:   Color(hex: "1D1D1B"),
        textSecondary: Color(hex: "6E6E6A"),
        textHint:      Color(hex: "A3A39E"),
        income:        Color(hex: "3B9B6E"),
        expense:       Color(hex: "C94C4C"),
        info:          Color(hex: "4A8FC7"),
        warning:       Color(hex: "C4883A")
    )

    // MARK: 暗色

    static let dark = AppColors(
        background:    Color(hex: "141413"),
        surface:       Color(hex: "1E1E1C"),
        border:        Color(hex: "333331"),
        primary:       Color(hex: "E0725C"),
        textPrimary:   Color(hex: "EAE9E5"),
        textSecondary: Color(hex: "989893"),
        textHint:      Color(hex: "626260"),
        income:        Color(hex: "5DB88A"),
        expense:       Color(hex: "E07A6A"),
        info:          Color(hex: "6DA8D6"),
        warning:       Color(hex: "D9A25A")
    )
}

// MARK: - Color hex 便捷初始化

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
