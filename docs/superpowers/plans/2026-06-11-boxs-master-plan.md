# Boxs 项目开发总体规划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 AI 语音驱动的生活管理 App，通过一句话完成记账、打卡、备忘，用规则引擎 + LLM 双层架构实现低成本高效率的意图识别。

**Architecture:** iOS 原生 App（Swift + SwiftUI + GRDB.swift）与 Android 原生 App（Kotlin + Jetpack Compose + Room）各自通过 HTTPS/WSS 连接 Rust 后端（Axum + sqlx + PostgreSQL）。后端代理 LLM API 和讯飞 STT WebSocket。客户端内置规则引擎处理 60-70% 的简单请求，复杂请求走 LLM。

**Tech Stack:**
- **iOS:** Swift + SwiftUI + GRDB.swift + URLSession + Keychain + AVFoundation + Starscream
- **Android (P1+):** Kotlin + Jetpack Compose + Room + OkHttp + EncryptedSharedPreferences
- **Backend:** Rust + Axum + sqlx + PostgreSQL
- **NLU:** 规则引擎 + LLM，原生实现（Swift on iOS, Kotlin on Android）

---

## 一、项目概览

```
┌──────────────────────────────────────────────────────────┐
│              iOS App (Swift/SwiftUI)                      │
│  GRDB.swift · AVFoundation · 规则引擎(Swift) · UI         │
├──────────────────────────────────────────────────────────┤
│              Android App (Kotlin/Compose)                 │
│  Room · OkHttp · 规则引擎(Kotlin) · UI                    │
└──────────────────────────┬───────────────────────────────┘
                           │ HTTPS / WSS
┌──────────────────────────┴───────────────────────────────┐
│                    Rust Backend (boxs-server)             │
│  Auth (JWT) · NLU (LLM Proxy) · Data CRUD · STT Relay    │
└──────────────────────────┬───────────────────────────────┘
                    ┌───────┼───────┐
              PostgreSQL   LLM API   讯飞 STT
```

### 页面架构

共 7 个页面，无 Tab Bar 导航：

| 页面 | 入口 | 说明 |
|------|------|------|
| **MainPage** | App 唯一根页面 | 水平滚动概览卡片（待办/账单/打卡）+ 浮动语音按钮 |
| **SettingsPage** | MainPage 右上角齿轮图标 | 用户设置、账户管理 |
| **ExpenseStatsPage** | MainPage 账单卡片 | 记账统计图表 |
| **TodoListPage** | MainPage 待办卡片 | 完整待办列表 |
| **HabitCalendarPage** | MainPage 打卡卡片 | 打卡日历视图 |
| **RecordDetailPage** | 任意记录项点击 | 单条记录详情/编辑 |
| **ConfirmSheet** | 语音识别完成后弹出 | NLU 解析结果确认/修改 |

```
┌─────────────────────────────────┐
│  MainPage              [⚙️]     │  ← 右上角 Settings 入口
│                                 │
│  ┌─────┐ ┌─────┐ ┌─────┐      │  ← 水平滚动概览卡片
│  │待办  │ │账单  │ │打卡  │      │     点击进入对应详情页
│  └─────┘ └─────┘ └─────┘      │
│                                 │
│  最近记录列表...                 │
│                                 │
│            [🎙]                 │  ← 底部居中浮动语音按钮
└─────────────────────────────────┘
```

---

## 二、开发阶段总览

| 阶段 | 周期 | 核心交付 | 详细计划 |
|------|------|---------|---------|
| **P0 iOS MVP** | 3 周 | Rust 后端 + iOS 核心功能 + NLU + 语音 + 主页 | [P0 详细计划](./2026-06-11-p0-prototype.md) |
| **P1 Android + 完善** | 2 周 | Android 移植 + 统计图表 + 推送通知 | 本文档 §五 |
| **P2 发布** | 1 周 | App Store + Google Play 上架 | 本文档 §六 |
| **P3 迭代** | 持续 | AI 查询、微信小程序、Widget、云同步 | 本文档 §七 |

**总计 6 周可双平台上线。**

---

## 三、子系统拆分

项目分为四个可独立开发的子系统，P0 阶段聚焦 iOS，按依赖顺序推进：

| 子系统 | 说明 | 关键技术 | P0 任务范围 |
|--------|------|---------|------------|
| **A. Rust 后端** | 认证、LLM 代理、STT 透传、数据 CRUD | Axum + sqlx + PostgreSQL | Task 1-7 |
| **B. iOS 基础** | 项目框架、本地存储、主题系统、自定义组件 | SwiftUI + GRDB.swift + Keychain | Task 8-11 |
| **C. NLU + 语音** | 规则引擎、LLM 客户端、置信度路由、STT 集成 | Swift 原生 + AVFoundation + Starscream | Task 12-16 |
| **D. UI 页面** | MainPage + 6 个子页面 | SwiftUI | Task 17-20 |

