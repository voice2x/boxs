import Foundation

/// 多意图规则引擎
/// 拆完之后，每个子句走单意图规则。任一段失败则整体降级给 LLM
final class MultiIntentEngine {

    private let splitter = SentenceSplitter()
    private let singleEngine = SingleIntentRuleEngine()

    /// 尝试多意图匹配
    /// 返回 nil 表示不是多意图或某段匹配失败（应降级到 LLM）
    func tryMatch(_ text: String) -> NLUResult? {
        let segments = splitter.split(text)

        // 只有 1 段 → 不是多意图
        guard segments.count > 1 else { return nil }

        var items: [NLUResult] = []

        for seg in segments {
            guard let result = singleEngine.tryMatch(seg) else {
                // 某一段匹配失败 → 整体降级到 LLM
                return nil
            }
            items.append(result)
        }

        // 置信度 = 所有序列的最低值（短板效应）
        let minConfidence = items.map(\.confidence).min() ?? 0

        return .ruleResult(
            intent: "multiple",
            rawText: text,
            confidence: minConfidence,
            items: items
        )
    }
}
