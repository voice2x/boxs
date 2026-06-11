import Foundation

/// NLU 意图识别结果
struct NLUResult: Codable, Sendable {
    let intent: String          // expense, habit_checkin, todo_add, query, ...
    let confidence: Double
    let rawText: String
    let source: String          // "rule" | "llm"

    var amount: Double?
    var category: String?
    var note: String?
    var merchant: String?
    var habitName: String?
    var habitValue: String?
    var content: String?
    var remindAt: Date?
    var reply: String?
    var items: [NLUResult]?     // 多意图

    /// 是否为多意图
    var isMultiple: Bool { items != nil && !items!.isEmpty }

    /// 规则引擎结果
    static func ruleResult(
        intent: String,
        rawText: String,
        confidence: Double,
        amount: Double? = nil,
        category: String? = nil,
        note: String? = nil,
        habitName: String? = nil,
        habitValue: String? = nil,
        content: String? = nil,
        items: [NLUResult]? = nil
    ) -> NLUResult {
        NLUResult(
            intent: intent,
            confidence: confidence,
            rawText: rawText,
            source: "rule",
            amount: amount,
            category: category,
            note: note,
            merchant: nil,
            habitName: habitName,
            habitValue: habitValue,
            content: content,
            remindAt: nil,
            reply: nil,
            items: items
        )
    }

    /// LLM 结果
    static func llmResult(
        intent: String,
        rawText: String,
        confidence: Double = 0.95,
        amount: Double? = nil,
        category: String? = nil,
        note: String? = nil,
        merchant: String? = nil,
        habitName: String? = nil,
        habitValue: String? = nil,
        content: String? = nil,
        remindAt: Date? = nil,
        reply: String? = nil,
        items: [NLUResult]? = nil
    ) -> NLUResult {
        NLUResult(
            intent: intent,
            confidence: confidence,
            rawText: rawText,
            source: "llm",
            amount: amount,
            category: category,
            note: note,
            merchant: merchant,
            habitName: habitName,
            habitValue: habitValue,
            content: content,
            remindAt: remindAt,
            reply: reply,
            items: items
        )
    }
}
