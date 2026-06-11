import Testing
import Foundation
@testable import Boxs

@Suite("置信度打分测试")
struct ConfidenceScorerTests {
    let scorer = ConfidenceScorer()

    @Test("高置信度结果应该通过阈值")
    func testHighConfidence() {
        let result = NLUResult.ruleResult(
            intent: "expense",
            rawText: "午饭35",
            confidence: 0.90,
            amount: 35.0,
            category: "餐饮",
            note: "午饭"
        )
        let scored = scorer.score(result)
        #expect(scorer.shouldUseRuleEngine(confidence: scored))
    }

    @Test("含指代词应降低置信度")
    func testPronounPenalty() {
        let result = NLUResult.ruleResult(
            intent: "expense",
            rawText: "昨天那个35",
            confidence: 0.90,
            amount: 35.0,
            category: "其他"
        )
        let scored = scorer.score(result)
        #expect(scored < 0.85)
    }

    @Test("长句应降低置信度")
    func testLongTextPenalty() {
        let result = NLUResult.ruleResult(
            intent: "expense",
            rawText: "今天中午在公司楼下沙县小吃吃了一碗拌面和一个卤蛋",
            confidence: 0.90,
            amount: 35.0,
            category: "餐饮"
        )
        let scored = scorer.score(result)
        #expect(scored < 0.90)
    }

    @Test("阈值应为 0.85")
    func testThreshold() {
        #expect(ConfidenceScorer.threshold == 0.85)
    }
}
