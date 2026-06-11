# 置信度打分与路由决策

## 一、核心思路

**规则引擎不是判断"能不能处理"，而是给自己打个分——够自信就上，不够自信就让 LLM 来。**

这条线用置信度 **0.85** 一刀切，简单粗暴但有效。

```
规则引擎打分
     │
     ├── 置信度 ≥ 0.85 → 规则引擎直接处理
     │
     └── 置信度 < 0.85 → 交给 LLM
```

## 二、置信度打分模型

每一项匹配条件对应一个乘法因子，**所有命中的分乘起来**就是最终置信度。

### 单意图打分

```swift
// Sources/Core/NLU/ConfidenceScorer.swift
import Foundation

struct ConfidenceScorer {
    /// 每个条件独立打分，最终相乘
    func score(_ match: RuleMatch, originalText: String) -> ScoreResult {
        var score = 1.0
        var reasons: [String] = []

        // ── 金额确信度 ──────────────────────────

        if match.amount != nil {
            if hasUnit(originalText) {
                // "35块" "35元" → 金额非常确定
                score *= 1.0
                reasons.append("金额+单位: ×1.0")
            } else if isPureNumber(originalText) {
                // 纯数字 "35" → 大概率是金额
                score *= 0.9
                reasons.append("纯数字: ×0.9")
            } else {
                // "午饭35" → 有备注，金额大概率是金额
                score *= 0.95
                reasons.append("备注+数字: ×0.95")
            }
        }

        // ── 分类确信度 ──────────────────────────

        if let category = match.category {
            let catScore = categoryConfidence(category: category, note: match.note)
            score *= catScore
            reasons.append("分类\(catScore): ×\(catScore)")
        }

        // ── 意图清晰度 ──────────────────────────

        if hasActionWord(originalText) {
            score *= 1.0
            reasons.append("动作词: ×1.0")
        }

        // ── 降低置信度的因素 ────────────────────

        // 长句惩罚（超过15字开始降分）
        if originalText.count > 15 {
            let penalty = max(0.5, 1.0 - Double(originalText.count - 15) * 0.03)
            score *= penalty
            reasons.append("长句惩罚: ×\(max(0.5, penalty))")
        }

        // 模糊时间
        if hasAmbiguousTime(originalText) {
            score *= 0.8
            reasons.append("模糊时间: ×0.8")
        }

        // 代词/指代
        if hasReference(originalText) {
            score *= 0.6
            reasons.append("含指代: ×0.6")
        }

        // 连词（可能是多意图的信号）
        if hasConjunction(originalText) {
            score *= 0.7
            reasons.append("含连词: ×0.7")
        }

        return ScoreResult(
            score: min(max(score, 0.0), 1.0),
            reasons: reasons
        )
    }

    // ── 辅助方法 ──

    private func hasUnit(_ text: String) -> Bool {
        text.contains(/(块|元|块钱|毛|角)/)
    }

    private func isPureNumber(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /^\d+(\.\d+)?$/) != nil
    }

    private func hasActionWord(_ text: String) -> Bool {
        let actions = ["花了", "买了", "消费", "支出", "收入",
                       "打卡", "提醒", "记得", "备忘"]
        return actions.contains { text.contains($0) }
    }

    /// 分类确信度：备注和分类是否匹配
    private func categoryConfidence(category: String, note: String?) -> Double {
        guard let note, !note.isEmpty else { return 0.8 }

        let keywordMap: [String: [String]] = [
            "餐饮": ["饭", "餐", "吃", "外卖", "火锅", "面", "粉", "茶", "咖啡",
                     "奶茶", "烧烤", "麻辣烫", "麦当劳", "肯德基", "星巴克"],
            "交通": ["打车", "地铁", "公交", "出租", "滴滴", "加油", "停车"],
            "购物": ["买", "淘宝", "京东", "超市", "商场"],
            "娱乐": ["电影", "游戏", "唱歌", "KTV"],
            "医疗": ["看病", "药", "挂号", "体检"],
        ]

        let keywords = keywordMap[category] ?? []
        let matched = keywords.contains { note.contains($0) }
        return matched ? 1.0 : 0.7
    }

    private func hasAmbiguousTime(_ text: String) -> Bool {
        let ambiguous = ["最近", "前几天", "上回", "之前", "某天"]
        return ambiguous.contains { text.contains($0) }
    }

    private func hasReference(_ text: String) -> Bool {
        let refs = ["那个", "上次", "刚才", "刚刚那条", "上一条", "他", "她"]
        return refs.contains { text.contains($0) }
    }

    private func hasConjunction(_ text: String) -> Bool {
        let conj = ["和", "跟", "以及", "还有"]
        return conj.contains { text.contains($0) }
    }
}
```