### 开发顺序

```
Week 1:
  Day 1-2  → A: Rust 后端基础 (Task 1-3)
  Day 1-2  → B: iOS 项目搭建 (Task 8-9)           ← 可并行
  Day 3-5  → A: Rust 后端功能模块 (Task 4-7)
  Day 3-5  → B: iOS 主题+组件 (Task 10-11)         ← 可并行

Week 2:
  Day 6-7  → C: NLU 核心模块 (Task 12-14)
  Day 8    → C: 语音集成 (Task 15-16)
  Day 9-10 → D: UI 页面 + 联调 (Task 17-20)

Week 3:
  Day 11-15 → D: UI 完善 + 端到端测试 + iOS MVP 收尾
```

---

## 四、P0 详细任务（Week 1-3）

> 完整的逐步实施计划见 [P0 详细计划](./2026-06-11-p0-prototype.md)，包含每个步骤的代码、命令和预期输出。

### Week 1: 后端 + iOS 基础框架

| Day | Task | 交付物 |
|-----|------|--------|
| 1 | Rust 项目初始化 + Config + Error + State | 编译通过的空服务 |
| 1 | 数据库迁移 (users, business, usage) | 4 个 migration SQL 文件 |
| 2 | Auth 模块 (注册/登录/JWT/中间件) | 5 个 API 端点 |
| 2 | iOS 项目初始化 + Xcode 项目 + 目录结构 | 可运行的空 SwiftUI App |
| 3 | LLM 代理模块 (client + quota + prompts) | NLU classify 端点 |
| 3 | iOS GRDB 数据库 + Repository 层 | 本地 SQLite CRUD |
| 4 | STT 透传模块 (讯飞 WebSocket + relay) | STT WebSocket 端点 |
| 4 | iOS 主题系统 (颜色 + 间距 + 组件库) | SwiftUI 自定义组件 |
| 5 | Data CRUD 模块 (expense + habit + todo) | 14 个数据 API 端点 |
| 5 | iOS API Client (URLSession) + Token 管理 (Keychain) | 网络层封装 |

### Week 2: NLU + 语音 + 核心交互

| Day | Task | 交付物 |
|-----|------|--------|
| 6 | 文本预处理 + 单意图规则引擎 (Swift) | 规则引擎核心逻辑 |
| 7 | 分句切割器 + 多意图规则引擎 (Swift) | 多意图处理 |
| 7 | NLU 单元测试 (XCTest) | 覆盖 30+ 场景的测试 |
| 8 | LLM Client (URLSession) + NLU Orchestrator | 客户端 NLU 流水线 |
| 8 | 置信度打分 + 路由决策 | 置信度评分系统 |
| 9 | 语音识别集成 (AVFoundation 录音 + Starscream STT WebSocket) | 实时语音转文字 |
| 9 | MainPage UI + 水平滚动卡片 + 浮动语音按钮 | 核心交互流程 |
| 10 | ConfirmSheet + RecordDetailPage | 确认卡片 + 记录详情页 |

### Week 3: 页面完善 + MVP 收尾

| Day | Task | 交付物 |
|-----|------|--------|
| 11 | ExpenseStatsPage (记账统计) | 统计图表页 |
| 12 | TodoListPage + HabitCalendarPage | 待办列表 + 打卡日历 |
| 13 | SettingsPage | 设置页 |
| 14 | 端到端联调 + Bug 修复 | 完整可运行 MVP |
| 15 | 暗色模式适配 + UI 动效打磨 | 视觉完善 |

---

## 五、P1 Android 移植 + 完善（Week 4-5）

### Week 4: Android 移植

| 任务 | 说明 |
|------|------|
| Android 项目初始化 | Kotlin + Jetpack Compose + Room + Gradle 配置 |
| Room 数据库 + Repository | 与 iOS GRDB 对等的数据层 |
| API Client (OkHttp) + EncryptedSharedPreferences | 网络层 + 安全 Token 存储 |
| NLU 规则引擎移植 (Kotlin) | Swift 规则引擎的 Kotlin 等价实现 |
| 语音集成 | Android AudioRecord + OkHttp WebSocket STT |
| 7 个页面全部用 Compose 实现 | 对齐 iOS 页面架构 |

### Week 5: 统计 + 通知 + UI 完善

