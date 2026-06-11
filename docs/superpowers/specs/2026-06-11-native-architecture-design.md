# Boxs 原生双端架构设计

> 本文档定义 Boxs 应用的完整技术架构：iOS (Swift) + Android (Kotlin) 原生客户端，
> 连接 Rust 后端。相关 specs：`03-architecture.md`、`12-rust-backend.md`、`14-ui-theme.md`。

---

## 一、整体架构

```
                    ┌─────────────────────────────┐
                    │       Rust Backend           │
                    │     (boxs-server)            │
                    │  Auth / NLU / STT / CRUD     │
                    └──────────┬──────────────────┘
                               │ HTTPS / WSS
                ┌──────────────┼──────────────┐
                ▼                              ▼
   ┌────────────────────┐        ┌────────────────────┐
   │   iOS App (Swift)   │        │ Android (Kotlin)    │
   │                     │        │                     │
   │  SwiftUI UI         │        │  Compose UI         │
   │  GRDB 本地存储      │        │  Room 本地存储       │
   │  Swift NLU 引擎     │        │  Kotlin NLU 引擎    │
   │  URLSession 网络    │        │  OkHttp/Retrofit    │
   │  AVFoundation 录音  │        │  MediaRecorder      │
   │  Starscream WS      │        │  OkHttp WS          │
   └────────────────────┘        └────────────────────┘
```

**设计原则：**

- 双端各自原生开发，充分利用平台特性和性能优势
- NLU 规则引擎逻辑简单（正则匹配 + 关键词查找 + 乘法打分），Swift/Kotlin 各约 300 行，各自原生实现
- 无跨语言桥接开销，性能最优
- 各自利用平台原生能力（Swift Regex literal / Kotlin Regex）

**后端职责：**

- Rust 后端（boxs-server）提供所有 API 服务
- PostgreSQL 数据持久化
- LLM Prompt 工程与分类服务
- STT WebSocket 服务
- 认证与授权

---

## 二、代码共享策略

### NLU 逻辑各自原生实现

原因：
1. 规则引擎逻辑简单（正则匹配 + 关键词查找 + 乘法打分），Swift/Kotlin 各约 300 行
2. 无跨语言桥接，性能最优
3. 各自利用平台特性（Swift Regex literal / Kotlin Regex）
4. 测试用例共享（同一套输入->预期输出），确保双端行为一致

### API 契约共享

双端调用相同的 REST API 端点，请求/响应格式一致。后端 API 路由定义、数据 Schema、WebSocket 协议为双端唯一权威契约。

---

## 三、页面结构（无 Tab 导航）

### 核心原则

**App 无 Tab Bar。** 主页是唯一根页面，所有功能通过主页控件进入。

```
MainPage（主页，唯一根页面）
  │
  ├── 右上角 ⚙️ → SettingsPage
  │
  ├── 横向概览卡片 →
  │   ├── 账单卡片点击 → ExpenseStatsPage
  │   ├── 待办卡片点击 → TodoListPage
  │   └── 打卡卡片点击 → HabitCalendarPage
  │
  ├── 记录列表点击 → RecordDetailPage
  │
  └── 悬浮语音按钮 → NLU 识别 → ConfirmSheet
```

### 页面清单（共 7 个）

| 页面 | 进入方式 | 内容 |
|------|---------|------|
| **MainPage** | 根页面 | 横向概览卡片 + 记录列表 + 悬浮语音按钮 |
| **SettingsPage** | 右上角 ⚙️ | 账号、订阅、主题切换、关于 |
| **ExpenseStatsPage** | 账单概览卡片点击 | 分类排行、趋势图、月/周/日切换 |
| **TodoListPage** | 待办概览卡片点击 | 全部待办，按优先级排序 |
| **HabitCalendarPage** | 打卡概览卡片点击 | 日历热力图、连续天数 |
| **RecordDetailPage** | 记录点击 | 单条记录详情 + 编辑/删除 |
| **ConfirmSheet** | NLU 识别后弹出 | 确认/编辑解析结果 |

### 主页布局

