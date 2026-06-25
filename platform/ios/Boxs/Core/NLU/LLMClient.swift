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

/// 容错日期解析：把 LLM 吐出的时间字符串尽力转成 `Date`，解析失败返回 `nil`
/// 而非抛错。
///
/// 背景：`JSONDecoder.boxs` 用 `.iso8601` 解码 `remind_at: Date?`。本地 LLM 常吐
/// 出非 ISO8601 格式（如 "2026-06-16 09:00"、"明天上午9点"），会让整个
/// `NLUClassifyResponse` 解码失败、整条意图回退成 unknown。这里改为先把
/// remind_at 当字符串取出，再用本解析器容错转换，避免单一坏字段拖垮整次响应解码。
enum LenientDateParser {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }

        // 1. ISO8601（含/不含毫秒）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }

        // 2. 常见绝对格式兜底（相对/中文表述如"明天上午9点"无法解析 → nil）
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let d = formatter.date(from: text) { return d }
        }
        return nil
    }
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

    private enum CodingKeys: String, CodingKey {
        case intent, confidence, amount, category, note, merchant
        case habit_name, habit_value, content, remind_at, reply, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent = try c.decode(String.self, forKey: .intent)
        // confidence/amount 容错：本地 LLM 偶尔把数值当字符串吐（如 "0.9"、"35"），
        // 直接 decode(Double) 会抛错拖垮整条解码。这里数字优先、字符串兜底，
        // 坏值降级（confidence 取默认 0.9，amount 取 nil）。
        confidence = Self.lenientDouble(c, forKey: .confidence) ?? 0.9
        amount = Self.lenientDouble(c, forKey: .amount)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        habit_name = try c.decodeIfPresent(String.self, forKey: .habit_name)
        habit_value = try c.decodeIfPresent(String.self, forKey: .habit_value)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        // remind_at 容错：当字符串取（非字符串/对象也降级为 nil），再尽力解析成 Date。
        // 关键是不让 remind_at 的坏值抛错、拖垮整条 NLUClassifyResponse 的解码。
        let remindRaw = try? c.decodeIfPresent(String.self, forKey: .remind_at)
        remind_at = LenientDateParser.parse(remindRaw)
        reply = try c.decodeIfPresent(String.self, forKey: .reply)
        items = try c.decodeIfPresent([NLUClassifyItem].self, forKey: .items)
    }

    /// 容错读取 Double：数字优先；失败则尝试数字字符串（如 "35"、"0.9"）。
    private static func lenientDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let n = try? container.decode(Double.self, forKey: key) { return n }
        if let s = try? container.decode(String.self, forKey: key),
           let parsed = Double(s) { return parsed }
        return nil
    }
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
