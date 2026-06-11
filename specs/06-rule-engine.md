# 规则引擎设计

规则引擎的目标：用正则和关键词匹配处理简单输入，**省掉 60-70% 的 LLM 调用**。

设计原则：**宁可漏掉（交给 LLM），不可错判。**

## 一、单意图规则引擎

### 匹配模式

```swift
// Sources/Core/NLU/SingleIntentRuleEngine.swift
import Foundation

final class SingleIntentRuleEngine {
    /// 纯金额 → 直接记账
    /// "35"、"35块"、"35元" → expense
    private let pureAmount = /^(\d+(?:\.\d+)?)\s*(块|元|块钱)?$/

    /// 金额 + 简单备注
    /// "午饭35"、"打车28块" → expense + note
    private let amountWithNote = /^([^\d]+?)\s*(\d+(?:\.\d+)?)\s*(块|元|块钱)?$/

    /// 常见打卡关键词
    private let checkinKeywords: [String: String?] = [
        "打卡": nil,
        "跑步": "跑步", "运动": "运动",
        "健身": "健身", "读书": "读书", "阅读": "阅读",
        "早起": "早起", "冥想": "冥想", "喝水": "喝水",
    ]

    /// 单意图匹配入口
    func tryMatch(_ text: String) -> RuleResult? {
        let normalized = Self.normalize(text)

        // 1. 纯金额
        if let match = normalized.firstMatch(of: pureAmount) {
            return RuleResult(
                intent: "expense",
                amount: Double(match.1)!,
                confidence: 0.90
            )
        }

        // 2. 金额 + 备注
        if let match = normalized.firstMatch(of: amountWithNote) {
            let note = String(match.1)
            let category = guessCategory(note)
            return RuleResult(
                intent: "expense",
                amount: Double(match.2)!,
                note: note,
                category: category,
                confidence: 0.85
            )
        }

        // 3. 打卡关键词
        for (keyword, habitName) in checkinKeywords {
            if normalized.contains(keyword) {
                return RuleResult(
                    intent: "habit_checkin",
                    habitName: habitName ?? keyword,
                    confidence: 0.90
                )
            }
        }

        return nil // 未命中
    }
}
```

## 二、分句切割器（SentenceSplitter）

一句话多意图处理的核心。优先按显式分隔符切，切不动就按模式边界切。

### 三种难度

| 难度 | 示例 | 处理方式 |
|------|------|---------|
| 简单 | "午饭35，打车28" | 显式分隔符切割 |
| 中等 | "午饭35打车28" | 模式边界切割（备注+金额） |
| 困难 | "今天午饭和晚饭花了50" | 无法拆分，交给 LLM |

### 实现

```swift
// Sources/Core/NLU/SentenceSplitter.swift
import Foundation

final class SentenceSplitter {
    /// 显式分隔符列表
    private let delimiters = [
        "，", ",", "。", "；", ";",
        "然后", "还有", "另外", "接着", "还有个", "对了",
        "顺便", "以及",
    ]

    /// 切割主入口
    func split(_ text: String) -> [String] {
        // 第一步：按显式分隔符切割
        var segments = splitByDelimiters(text)

        // 第二步：对每个段再做模式边界切割
        return segments.flatMap { splitByPattern($0) }
    }

    /// 按分隔符切割
    private func splitByDelimiters(_ text: String) -> [String] {
        var result = [text]

        for delim in delimiters {
            var expanded: [String] = []
            for segment in result {
                expanded.append(contentsOf: segment.components(separatedBy: delim))
            }
            result = expanded
        }

        return result.map { $0.trimmingCharacters(in: .whitespaces) }
                     .filter { !$0.isEmpty }
    }

    /// 按模式边界切割（处理无分隔符的情况）
    /// "午饭35打车28" → ["午饭35", "打车28"]
    private func splitByPattern(_ segment: String) -> [String] {
        if segment.count <= 4 { return [segment] }

        var results: [String] = []

        // 模式：「非数字关键词」+「金额」出现多次
        let pattern = /([^\d，。；,;]+?)(\d+(?:\.\d+)?)(?:块|元|块钱)?/

        var lastEnd = segment.startIndex
        for match in segment.matches(of: pattern) {
            if match.range.lowerBound > lastEnd {
                let prefix = segment[lastEnd..<match.range.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty { results.append(prefix) }
            }
            results.append(String(match.output.0))
            lastEnd = match.range.upperBound
        }

        if lastEnd < segment.endIndex {
            let tail = segment[lastEnd...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { results.append(tail) }
        }

        return results.isEmpty ? [segment] : results
    }
}
```

## 三、多意图规则引擎

拆完之后，每个子句走单意图规则。任一段失败则整体降级给 LLM。