```
┌──────────────────────────────────┐
│  6/10 周二               ⚙️     │  顶栏 40pt
├──────────────────────────────────┤
│                                  │
│  ← 横向滑动概览卡片 →           │
│  ┌──────────┐ ┌──────────┐      │
│  │ 📋 待办  │ │ 💰 账单  │      │  可横向滑动
│  │ 今日 3/5 │ │ 本月     │      │
│  │ 已完成3  │ │ ¥3,850   │      │
│  │          │ │ ↑12% ↑   │      │
│  └──────────┘ └──────────┘      │
│                                  │
├──────────────────────────────────┤
│  最近记录                        │
│  🍜 午饭                -35.50 │  每行 44pt
│  餐饮 · 沙县          12:30    │
│  ─────────────────────────────  │  1px 分割线
│  🚕 打车                -28.00 │
│  交通                  09:15   │
│  ─────────────────────────────  │
│  📝 周五开会                    │
│  待办 · 提醒 15:00              │
│  ─────────────────────────────  │
│  💧 喝水                    ✓   │
│  习惯 · 今天第 8 杯             │
│                                  │
│              ◎ 🎤               │  ← 悬浮语音按钮
│                                  │  40pt 圆形，铁锈红
└──────────────────────────────────┘
```

### 概览卡片设计

**待办卡片：**
```
┌──────────────┐
│  📋 待办      │
│  今日 3/5    │  ← 已完成 3 / 总共 5
│  ■■■□□ 60%   │  ← 进度条
└──────────────┘
```

**账单卡片：**
```
┌──────────────┐
│  💰 账单      │
│  本月        │  ← 可切换 月/周/日
│  ¥3,850     │
│  ↑12% ↑     │  ← 较上周期变化趋势
└──────────────┘
```

**打卡卡片（可选）：**
```
┌──────────────┐
│  🏃 打卡      │
│  今日 3/5    │  ← 已打卡 3 / 习惯总数 5
│  🏃 ✓ 📖 ✓ 💧 │  ← 各习惯 emoji 状态
└──────────────┘
```

---

## 四、iOS 技术栈

### 核心依赖

| 领域 | 方案 | 说明 |
|------|------|------|
| UI | **SwiftUI** | 声明式 UI，紧凑自定义组件 |
| 导航 | **NavigationStack** | 单栈 push + sheet 弹出 |
| 本地存储 | **GRDB.swift** | SQLite 包装，类型安全查询，支持迁移 |
| 网络 | **URLSession + async/await** | 原生 HTTP，JWT 自动刷新，零第三方依赖 |
| Token | **Keychain** | 原生安全存储 |
| WebSocket | **Starscream** | 轻量 WebSocket 客户端，用于 STT |
| 录音 | **AVFoundation** | 原生 PCM 16kHz 录音 |
| 架构 | **MVVM + @Observable** | SwiftUI 原生观察机制 |
| 最低版本 | **iOS 16+** | 支持 Swift Regex literal |

### 不使用的依赖

- ~~Alamofire~~ — URLSession + async/await 足够
- ~~CoreData~~ — GRDB 更轻量灵活
- ~~Realm~~ — SQLite 生态更成熟
- ~~SnapKit~~ — SwiftUI 不需要