### 多意图打分

多意图的置信度 = **所有子句置信度的最小值 × 组合惩罚系数**：

```swift
// Sources/Core/NLU/MultiConfidenceScorer.swift
import Foundation

struct MultiConfidenceScorer {
    private let singleScorer = ConfidenceScorer()

    func score(_ matches: [RuleMatch], originalText: String) -> Double {
        guard !matches.isEmpty else { return 0 }

        // 每个子句独立打分
        let scores = matches.map {
            singleScorer.score($0, originalText: $0.segmentText).score
        }

        // 取最低分（短板效应）
        let minScore = scores.min()!

        // 组合惩罚：子句越多，出错概率越高
        let count = matches.count
        let countPenalty: Double = switch count {
            case 1: 1.0
            case 2: 0.95
            case 3: 0.9
            default: 0.85
        }

        // 类型混合惩罚
        let types = Set(matches.map(\.intent))
        let mixPenalty = types.count > 1 ? 0.9 : 1.0

        return min(max(minScore * countPenalty * mixPenalty, 0.0), 1.0)
    }
}
```

## 三、打分举例

| 输入 | 匹配结果 | 打分过程 | 最终分 | 走谁 |
|------|---------|---------|--------|------|
| "35" | expense, ¥35 | 纯数字 ×0.9 | **0.90** | 规则 |
| "午饭35块" | expense, ¥35, 餐饮 | 备注+数字 ×0.95, 关键词匹配 ×1.0 | **0.95** | 规则 |
| "打车28" | expense, ¥28, 交通 | 备注+数字 ×0.95, 关键词匹配 ×1.0 | **0.95** | 规则 |
| "跑步打卡" | habit_checkin, 跑步 | 关键词直匹配 | **0.95** | 规则 |
| "午饭35打车28" | multiple: 2×expense | 各 0.95, countPenalty ×0.95 | **0.90** | 规则 |
| "买了点东西35" | expense, ¥35 | 备注+数字 ×0.95, 分类不匹配 ×0.7 | **0.67** | LLM |
| "午饭和晚饭50" | expense? | 含连词 ×0.7, 分类不确定 | **<0.7** | LLM |
| "昨天那个东西花了挺多" | expense? | 模糊时间 ×0.8, 含指代 ×0.6, 无金额 | **<0.5** | LLM |
| "这个月花了多少" | query | 无金额、无打卡词 | **0** | LLM |

## 四、阈值选择

```
阈值太高（0.95）→ 几乎所有请求都走 LLM，规则引擎形同虚设
阈值太低（0.70）→ 规则引擎误判率上升，用户看到错误分类

0.85 的含义：
- 金额明确 + 分类明确 → 0.90+ → 规则处理（自信）
- 金额明确 + 分类模糊 → 0.65- → LLM 处理（不冒险）
- 这条线正好把「确定能处理的」和「拿不准的」分开

上线后微调策略：
- 误判率 < 2% → 可降到 0.80，让更多请求走规则
- 误判率 > 5% → 升到 0.90，收紧标准
```

## 五、NLU 调度器

```swift
// Sources/Core/NLU/NluOrchestrator.swift
import Foundation

actor NluOrchestrator {
    private let ruleEngine = RuleEngine()
    private let llmClient: LlmClient
    private let scorer = ConfidenceScorer()

    private static let ruleThreshold = 0.85

    init(llmClient: LlmClient) {
        self.llmClient = llmClient
    }

    func process(_ rawText: String) async throws -> NluResult {
        let text = preprocess(rawText)

        // 1. 规则引擎尝试
        if let ruleResult = ruleEngine.tryMatch(text) {
            let scoreResult = scorer.score(ruleResult, originalText: text)

            if scoreResult.score >= Self.ruleThreshold {
                // ✅ 规则引擎处理
                return NluResult.fromRule(ruleResult, confidence: scoreResult.score)
            }
            // 分数不够，走 LLM（规则结果不传给 LLM，简化接口）
        }

        // 2. LLM 处理（通过后端代理调用）
        return try await llmClient.classify(text)
    }
}
```
