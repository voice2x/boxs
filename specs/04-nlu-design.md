# NLU 模块设计

## 一、意图分类体系（Intent Taxonomy）

### 主意图（Primary Intents）

| Intent | 含义 | 触发示例 | 优先级 |
|--------|------|----------|--------|
| `expense` | 支出记账 | "午饭花了35"、"打车28" | 高 |
| `income` | 收入记账 | "发了工资8000"、"收到红包200" | 高 |
| `transfer` | 转账/还款 | "还了信用卡3000"、"转给老王500" | 中 |
| `habit_checkin` | 习惯打卡 | "跑了5公里"、"今天看了30页书" | 高 |
| `todo_add` | 添加待办 | "提醒我周五开会"、"记得买牛奶" | 高 |
| `memo_add` | 添加备忘 | "今天心情不错"、"这个餐厅好吃" | 中 |
| `query` | 查询数据 | "这个月花了多少"、"上周跑步几次" | 高 |
| `query_habit` | 查询习惯进度 | "我这周跑步打卡了吗" | 中 |
| `modify` | 修改记录 | "把午饭改成40"、"删掉上一条" | 中 |
| `cancel` | 撤销操作 | "刚才记错了"、"取消上一步" | 低 |
| `multiple` | 混合多条 | "午饭35，下午咖啡18，跑步5公里" | 高 |
| `chitchat` | 闲聊/超出范围 | "今天天气怎么样" | 低 |

### 记账分类（Expense/Income Categories）

```swift
// Sources/Core/Constants/Categories.swift
enum ExpenseCategory: String, CaseIterable {
    case dining       = "餐饮"
    case transport    = "交通"
    case shopping     = "购物"
    case entertainment = "娱乐"
    case medical      = "医疗"
    case education    = "教育"
    case housing      = "居住"
    case clothing     = "服饰"
    case digital      = "数码"
    case social       = "社交"
    case pet          = "宠物"
    case other        = "其他"

    var icon: String {
        switch self {
        case .dining:        return "🍜"
        case .transport:     return "🚗"
        case .shopping:      return "🛒"
        case .entertainment: return "🎮"
        case .medical:       return "🏥"
        case .education:     return "📚"
        case .housing:       return "🏠"
        case .clothing:      return "👕"
        case .digital:       return "📱"
        case .social:        return "🎁"
        case .pet:           return "🐱"
        case .other:         return "📌"
        }
    }

    var keywords: [String] {
        switch self {
        case .dining:
            return ["吃饭", "午饭", "晚饭", "早餐", "外卖", "火锅", "咖啡", "奶茶", "水果"]
        case .transport:
            return ["打车", "地铁", "公交", "加油", "停车", "过路费"]
        case .shopping:
            return ["买", "淘宝", "京东", "超市", "日用品"]
        case .entertainment:
            return ["电影", "游戏", "KTV", "唱歌"]
        case .medical:
            return ["看病", "药", "体检", "挂号"]
        case .education:
            return ["课程", "书", "培训", "学费"]
        case .housing:
            return ["房租", "水费", "电费", "燃气", "物业"]
        case .clothing:
            return ["衣服", "鞋", "包", "外套"]
        case .digital:
            return ["手机", "电脑", "耳机", "会员", "充值"]
        case .social:
            return ["红包", "礼物", "请客", "随礼"]
        case .pet:
            return ["猫粮", "狗粮", "宠物", "疫苗"]
        case .other:
            return []
        }
    }
}
```

## 二、NLU 处理管线

```
用户输入（语音/文字）
       │
       ▼
  ┌─────────────┐
  │ 1. 预处理    │  文本清洗、标点规范化、方言关键词替换
  │ PreProcessor │  "午饭花了三十五" → "午饭花了35"
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │ 2. 快速规则  │  正则匹配明显模式（纯金额、纯打卡词）
  │ RuleEngine  │  "35" → 直接记账，不调 LLM
  └──────┬──────┘
         │ 未命中规则 或 置信度 < 0.85
         ▼
  ┌─────────────┐
  │ 3. LLM 缓存  │  输入文本 hash → 命中缓存则直接返回
  │ LLM Cache   │  缓存 LRU 100 条，TTL 10 分钟
  └──────┬──────┘
         │ 缓存未命中
         ▼
  ┌─────────────┐
  │ 3. LLM 调用  │  发送 Prompt，获取 JSON
  │ LLM Client  │  超时 3s，失败走降级
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │ 4. 后处理    │  JSON 解析 + Schema 校验 + 默认值填充
  │ PostProcess  │  无效 amount → 标记需用户确认
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │ 5. 确认/执行 │  高置信度 → 静默执行 + toast 确认
  │ Executor    │  低置信度 → 弹出确认卡片
  └──────┬──────┘
         │
         ▼
    结构化存储 → UI 更新
```

