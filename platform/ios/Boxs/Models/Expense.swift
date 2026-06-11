import Foundation

/// 记账领域模型（ViewModel 层使用）
struct Expense: Identifiable {
    let id: String
    let type: String           // expense / income / transfer
    let amountCents: Int
    let category: String
    let merchant: String?
    let note: String?
    let recordDate: Date
    let source: String
    let createdAt: Date

    var displayAmount: String {
        let amount = Double(amountCents) / 100.0
        return String(format: "%.2f", amount)
    }

    var signedDisplayAmount: String {
        let amount = Double(amountCents) / 100.0
        let prefix = type == "expense" ? "-" : "+"
        return "\(prefix)\(String(format: "%.2f", amount))"
    }

    /// 从数据库模型转换
    static func from(_ record: ExpenseRecord) -> Expense {
        Expense(
            id: record.id,
            type: record.type,
            amountCents: record.amountCents,
            category: record.category,
            merchant: record.merchant,
            note: record.note,
            recordDate: record.recordDate,
            source: record.source,
            createdAt: record.createdAt
        )
    }
}