### SPM 依赖 (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.0"),
]
```

---

## 五、iOS 项目结构

```
Boxs/
├── Boxs.xcodeproj
├── Boxs/
│   ├── App/
│   │   ├── BoxsApp.swift              # @main 入口
│   │   └── AppDelegate.swift          # 生命周期
│   │
│   ├── Core/
│   │   ├── Theme/                     # 主题系统（与 14-ui-theme.md 一致）
│   │   │   ├── AppColors.swift        # 亮色 #F8F7F4 / 暗色 #141413
│   │   │   ├── AppSpacing.swift       # page=16, card=12, item=4
│   │   │   ├── AppRadius.swift        # card=10, button=8, tag=6
│   │   │   ├── AppSize.swift          # listItem=44, button=36, voice=40
│   │   │   └── AppTypography.swift    # 14pt主/12pt副/15pt金额/26pt大金额
│   │   │
│   │   ├── Database/                  # GRDB 本地存储
│   │   │   ├── AppDatabase.swift      # 数据库连接 + 迁移
│   │   │   ├── ExpenseRecord.swift    # Codable + FetchableRecord
│   │   │   ├── HabitDefinition.swift
│   │   │   ├── HabitRecord.swift
│   │   │   └── TodoRecord.swift
│   │   │
│   │   ├── Network/                   # API 客户端
│   │   │   ├── APIClient.swift        # URLSession 封装 + Token 自动刷新
│   │   │   ├── TokenManager.swift     # Keychain JWT 管理
│   │   │   └── Endpoints.swift        # API 路径常量
│   │   │
│   │   ├── NLU/                       # Swift 原生 NLU
│   │   │   ├── Preprocessor.swift     # 文本清洗 + 中文数字转换
│   │   │   ├── SingleIntentRuleEngine.swift
│   │   │   ├── SentenceSplitter.swift
│   │   │   ├── MultiIntentEngine.swift
│   │   │   ├── ConfidenceScorer.swift
│   │   │   ├── NLUOrchestrator.swift  # 规则引擎 → LLM 路由
│   │   │   ├── LLMClient.swift        # 调用后端 /api/nlu/classify
│   │   │   └── ResponseParser.swift   # JSON → NLUResult
│   │   │
│   │   ├── STT/                       # 语音识别
│   │   │   ├── AudioRecorder.swift    # AVFoundation 录音
│   │   │   └── STTClient.swift        # Starscream WebSocket
│   │   │
│   │   └── Constants/
│   │       └── Categories.swift       # 12 分类 + emoji + keywords
│   │
│   ├── Models/
│   │   ├── NLUResult.swift            # 意图识别结果
│   │   ├── Expense.swift              # 记账模型
│   │   ├── Habit.swift                # 习惯模型
│   │   ├── Todo.swift                 # 待办模型
│   │   └── User.swift                 # 用户模型
│   │
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift        # 主页：概览数据 + 记录列表
│   │   ├── NLUViewModel.swift         # NLU 处理状态管理
│   │   ├── AuthViewModel.swift        # 注册/登录
│   │   ├── ExpenseStatsViewModel.swift
│   │   ├── HabitViewModel.swift
│   │   └── TodoViewModel.swift
│   │
│   ├── Views/
│   │   ├── Components/                # SwiftUI 可复用组件
│   │   │   ├── CompactListItem.swift  # 44pt 行高记录行
│   │   │   ├── AppDivider.swift       # 1px 分割线
│   │   │   ├── OverviewCard.swift     # 横向概览卡片
│   │   │   ├── TodoOverviewCard.swift
│   │   │   ├── ExpenseOverviewCard.swift
│   │   │   ├── HabitOverviewCard.swift
│   │   │   ├── VoiceButton.swift      # 40pt 悬浮语音按钮
│   │   │   ├── ConfirmSheet.swift     # NLU 确认弹窗
│   │   │   ├── TagView.swift          # 22pt 标签
│   │   │   └── ActionButton.swift     # 36pt 按钮
│   │   │
│   │   └── Pages/                     # 7 个页面
│   │       ├── MainPage.swift         # 唯一根页面
│   │       ├── SettingsPage.swift
│   │       ├── ExpenseStatsPage.swift
│   │       ├── TodoListPage.swift
│   │       ├── HabitCalendarPage.swift
│   │       ├── RecordDetailPage.swift
│   │       └── ConfirmSheet.swift
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
│
├── BoxsTests/
│   ├── NLUTests/                      # 规则引擎单元测试
│   │   ├── RuleEngineTests.swift
│   │   ├── SentenceSplitterTests.swift
│   │   ├── ConfidenceScorerTests.swift
│   │   └── PreprocessorTests.swift
│   └── DatabaseTests/
│       └── DatabaseTests.swift
│
└── BoxsUITests/
```

---

## 六、Swift NLU 规则引擎实现

> 完整的 Swift 实现代码见 [`specs/06-rule-engine.md`](../../../specs/06-rule-engine.md)（规则引擎）和 [`specs/07-confidence-and-routing.md`](../../../specs/07-confidence-and-routing.md)（置信度与路由）。
> 以下仅列出核心数据类型和调度流程概要。

### 核心数据类型

```swift
// Models/NLUResult.swift
struct NLUResult: Codable, Sendable {
    let intent: String           // expense, habit_checkin, todo_add, ...
    let confidence: Double
    let rawText: String
    let source: String           // "rule" | "llm"

    var amount: Double?
    var category: String?
    var note: String?
    var merchant: String?
    var habitName: String?
    var habitValue: String?
    var content: String?
    var remindAt: Date?
    var reply: String?
    var items: [NLUResult]?      // 多意图
}
```

### NLU 调度流程

```
用户输入 → Preprocessor（文本清洗）
         → SingleIntentRuleEngine（正则匹配，~70% 请求命中）
         → SentenceSplitter + MultiIntentEngine（多意图拆分）
         → ConfidenceScorer（乘法因子打分）
         → 置信度 ≥ 0.85？→ 规则引擎直接处理
         → 置信度 < 0.85？→ LlmClient.classify()（调用后端 /api/nlu/classify）