```swift
// Sources/Core/NLU/MultiIntentRuleEngine.swift
import Foundation

final class MultiIntentRuleEngine {
    private let splitter = SentenceSplitter()
    private let singleEngine = SingleIntentRuleEngine()

    func tryMatch(_ text: String) -> MultiIntentResult? {
        let segments = splitter.split(text)

        // 只有 1 段 → 不是多意图
        guard segments.count > 1 else { return nil }

        var items: [ParsedItem] = []
        var sharedDate: String?

        for seg in segments {
            guard var result = singleEngine.tryMatch(seg) else {
                // 某一段匹配失败 → 整体降级到 LLM
                return nil
            }

            // 继承共享上下文（比如开头的"今天"）
            if let date = result.date, sharedDate == nil {
                sharedDate = date
            }
            if let shared = sharedDate, result.date == nil {
                result.date = shared
            }
            items.append(result)
        }

        return MultiIntentResult(
            intent: "multiple",
            items: items,
            confidence: calcConfidence(items),
            rawText: text
        )
    }

    /// 置信度 = 所有序列的最低值（短板效应）
    private func calcConfidence(_ items: [ParsedItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.confidence).min()!
    }
}
```

## 四、规则引擎总入口

```swift
// Sources/Core/NLU/RuleEngine.swift
import Foundation

final class RuleEngine {
    private let single = SingleIntentRuleEngine()
    private let multi = MultiIntentRuleEngine()

    func tryMatch(_ text: String) -> RuleResult? {
        // 1. 先试单意图（快速路径）
        if let single = single.tryMatch(text) {
            return single
        }

        // 2. 再试多意图
        if let multi = multi.tryMatch(text) {
            return multi
        }

        // 3. 都没命中 → 交给 LLM
        return nil
    }
}
```

## 五、各场景走法

| 输入 | 分句结果 | 规则引擎 | 走 LLM |
|------|---------|---------|--------|
| "午饭35" | 1段：`["午饭35"]` | ✅ 单意图 expense | |
| "午饭35，打车28" | 2段：`["午饭35", "打车28"]` | ✅ 多意图 2×expense | |
| "午饭35打车28" | 2段：`["午饭35", "打车28"]` | ✅ 模式切割 | |
| "午饭35，跑步5公里" | 2段 | ✅ 多意图 expense+habit | |
| "午饭35，记得买牛奶" | 2段 | ✅ 多意图 expense+todo | |
| "今天午饭和晚饭花了50" | 1段 | ❌ 无法拆分 | ✅ LLM 理解语义 |
| "上周的餐饮花了多少钱" | 1段 | ❌ 查询类 | ✅ LLM 处理 |
| "打车28奶茶15午饭35" | 3段：`["打车28", "奶茶15", "午饭35"]` | ✅ 模式切割 | |

## 六、不处理的边界情况

以下场景规则引擎**主动放弃**，交给 LLM：

```
"今天午饭和晚饭花了50"
  → 语义歧义（总共50？各50？）

"昨天的那个东西花了挺多"
  → 含指代词，需要上下文理解

"这个月餐饮花了多少"
  → 查询类，需要数据库交互

"把上一条改成40"
  → 修改操作，需要指代消解

规则引擎原则：
- 能切就切，切完后每段必须独立可识别
- 任何一段识别失败 → 整体降级给 LLM
- 宁可多调 LLM，不可错误分类
```

## 七、规则热更新

规则引擎硬编码在客户端，修改需要发版。通过后端下发 JSON 配置实现热更新。

### 配置文件格式

```json
{
  "version": 2,
  "updated_at": "2026-06-11T10:00:00Z",
  "rules": {
    "checkin_keywords": {
      "打坐": "冥想",
      "散步": "运动",
      "瑜伽": "运动"
    },
    "category_keywords": {
      "餐饮": ["轻食", "沙拉", "寿司"],
      "交通": ["骑行", "共享单车"]
    },
    "delimiters": ["、", "以及"]
  }
}
```

### 更新机制

```
App 启动时：
  1. 请求 GET /api/v1/rules/config?current_version={本地版本}
  2. 服务端比对版本号，无变化返回 304 Not Modified
  3. 有变化返回新 JSON，客户端存入本地 UserDefaults
  4. 规则引擎初始化时合并：内置规则 + 热更新规则

合并策略：
  - 热更新关键词 追加到 内置关键词列表
  - 热更新分隔符 追加到 内置分隔符列表
  - 不支持删除内置规则，只能新增
```

### Rust 后端接口

```
GET /api/v1/rules/config?current_version=1

200 OK — 返回新版配置 JSON（含 version 字段）
304 Not Modified — 版本号一致，无需更新
```
