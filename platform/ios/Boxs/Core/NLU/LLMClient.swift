import Foundation
import os.log

/// LLM 客户端 — 调用后端 /api/nlu/classify
actor LLMClient {
    private let apiClient = APIClient.shared
    private let logger = Logger(subsystem: "com.boxs.app", category: "LLM")

    /// 调用后端 NLU 分类接口
    func classify(text: String) async throws -> NLUResult {
        logger.info("调用 LLM 分类: \(text)")

        let request = NLUClassifyRequest(text: text)
        let endpoint = Endpoint(method: .POST, path: "/api/nlu/classify")
        let response: NLUClassifyResponse = try await apiClient.request(endpoint, body: request)

        return NLUResult(
            intent: response.intent,
            confidence: response.confidence,
            rawText: text,
            source: "llm",
            amount: response.amount,
            category: response.category,
            note: response.note,
            merchant: response.merchant,
            habitName: response.habit_name,
            habitValue: response.habit_value,
            content: response.content,
            remindAt: response.remind_at,
            reply: response.reply,
            items: response.items?.map { item in
                NLUResult(
                    intent: item.intent,
                    confidence: item.confidence,
                    rawText: text,
                    source: "llm",
                    amount: item.amount,
                    category: item.category,
                    note: item.note,
                    merchant: item.merchant,
                    habitName: item.habit_name,
                    habitValue: item.habit_value,
                    content: item.content,
                    remindAt: nil,
                    reply: nil,
                    items: nil
                )
            }
        )
    }
}

// MARK: - 请求/响应类型

struct NLUClassifyRequest: Encodable {
    let text: String
}

struct NLUClassifyResponse: Decodable {
    let intent: String
    let confidence: Double
    let amount: Double?
    let category: String?
    let note: String?
    let merchant: String?
    let habit_name: String?
    let habit_value: String?
    let content: String?
    let remind_at: Date?
    let reply: String?
    let items: [NLUClassifyItem]?
}

struct NLUClassifyItem: Decodable {
    let intent: String
    let confidence: Double
    let amount: Double?
    let category: String?
    let note: String?
    let merchant: String?
    let habit_name: String?
    let habit_value: String?
    let content: String?
}