## 三、降级策略（Fallback Chain）

```
1. 规则引擎匹配 → ~70% 的请求不走 LLM
     │ 未命中
     ▼
2. LLM 缓存 → 输入文本 hash 命中则直接返回，省掉 LLM 调用
     │ 缓存未命中
     ▼
3. 主模型（glm-4-flash）→ 延迟 ~200ms（Rust 后端代理调用）
     │ 超时/失败
     ▼
4. 备用模型（gpt-4o-mini）→ 延迟 ~500ms
     │ 也失败
     ▼
5. 离线模式 → 弹出手动输入卡片
              "网络不太好，请手动输入"
              自动填入已识别的文本
```

## 四、LLM Provider 策略

客户端通过 Rust 后端代理调用 LLM，不直连 LLM API。后端负责 Prompt 组装、模型选择、降级和额度控制。

```swift
// Sources/Core/NLU/LlmClient.swift
import Foundation

final class LlmClient {
    private let baseURL: URL
    private let getAccessToken: () async -> String?
    private let session: URLSession

    init(
        baseURL: URL,
        session: URLSession = .shared,
        getAccessToken: @escaping () async -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.getAccessToken = getAccessToken
    }

    func classify(
        _ text: String,
        recentRecords: [ExpenseRecord]? = nil,
        userHabits: [String]? = nil
    ) async throws -> NluResult {
        let token = await getAccessToken()
        let url = baseURL.appendingPathComponent("/api/nlu/classify")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "text": text,
            "user_habits": userHabits ?? [],
            "recent_records": recentRecords ?? [],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LlmError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw LlmError.quotaExceeded
        }
        guard httpResponse.statusCode == 200 else {
            throw LlmError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = body["result"]
        return try ResponseParser.parse(result)
    }
}
```

## 五、LLM 结果缓存

对 LLM 返回结果做客户端内存缓存，相同或相似输入直接复用，进一步降低调用量。

```swift
// Sources/Core/NLU/LlmCache.swift
import Foundation

actor LlmCache {
    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = 100
    private let ttl: TimeInterval = 600 // 10 分钟

    struct CacheEntry {
        let result: NluResult
        let createdAt: Date
        var isExpired: Bool { Date().timeIntervalSince(createdAt) > 600 }
    }

    /// 查询缓存，命中且未过期则返回
    func get(_ text: String) -> NluResult? {
        let key = cacheKey(text)
        guard let entry = cache[key], !entry.isExpired else {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.result
    }

    /// 写入缓存，超出上限时淘汰最旧条目
    func set(_ text: String, result: NluResult) {
        let key = cacheKey(text)
        if cache.count >= maxEntries {
            // 淘汰最旧的条目
            if let oldest = cache.min(by: { $0.value.createdAt < $1.value.createdAt }) {
                cache.removeValue(forKey: oldest.key)
            }
        }
        cache[key] = CacheEntry(result: result, createdAt: Date())
    }

    /// 缓存 key：标准化后的文本的确定性哈希
    private func cacheKey(_ text: String) -> String {
        // 去除空格、转小写后，使用 SHA-256 前 16 位作为 key
        // 不使用 hashValue（跨进程不稳定且有碰撞风险）
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
        return normalized
            .data(using: .utf8)!
            .sha256.prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
```

**缓存策略：**
- LRU 淘汰，上限 100 条
- TTL 10 分钟（同一输入短时间内重复不会重复调 LLM）
- 缓存 key 为标准化文本的 SHA-256 前 16 字节（去空格、转小写后取摘要）
- 仅缓存高置信度结果（confidence ≥ 0.8），低置信度结果不缓存
- 规则引擎命中不经过缓存（本身已是 0 成本）