| 任务 | 说明 |
|------|------|
| 记账统计页 (双平台) | 日/周/月统计图表、分类排行、日支出趋势 |
| NLU query 接口 | Rust 端实现 `/api/nlu/query`，查询 Prompt |
| AI 对话查询 | 双平台集成对话式数据查询 |
| NLU correct 接口 | Rust 端实现 `/api/nlu/correct`，纠错 Prompt |
| 本地推送通知 | iOS UNUserNotificationCenter + Android WorkManager |
| 待办提醒系统 | 基于 remind_at 的本地定时通知 |
| 打卡提醒 | 每日打卡提醒推送 |
| UI 动效 (双平台) | 语音按钮脉冲、打卡弹性动画、记录插入动画 |
| 数据同步引擎 | 本地 SQLite ↔ PostgreSQL 双向同步基础框架 |

---

## 六、P2 发布阶段（Week 6）

| 任务 | 说明 |
|------|------|
| App Store 提审 | iOS 应用描述、截图、隐私政策 |
| Google Play 上架 | Android 签名、AAB 构建、商店素材 |
| 邮箱验证 | SMTP 集成、验证码发送 |
| 生产部署 | Docker 部署、Nginx HTTPS、数据库生产配置 |
| Landing Page | 产品官网 |
| 埋点 + 错误收集 | 基础使用数据收集 |

---

## 七、P3 持续迭代

| 功能 | 优先级 | 说明 |
|------|--------|------|
| 微信小程序版本 | 高 | 降低安装门槛 |
| Widget / 小组件 | 高 | iOS WidgetKit + Android Glance |
| 数据云同步 | 高 | 多设备实时同步 |
| 数据导出 | 中 | CSV/PDF 导出 |
| 多账本 | 中 | 个人/家庭/旅行 |
| Apple Watch | 中 | 快速语音记录 |
| AI 消费建议 | 中 | 月度报告 |
| Siri / 快捷指令 | 中 | iOS 集成 |
| 家庭共享 | 低 | 家庭记账 |

---

## 八、文件结构总览

### Rust 后端 (boxs-server/)

```
boxs-server/
├── Cargo.toml
├── .env
├── migrations/
│   ├── 001_users.sql
│   ├── 002_business.sql
│   ├── 003_usage.sql
│   └── 004_housekeeping.sql
├── src/
│   ├── main.rs
│   ├── config.rs
│   ├── error.rs
│   ├── state.rs
│   ├── auth/        (mod, password, jwt, handler, middleware, email)
│   ├── routes/      (mod, auth, nlu, data, stt, health)
│   ├── llm/         (mod, client, quota, prompts)
│   ├── stt/         (mod, relay, xfyun)
│   └── data/        (mod, expense, habit, todo)
├── Dockerfile
└── docker-compose.yml
```

### iOS App (Boxs/)

```
Boxs/
├── Boxs.xcodeproj
├── Boxs/
│   ├── App/
│   │   ├── BoxsApp.swift              (@main entry point)
│   │   └── AppDelegate.swift
│   ├── Core/
│   │   ├── Theme/       (Colors.swift, Spacing.swift, Typography.swift)
│   │   ├── Constants/   (Categories.swift)
│   │   ├── Network/     (APIClient.swift, URLSession extensions)
│   │   ├── Auth/        (TokenManager.swift, KeychainWrapper.swift)
│   │   ├── Database/    (AppDatabase.swift, Tables/, DAOs/)
│   │   ├── NLU/         (Preprocessor.swift, RuleEngine.swift,
│   │   │                 SentenceSplitter.swift, MultiIntentEngine.swift,
│   │   │                 ConfidenceScorer.swift, NLUOrchestrator.swift,
│   │   │                 LLMClient.swift, ResponseParser.swift)
│   │   └── STT/         (STTClient.swift, AudioRecorder.swift)
│   ├── Views/
│   │   ├── Components/  (OverviewCard.swift, CompactListItem.swift, AppDivider.swift,
│   │   │                 VoiceButton.swift, TagView.swift, ActionButton.swift,
│   │   │                 HalfSheet.swift, ConfirmSheet.swift)
│   │   └── Pages/       (MainPage.swift, SettingsPage.swift,
│   │                      ExpenseStatsPage.swift, TodoListPage.swift,
│   │                      HabitCalendarPage.swift, RecordDetailPage.swift)
│   ├── Models/          (Expense.swift, Habit.swift, Todo.swift, NLUResult.swift)
│   └── ViewModels/      (MainViewModel.swift, ExpenseViewModel.swift,
│                          HabitViewModel.swift, TodoViewModel.swift,
│                          NLUViewModel.swift, AuthViewModel.swift)
├── BoxsTests/
│   ├── NLU/
│   │   ├── RuleEngineTests.swift
│   │   ├── SentenceSplitterTests.swift
│   │   ├── ConfidenceScorerTests.swift
│   │   └── PreprocessorTests.swift
│   └── ViewModels/
│       └── MainViewModelTests.swift
├── BoxsUITests/
└── .github/
```

