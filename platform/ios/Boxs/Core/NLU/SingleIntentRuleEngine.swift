import Foundation

/// 单意图规则引擎
/// 用正则和关键词匹配处理简单输入，省掉 60-70% 的 LLM 调用
/// 原则：宁可漏掉（交给 LLM），不可错判
final class SingleIntentRuleEngine {

    private let preprocessor = Preprocessor()

    // MARK: - 正则模式

    /// 纯金额 → 直接记账
    /// "35"、"35块"、"35元" → expense
    private let pureAmount = /(\d+(?:\.\d+)?)\s*(块|元|块钱)?$/

    /// 金额 + 简单备注
    /// "午饭35"、"打车28块" → expense + note
    private let amountWithNote = /([^\d]+?)\s*(\d+(?:\.\d+)?)\s*(块|元|块钱)?$/

    /// 纯记账前缀 + 金额
    /// "花了35"、"消费28" → expense
    private let expensePrefix = /(花了|消费|支出|付了)\s*(\d+(?:\.\d+)?)\s*(块|元|块钱)?$/

    /// 待办关键词
    private let todoKeywords = ["记得", "别忘了", "提醒我", "待办", "要买", "要做"]

    /// 打卡关键词 → 习惯名映射
    private let checkinKeywords: [(keyword: String, habitName: String)] = [
        ("跑步", "跑步"), ("运动", "运动"), ("健身", "健身"),
        ("读书", "读书"), ("阅读", "阅读"), ("早起", "早起"),
        ("冥想", "冥想"), ("喝水", "喝水"), ("打卡", ""),
        ("背单词", "背单词"), ("写日记", "写日记"),
        ("练琴", "练琴"), ("画画", "画画"),
    ]

    // MARK: - 匹配入口

    /// 尝试单意图匹配，未命中返回 nil（交给 LLM）
    func tryMatch(_ text: String) -> NLUResult? {
        let normalized = preprocessor.process(text)

        // 为空直接返回
        guard !normalized.isEmpty else { return nil }

        // 1. 纯金额
        if let match = tryMatchPureAmount(normalized, rawText: text) {
            return match
        }

        // 2. 花了/消费/支出 前缀 + 金额
        if let match = tryMatchExpensePrefix(normalized, rawText: text) {
            return match
        }

        // 3. 金额 + 备注
        if let match = tryMatchAmountWithNote(normalized, rawText: text) {
            return match
        }

        // 4. 打卡关键词
        if let match = tryMatchCheckin(normalized, rawText: text) {
            return match
        }

        // 5. 待办关键词
        if let match = tryMatchTodo(normalized, rawText: text) {
            return match
        }

        return nil // 未命中，交给 LLM
    }

    // MARK: - 匹配方法

    private func tryMatchPureAmount(_ text: String, rawText: String) -> NLUResult? {
        guard let match = text.firstMatch(of: pureAmount),
              let amount = Double(match.1) else { return nil }

        // 纯金额后面不能还有非单位文字（排除 "35块钱的那种" 这种场景）
        let fullMatch = String(match.0)
        if fullMatch.count < text.count {
            // 不是整个字符串匹配，跳过
            return nil
        }

        return .ruleResult(
            intent: "expense",
            rawText: rawText,
            confidence: 0.90,
            amount: amount,
            category: "其他"
        )
    }

    private func tryMatchExpensePrefix(_ text: String, rawText: String) -> NLUResult? {
        guard let match = text.firstMatch(of: expensePrefix),
              let amount = Double(match.2) else { return nil }

        let fullMatch = String(match.0)
        if fullMatch.count < text.count { return nil }

        return .ruleResult(
            intent: "expense",
            rawText: rawText,
            confidence: 0.88,
            amount: amount,
            category: "其他"
        )
    }

    private func tryMatchAmountWithNote(_ text: String, rawText: String) -> NLUResult? {
        guard let match = text.firstMatch(of: amountWithNote),
              let amount = Double(match.2) else { return nil }

        let note = String(match.1).trimmingCharacters(in: .whitespaces)

        // 备注不能太长（超过 10 字可能是其他内容）
        guard note.count <= 10 else { return nil }

        // 备注不能以数字开头
        guard !note.first!.isNumber else { return nil }

        let category = ExpenseCategory.guess(from: note).rawValue

        return .ruleResult(
            intent: "expense",
            rawText: rawText,
            confidence: 0.85,
            amount: amount,
            category: category,
            note: note
        )
    }

    private func tryMatchCheckin(_ text: String, rawText: String) -> NLUResult? {
        for (keyword, habitName) in checkinKeywords {
            if text.contains(keyword) {
                // 尝试提取数值（如 "跑步5公里" → value="5公里"）
                let value = extractCheckinValue(from: text, keyword: keyword)

                return .ruleResult(
                    intent: "habit_checkin",
                    rawText: rawText,
                    confidence: 0.90,
                    habitName: habitName.isEmpty ? keyword : habitName,
                    habitValue: value
                )
            }
        }
        return nil
    }

    private func tryMatchTodo(_ text: String, rawText: String) -> NLUResult? {
        for keyword in todoKeywords {
            if text.contains(keyword) {
                // 提取待办内容
                var content = text
                for kw in todoKeywords {
                    content = content.replacingOccurrences(of: kw, with: "")
                }
                content = content.trimmingCharacters(in: .whitespaces)

                guard !content.isEmpty else { return nil }

                return .ruleResult(
                    intent: "todo_add",
                    rawText: rawText,
                    confidence: 0.85,
                    content: content
                )
            }
        }
        return nil
    }

    // MARK: - 辅助

    /// 提取打卡值（如 "跑步5公里" → "5公里"）
    private func extractCheckinValue(from text: String, keyword: String) -> String? {
        // 匹配 "关键词 + 数字 + 单位"
        let patternString = NSRegularExpression.escapedPattern(for: keyword)
            + "\\s*(\\d+(?:\\.\\d+)?)\\s*(公里|km|页|分钟|min|杯|次|个)?"
        guard let regex = try? NSRegularExpression(pattern: patternString, options: []) else { return nil }

        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 2 else { return nil }

        var value = ""
        if let range = Range(match.range(at: 1), in: text) {
            value = String(text[range])
        }
        if match.numberOfRanges >= 3, let range = Range(match.range(at: 2), in: text) {
            let unit = String(text[range])
            if !unit.isEmpty {
                value += unit
            }
        }
        return value.isEmpty ? nil : value
    }
}