```

---

## 七、SwiftUI 组件

> 完整组件实现见 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §四–§六。
> 包含：CompactListItem、AppDivider、OverviewCard、TagView、ActionButton、VoiceButton、HalfSheet 等。

核心组件清单：

| 组件 | 文件 | 说明 |
|------|------|------|
| OverviewCard | `Views/Components/OverviewCard.swift` | 横向概览卡片（120×80dp） |
| CompactListItem | `Views/Components/CompactListItem.swift` | 44dp 行高记录行 |
| AppDivider | `Views/Components/AppDivider.swift` | 1px 分割线，左偏移 52dp |
| TagView | `Views/Components/TagView.swift` | 22dp 高度标签 |
| ActionButtonStyle | `Views/Components/ActionButtonStyle.swift` | primary/secondary/text 三种样式 |
| VoiceButton | `Views/Components/VoiceButton.swift` | 40dp 悬浮语音按钮 + 脉冲动画 |
| HalfSheet | `Views/Components/HalfSheet.swift` | 自定义半屏弹窗 |

### 主页布局结构

```
MainPage (NavigationStack, 单栈导航)
  ├── 顶栏 (40dp)：日期 + ⚙️ 设置入口
  ├── 横向概览卡片 (ScrollView .horizontal)
  │   ├── ExpenseOverviewCard → 点击进入 ExpenseStatsPage
  │   ├── TodoOverviewCard → 点击进入 TodoListPage
  │   └── HabitOverviewCard → 点击进入 HabitCalendarPage
  ├── 记录列表 (LazyVStack, 每行 44dp)
  └── VoiceButton (Z轴浮动, 底部居中)

NavigationRoute 枚举：
  case settings / expenseStats / todoList / habitCalendar / recordDetail(String)
```

---

## 八、GRDB 本地存储

> 数据库 Schema 与服务端 PostgreSQL 对齐（见 [`specs/03-architecture.md`](../../../specs/03-architecture.md) §三），字段名用 camelCase。
> 完整 GRDB 实现见 [`docs/superpowers/plans/2026-06-11-p0-prototype.md`](../plans/2026-06-11-p0-prototype.md) Task 10。

核心表模型：`ExpenseRecord`、`HabitDefinition`、`HabitRecord`、`TodoRecord`（均为 `Codable + FetchableRecord + PersistableRecord`）。

金额统一用 `amountCents: Int`（分），展示时除以 100。

---

## 九、开发阶段

### P0 — iOS MVP（3 周）

| 周 | 任务 |
|----|------|
| **Week 1** | Rust 后端搭建 + iOS 项目初始化 + 主题系统 + GRDB 数据层 + 网络层 |
| **Week 2** | NLU 规则引擎（Swift）+ 置信度/路由 + STT 集成 + 语音按钮 |
| **Week 3** | 主页 UI + 概览卡片 + 记录列表 + 确认弹窗 + 联调 |

### P1 — Android 移植（2 周）

| 周 | 任务 |
|----|------|
| **Week 4** | Kotlin 项目初始化 + Compose UI + Room 数据层 + 网络层 |
| **Week 5** | NLU 规则引擎（Kotlin）+ STT + 主页 + 联调 |

### P2 — 发布上线（1 周）

| 任务 |
|------|
| 双端回归测试 + 修复 |
| App Store / Google Play 提审素材准备 |
| 灰度发布 + 监控接入 |

### P3 — 持续迭代

| 功能 | 优先级 |
|------|--------|
| 统计图表 | 高 |
| 提醒通知 | 高 |
| 暗色模式 | 中 |
| OCR 票据 | 中 |
| 数据云同步 | 中 |

---

## 十、Android 技术栈映射（P1 参考）

| iOS | Android |
|-----|---------|
| SwiftUI | Jetpack Compose |
| GRDB.swift | Room |
| URLSession | OkHttp + Retrofit |
| Keychain | EncryptedSharedPreferences |
| AVFoundation | MediaRecorder |
| Starscream | OkHttp WebSocket |
| Swift Regex | Kotlin Regex |
| @Observable | StateFlow / Compose State |
| NavigationStack | Compose Navigation |

---

## 附录：与现有 Specs 的关系

| 现有 Spec | 关系 |
|-----------|------|
| `01-product-overview.md` | 产品定义不变 |
| `02-features.md` | 功能范围不变 |
| `03-architecture.md` | 本文档为前端架构的权威定义 |
| `04-nlu-design.md` | NLU 管线设计不变，Swift/Kotlin 原生实现 |
| `05-nlu-prompts.md` | LLM Prompt 不变 |
| `06-rule-engine.md` | 规则引擎逻辑不变，Swift/Kotlin 各自实现 |
| `07-confidence-and-routing.md` | 置信度与路由逻辑不变，Swift/Kotlin 各自实现 |
| `08-development-plan.md` | 开发计划以本文档 P0-P3 为准 |
| `12-rust-backend.md` | 后端架构不变 |
| `14-ui-theme.md` | 主题值不变，无 Tab Bar，概览为横向卡片 |
