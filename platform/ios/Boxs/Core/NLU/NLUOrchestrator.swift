import Foundation
import os.log

/// NLU 调度器
/// 规则引擎 → 多意图引擎 → LLM 路由
/// 置信度 ≥ 0.85 使用规则引擎，< 0.85 降级 LLM
actor NLUOrchestrator {
    private let singleEngine = SingleIntentRuleEngine()
    private let multiEngine = MultiIntentEngine()
    private let scorer = ConfidenceScorer()
    private let llmClient = LLMClient()
    private let logger = Logger(subsystem: "com.boxs.app", category: "NLU")

    /// 处理用户输入，返回 NLU 结果
    func process(_ text: String) async throws -> NLUResult {
        logger.info("NLU 处理: \(text)")

        // 第一步：尝试单意图规则匹配
        if let result = singleEngine.tryMatch(text) {
            let scored = scorer.score(result)
            if scorer.shouldUseRuleEngine(confidence: scored) {
                logger.info("单意图规则命中 (置信度: \(String(format: "%.2f", scored)))")
                return adjustConfidence(result, newConfidence: scored)
            }
        }

        // 第二步：尝试多意图规则匹配
        if let result = multiEngine.tryMatch(text) {
            let scored = scorer.score(result)
            if scorer.shouldUseRuleEngine(confidence: scored) {
                logger.info("多意图规则命中 (置信度: \(String(format: "%.2f", scored)))")
                return adjustConfidence(result, newConfidence: scored)
            }
        }

        // 第三步：降级到 LLM
        logger.info("规则引擎未命中，降级到 LLM")
        do {
            return try await llmClient.classify(text: text)
        } catch {
            logger.error("LLM 调用失败: \(error.localizedDescription)")
            // LLM 也失败时，返回兜底结果
            return NLUResult(
                intent: "unknown",
                confidence: 0.0,
                rawText: text,
                source: "rule",
                amount: nil,
                category: nil,
                note: nil,
                merchant: nil,
                habitName: nil,
                habitValue: nil,
                content: text,
                remindAt: nil,
                reply: nil,
                items: nil
            )
        }
    }

    /// 纯规则引擎处理（离线可用）
    func processOffline(_ text: String) -> NLUResult? {
        if let result = singleEngine.tryMatch(text) {
            let scored = scorer.score(result)
            if scorer.shouldUseRuleEngine(confidence: scored) {
                return adjustConfidence(result, newConfidence: scored)
            }
        }

        if let result = multiEngine.tryMatch(text) {
            let scored = scorer.score(result)
            if scorer.shouldUseRuleEngine(confidence: scored) {
                return adjustConfidence(result, newConfidence: scored)
            }
        }

        return nil
    }

    private func adjustConfidence(_ result: NLUResult, newConfidence: Double) -> NLUResult {
        NLUResult(
            intent: result.intent,
            confidence: newConfidence,
            rawText: result.rawText,
            source: result.source,
            amount: result.amount,
            category: result.category,
            note: result.note,
            merchant: result.merchant,
            habitName: result.habitName,
            habitValue: result.habitValue,
            content: result.content,
            remindAt: result.remindAt,
            reply: result.reply,
            items: result.items
        )
    }
}