### Android App (boxs-android/) — P1 阶段创建

```
boxs-android/
├── build.gradle.kts
├── app/
│   ├── src/main/
│   │   ├── java/com/boxs/app/
│   │   │   ├── App.kt
│   │   │   ├── core/
│   │   │   │   ├── theme/       (Color.kt, Theme.kt, Type.kt)
│   │   │   │   ├── constants/   (Categories.kt)
│   │   │   │   ├── network/     (ApiClient.kt, OkHttp extensions)
│   │   │   │   ├── auth/        (TokenManager.kt, EncryptedPrefs.kt)
│   │   │   │   ├── database/    (AppDatabase.kt, Entities/, DAOs/)
│   │   │   │   ├── nlu/         (Preprocessor.kt, RuleEngine.kt,
│   │   │   │   │                 SentenceSplitter.kt, MultiIntentEngine.kt,
│   │   │   │   │                 ConfidenceScorer.kt, NLUOrchestrator.kt,
│   │   │   │   │                 LLMClient.kt, ResponseParser.kt)
│   │   │   │   └── stt/         (STTClient.kt, AudioRecorder.kt)
│   │   │   ├── ui/
│   │   │   │   ├── main/        (MainPage.kt, OverviewCard.kt)
│   │   │   │   ├── settings/    (SettingsPage.kt)
│   │   │   │   ├── expense/     (ExpenseStatsPage.kt)
│   │   │   │   ├── todo/        (TodoListPage.kt)
│   │   │   │   ├── habit/       (HabitCalendarPage.kt)
│   │   │   │   ├── record/      (RecordDetailPage.kt)
│   │   │   │   └── confirm/     (ConfirmSheet.kt)
│   │   │   ├── data/            (ExpenseRepository.kt, HabitRepository.kt,
│   │   │   │                     TodoRepository.kt)
│   │   │   └── viewmodel/       (MainViewModel.kt, ExpenseViewModel.kt,
│   │   │                          HabitViewModel.kt, TodoViewModel.kt,
│   │   │                          NLUViewModel.kt, AuthViewModel.kt)
│   │   └── res/
│   └── src/test/
│       └── nlu/
│           ├── RuleEngineTest.kt
│           ├── SentenceSplitterTest.kt
│           ├── ConfidenceScorerTest.kt
│           └── PreprocessorTest.kt
└── .github/
```

---

## 九、风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| 讯飞 STT 识别准确率不足 | 用户体验差 | 备用百度 STT；iOS 考虑本地 Speech 框架 |
| LLM API 延迟/不稳定 | 等待时间长 | 规则引擎兜底 + 双模型降级策略 |
| App Store 审核被拒 | 上架延迟 | 提前研究审核要求，避免常见拒审原因 |
| 用户对语音输入不习惯 | 使用率低 | 支持文字输入作为备选 |
| 规则引擎误判 | 错误分类 | 0.85 阈值保守策略 + ConfirmSheet 确认 |
| Swift ↔ Kotlin 规则引擎行为不一致 | 双平台体验差异 | 共享测试用例集，保持行为对齐 |

---

## 十、成本预估

### API 成本（单用户/月）

| 项目 | 费用 |
|------|------|
| LLM API (GPT-4o-mini) | ~$0.01/月 |
| STT (讯飞免费额度) | ¥0 (500次/天免费) |
| **合计** | **< ¥0.5/月** |

### 服务器成本

| 规模 | 方案 | 费用 |
|------|------|------|
| < 1000 用户 | 无服务器（纯本地） | ¥0 |
| 1000-10000 用户 | 轻量云服务器 | ~¥100/月 |
| 10000+ 用户 | 云服务器 + 托管数据库 | ~¥500/月 |

---

## 十一、变现模式

| 模式 | 价格 | 说明 |
|------|------|------|
| 免费版 | ¥0 | 基础功能 + 每日 10 次 AI 语音（规则引擎不计数） |
| Pro 订阅 | ¥12/月 或 ¥98/年 | 无限语音 + AI 查询 + 云同步 |
| 一次性买断 | ¥68 | 终身基础功能（不含 AI 高级功能） |
