import Foundation
import GRDB

/// 记账记录（本地 SQLite 模型）
struct ExpenseRecord: Codable, Sendable, Identifiable {
    var id: String
    var userId: String
    var type: String           // expense / income / transfer
    var amountCents: Int       // 金额（分），¥35.50 → 3550
    var currency: String       // 币种，默认 CNY
    var category: String       // 餐饮、交通、购物 等
    var merchant: String?
    var note: String?
    var recordDate: Date
    var source: String         // voice / text / ocr
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId, type, amountCents, currency, category
        case merchant, note, recordDate, source, isDeleted
        case createdAt, updatedAt, deletedAt
    }
}

// MARK: - GRDB 协议

extension ExpenseRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "expense_record"
}

// MARK: - 便捷方法

extension ExpenseRecord {
    /// 金额格式化显示
    var displayAmount: String {
        let amount = Double(amountCents) / 100.0
        return String(format: "¥%.2f", amount)
    }

    /// 带符号的金额显示
    var signedDisplayAmount: String {
        let amount = Double(amountCents) / 100.0
        let prefix = type == "expense" ? "-" : "+"
        return "\(prefix)\(String(format: "%.2f", amount))"
    }

    /// 创建一条新记账记录
    static func create(
        userId: String = "local",
        type: String = "expense",
        amountCents: Int,
        category: String,
        note: String? = nil,
        merchant: String? = nil,
        source: String = "text"
    ) -> ExpenseRecord {
        ExpenseRecord(
            id: UUID().uuidString,
            userId: userId,
            type: type,
            amountCents: amountCents,
            currency: "CNY",
            category: category,
            merchant: merchant,
            note: note,
            recordDate: Date(),
            source: source,
            isDeleted: false,
            createdAt: Date(),
            updatedAt: nil,
            deletedAt: nil
        )
    }
}
