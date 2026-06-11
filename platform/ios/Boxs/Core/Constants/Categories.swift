import Foundation

/// 消费分类枚举（12 大类 + emoji + 关键词）
enum ExpenseCategory: String, CaseIterable, Sendable {
    case food = "餐饮"
    case transport = "交通"
    case shopping = "购物"
    case entertainment = "娱乐"
    case medical = "医疗"
    case education = "教育"
    case housing = "居住"
    case clothing = "服饰"
    case digital = "数码"
    case social = "社交"
    case pet = "宠物"
    case other = "其他"

    var emoji: String {
        switch self {
        case .food:          return "🍜"
        case .transport:     return "🚕"
        case .shopping:      return "🛒"
        case .entertainment: return "🎮"
        case .medical:       return "🏥"
        case .education:     return "📚"
        case .housing:       return "🏠"
        case .clothing:      return "👕"
        case .digital:       return "📱"
        case .social:        return "🍻"
        case .pet:           return "🐾"
        case .other:         return "📦"
        }
    }

    /// 用于规则引擎匹配的关键词列表
    var keywords: [String] {
        switch self {
        case .food:
            return ["早", "午", "晚", "饭", "餐", "吃", "面", "粉", "外卖", "奶茶", "咖啡",
                    "火锅", "烧烤", "快餐", "小吃", "水果", "零食", "饮料", "蛋糕", "面包",
                    "米线", "麻辣烫", "沙县", "麦当劳", "肯德基", "星巴克", "瑞幸"]
        case .transport:
            return ["打车", "地铁", "公交", "出租", "高铁", "火车", "飞机", "骑车", "滴滴",
                    "共享单车", "加油", "停车", "过路费", "机票", "车票"]
        case .shopping:
            return ["超市", "商场", "网购", "淘宝", "京东", "拼多多", "日用品", "家电",
                    "家居", "零食", "盒马", "山姆", "costco"]
        case .entertainment:
            return ["电影", "游戏", "唱歌", "KTV", "酒吧", "旅游", "门票", "演出", "会员"]
        case .medical:
            return ["药", "医院", "看病", "体检", "挂号", "牙", "眼", "中医"]
        case .education:
            return ["书", "课", "培训", "学费", "考试", "网课"]
        case .housing:
            return ["房租", "水费", "电费", "燃气", "物业", "宽带", "网费", "维修"]
        case .clothing:
            return ["衣服", "鞋", "包", "裤子", "外套", "T恤", "裙子", "优衣库", "zara"]
        case .digital:
            return ["手机", "电脑", "耳机", "充电", "数码", "软件", "app", "订阅"]
        case .social:
            return ["红包", "礼物", "请客", "份子钱", "随礼"]
        case .pet:
            return ["猫粮", "狗粮", "宠物", "猫砂", "疫苗"]
        case .other:
            return []
        }
    }

    /// 根据备注文字猜测分类
    static func guess(from note: String?) -> ExpenseCategory {
        guard let note, !note.isEmpty else { return .other }
        let lowered = note.lowercased()

        for category in ExpenseCategory.allCases {
            if category.keywords.contains(where: { lowered.contains($0.lowercased()) }) {
                return category
            }
        }
        return .other
    }
}
