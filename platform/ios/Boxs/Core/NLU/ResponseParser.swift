import Foundation

/// LLM 响应解析器 — 将 JSON 字符串解析为 NLUResult
struct ResponseParser {

    /// 解析 LLM 返回的 JSON 字符串为 NLUResult
    func parse(jsonString: String, rawText: String) -> NLUResult? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        // 先尝试标准响应格式
        if let response = try? JSONDecoder.boxs.decode(NLUClassifyResponse.self, from: data) {
            return NLUResult(
                intent: response.intent,
                confidence: response.confidence,
                rawText: rawText,
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
                        rawText: rawText,
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

        // 尝试从 markdown 代码块中提取 JSON
        if let extracted = extractJSON(from: jsonString) {
            return parse(jsonString: extracted, rawText: rawText)
        }

        return nil
    }

    /// 从 markdown 代码块中提取 JSON
    private func extractJSON(from text: String) -> String? {
        // 匹配 ```json ... ```
        let pattern = "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
