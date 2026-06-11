import SwiftUI

/// 紧凑版字号体系
enum Typography {
    // 页面标题
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    // 区块标题
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    // 卡片主文字
    static let cardPrimary = Font.system(size: 14, weight: .medium)
    // 卡片次要文字
    static let cardSecondary = Font.system(size: 12, weight: .regular)
    // 标签/徽章
    static let badge = Font.system(size: 10, weight: .medium)
    // 金额（大）
    static let amountLarge = Font.system(size: 26, weight: .bold)
    // 金额（列表）
    static let amountList = Font.system(size: 15, weight: .semibold)
    // 金额整数部分
    static let amountInteger = Font.system(size: 20, weight: .bold)
    // 金额小数部分
    static let amountDecimal = Font.system(size: 14, weight: .regular)
}
