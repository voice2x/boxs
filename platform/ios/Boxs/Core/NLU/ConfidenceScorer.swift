import Foundation

/// 置信度打分器
/// 乘法因子模型：金额确信度 × 分类确信度 × 长句惩罚 × 指代惩罚
struct ConfidenceScorer {

    /// 置信度阈值：≥ 此值走规则引擎结果，< 此值降级 LLM
    static let threshold: Double = 0.85

    /// 对规则引擎结果进行二次置信度评估
    func score(_ result: NLUResult) -> Double {
        var confidence = result.confidence

        // 1. 金额确信度（有金额且 > 0，加分）
        if result.intent == "expense" {
            if let amount = result.amount, amount > 0 {
                // 金额合理范围（0.01 ~ 100000），确信度高
                if amount >= 0.01 && amount <= 100000 {
                    confidence *= 1.0
                } else {
                    // 异常金额，降低确信度
                    confidence *= 0.7
                }
            } else {
                // 记账意图无金额，降低确信度
                confidence *= 0.6
            }
        }

        // 2. 分类确信度（有明确分类，加分）
        if result.category != nil && result.category != "其他" {
            confidence *= 1.0
        } else if result.category == "其他" {
            confidence *= 0.9
        }

        // 3. 长句惩罚（输入越长，规则引擎越不可靠）
        let textLength = result.rawText.count
        if textLength > 20 {
            confidence *= 0.8
        } else if textLength > 10 {
            confidence *= 0.9
        }

        // 4. 指代词惩罚（包含"那个"、"上次"等指代词，降低确信度）
        let pronouns = ["那个", "上次", "昨天那个", "之前的", "刚才", "上一条"]
        for pronoun in pronouns {
            if result.rawText.contains(pronoun) {
                confidence *= 0.5
                break
            }
        }

        return min(confidence, 1.0)
    }

    /// 判断是否应该使用规则引擎结果
    func shouldUseRuleEngine(confidence: Double) -> Bool {
        confidence >= Self.threshold
    }
}
