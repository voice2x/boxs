# P0 iOS MVP 实施计划 — 详细 Task 拆解

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3 周内完成 iOS MVP：用户通过语音或文字输入一句话，系统自动识别意图并完成记账/打卡/备忘。

**Architecture:** Rust 后端提供 Auth + NLU + STT + Data CRUD API；iOS App (Swift/SwiftUI) 本地优先，内置 Swift 原则引擎处理简单输入，复杂输入走后端 LLM 代理。

**Tech Stack:** Rust/Axum/sqlx + Swift/SwiftUI/GRDB + PostgreSQL + OpenAI/智谱 LLM + 讯飞 STT

---

## Task 1: Rust 项目初始化

**Files:**
- Create: `boxs-server/Cargo.toml`
- Create: `boxs-server/.env.example`
- Create: `boxs-server/src/main.rs`
- Create: `boxs-server/src/config.rs`
- Create: `boxs-server/src/error.rs`
- Create: `boxs-server/src/state.rs`

- [ ] **Step 1: 创建 Rust 项目目录**

```bash
cd /Users/huayang/Projects/boxs
cargo init boxs-server
cd boxs-server
```

- [ ] **Step 2: 编写 Cargo.toml**

```toml
[package]
name = "boxs-server"
version = "0.1.0"
edition = "2024"

[dependencies]
axum = { version = "0.8", features = ["ws", "macros"] }
tokio = { version = "1", features = ["full"] }
tungstenite = "0.26"
tokio-tungstenite = "0.26"
reqwest = { version = "0.12", features = ["json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
jsonwebtoken = "9"
argon2 = "0.5"
sqlx = { version = "0.8", features = ["runtime-tokio", "tls-rustls", "postgres", "chrono", "uuid"] }
hmac = "0.12"
sha2 = "0.10"
base64 = "0.22"
lettre = "0.11"
dotenvy = "0.15"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
futures-util = "0.3"
thiserror = "2"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }
rand = "0.8"
hex = "0.4"
tower-http = { version = "0.6", features = ["cors"] }
```

- [ ] **Step 3: 编写 config.rs**

```rust
// src/config.rs

#[derive(Debug, Clone)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub jwt_secret: String,
    pub llm_api_key: String,
    pub llm_base_url: String,
    pub llm_model: String,
    pub llm_timeout_secs: u64,
    pub xfyun_app_id: String,
    pub xfyun_api_key: String,
    pub xfyun_api_secret: String,
    pub max_ws_connections: usize,
}

impl Config {
    pub fn from_env() -> Self {
        let host = dotenvy::var("POSTGRES_HOST").unwrap_or_else(|_| "localhost".into());
        let port = dotenvy::var("POSTGRES_PORT").unwrap_or_else(|_| "5432".into());
        let user = dotenvy::var("POSTGRES_USER").unwrap_or_else(|_| "boxs".into());
        let password = dotenvy::var("POSTGRES_PASSWORD").expect("POSTGRES_PASSWORD required");
        let database_url = dotenvy::var("DATABASE_URL")
            .unwrap_or_else(|_| format!("postgresql://{}:{}@{}:{}/boxs", user, password, host, port));

        Self {
            host: dotenvy::var("HOST").unwrap_or_else(|_| "0.0.0.0".into()),
            port: dotenvy::var("PORT").unwrap_or_else(|_| "8000".into()).parse().unwrap(),
            database_url,
            jwt_secret: dotenvy::var("JWT_SECRET").expect("JWT_SECRET required"),
            llm_api_key: dotenvy::var("LLM_API_KEY").unwrap_or_default(),
            llm_base_url: dotenvy::var("LLM_BASE_URL").unwrap_or_else(|_| "https://api.openai.com/v1".into()),
            llm_model: dotenvy::var("LLM_MODEL").unwrap_or_else(|_| "gpt-4o-mini".into()),
            llm_timeout_secs: dotenvy::var("LLM_TIMEOUT_SECS").unwrap_or_else(|_| "5".into()).parse().unwrap(),
            xfyun_app_id: dotenvy::var("XFYUN_APP_ID").unwrap_or_default(),
            xfyun_api_key: dotenvy::var("XFYUN_API_KEY").unwrap_or_default(),
            xfyun_api_secret: dotenvy::var("XFYUN_API_SECRET").unwrap_or_default(),
            max_ws_connections: dotenvy::var("MAX_WS_CONNECTIONS").unwrap_or_else(|_| "10000".into()).parse().unwrap(),
        }
    }
}
```

- [ ] **Step 4: 编写 error.rs** — 从 `specs/12-rust-backend.md` §十 复制完整 `AppError` enum + `IntoResponse` impl + `From<sqlx::Error>` + `From<reqwest::Error>`

- [ ] **Step 5: 编写 state.rs** — 从 specs §十二 复制 `AppState` struct + `new()` + `inc_ws()/dec_ws()/active_ws()`

- [ ] **Step 6: 编写 main.rs 骨架** — 路由注册（所有 handler 先 `todo!()` 占位），启动服务 + 数据库迁移。从 specs §十三 复制完整 main.rs

- [ ] **Step 7: 创建占位模块文件**

```
src/auth/{mod,password,jwt,handler,middleware,email}.rs
src/routes/{mod,auth,nlu,data,stt,health}.rs
src/llm/{mod,client,quota,prompts}.rs
src/stt/{mod,relay,xfyun}.rs
src/data/{mod,expense,habit,todo}.rs
```

每个 handler 函数先用 `todo!()` 占位。

- [ ] **Step 8: 创建 .env.example**

```bash
HOST=0.0.0.0
PORT=8000
RUST_LOG=info
MAX_WS_CONNECTIONS=10000
POSTGRES_HOST=115.191.21.194
POSTGRES_PORT=7450
POSTGRES_USER=boxs
POSTGRES_PASSWORD=change-me
JWT_SECRET=change-me-to-random-32-chars
LLM_API_KEY=sk-xxx
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
LLM_TIMEOUT_SECS=5
XFYUN_APP_ID=xxx
XFYUN_API_KEY=xxx
XFYUN_API_SECRET=xxx
```

- [ ] **Step 9: 验证编译通过**

Run: `cd boxs-server && cargo check`
Expected: 编译通过（可能有 unused warnings，正常）

- [ ] **Step 10: Commit**

```bash
git add boxs-server/
git commit -m "feat(boxs-server): init project skeleton with config, error, state"
```

---

## Task 2: 数据库迁移

**Files:**
- Create: `boxs-server/migrations/001_users.sql`
- Create: `boxs-server/migrations/002_business.sql`
- Create: `boxs-server/migrations/003_usage.sql`
- Create: `boxs-server/migrations/004_housekeeping.sql`

- [ ] **Step 1-4: 从 `specs/03-architecture.md` §三 复制 4 个迁移 SQL 文件**

001_users.sql → users + refresh_tokens + email_verifications
002_business.sql → expense_records + habit_definitions + habit_records + todo_records + action_logs
003_usage.sql → llm_usage_logs + llm_usage_daily + stt_usage_logs + stt_usage_daily
004_housekeeping.sql → 清理任务（注释形式）

- [ ] **Step 5: 本地验证迁移**

```bash
cd boxs-server && cp .env.example .env
docker compose up -d postgres
cargo run
```

Expected: 日志显示 "数据库迁移完成"

- [ ] **Step 6: Commit**

```bash
git add boxs-server/migrations/
git commit -m "feat(boxs-server): add database migration scripts"
```

---

## Task 3: Auth 认证模块

**Files:**
- Modify: `boxs-server/src/auth/` 全部文件

- [ ] **Step 1-5: 从 `specs/12-rust-backend.md` §五 复制完整实现**

- `auth/mod.rs` — User, UserResponse, AuthResponse, RegisterRequest, LoginRequest, RefreshRequest, ChangePasswordRequest
- `auth/password.rs` — Argon2 hash/verify
- `auth/jwt.rs` — sign_access_token, verify_access_token, generate_refresh_token, hash_refresh_token
- `auth/handler.rs` — register, login, refresh, logout, change_password, me
- `auth/middleware.rs` — require_auth
- `auth/email.rs` — send_verification, verify_code

- [ ] **Step 6: 验证编译**

Run: `cargo check`

- [ ] **Step 7: 手动测试注册/登录**

```bash
cargo run &
curl -X POST http://localhost:8000/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"123456"}'
```

Expected: 返回 `{ "user": {...}, "access_token": "...", "refresh_token": "..." }`

- [ ] **Step 8: Commit**

```bash
git add boxs-server/src/auth/
git commit -m "feat(boxs-server): implement auth module (register, login, JWT, refresh)"
```

---

## Task 4: LLM 代理模块

**Files:**
- Modify: `boxs-server/src/llm/` + `src/routes/nlu.rs`

- [ ] **Step 1: 实现 llm/client.rs** — 从 specs §六 复制 LlmClient + chat() 方法

- [ ] **Step 2: 实现 llm/quota.rs** — 从 specs §六 复制 check_quota + record_usage

- [ ] **Step 3: 实现 llm/prompts.rs** — 从 specs §五 + `05-nlu-prompts.md` 实现 classify_prompt, query_prompt, correct_prompt

- [ ] **Step 4: 实现 routes/nlu.rs** — classify, query, correct 三个 handler

- [ ] **Step 5: 验证 + 手动测试**

Run: `cargo run`，用 curl + Bearer token 测试 `/api/nlu/classify`

- [ ] **Step 6: Commit**

```bash
git add boxs-server/src/llm/ boxs-server/src/routes/nlu.rs
git commit -m "feat(boxs-server): implement LLM proxy module"
```

---

## Task 5: STT 语音透传模块

**Files:**
- Modify: `boxs-server/src/stt/` + `src/routes/stt.rs`

- [ ] **Step 1: 实现 stt/xfyun.rs** — 从 specs §七 复制 XfyunUpstream + build_auth_url + extract_text_from_response

- [ ] **Step 2: 实现 stt/relay.rs** — 从 specs §七 复制 ws_upgrade + handle_relay + pipe_up + pipe_down

- [ ] **Step 3: 实现 routes/stt.rs**

- [ ] **Step 4: 验证编译**

Run: `cargo check`

- [ ] **Step 5: Commit**

```bash
git add boxs-server/src/stt/ boxs-server/src/routes/stt.rs
git commit -m "feat(boxs-server): implement STT WebSocket relay"
```

---

## Task 6: Data CRUD 模块

**Files:**
- Modify: `boxs-server/src/data/` + `src/routes/data.rs` + `src/routes/health.rs`

- [ ] **Step 1: 实现 routes/health.rs** — `pub async fn health() -> &'static str { "OK" }`

- [ ] **Step 2: 实现 data/expense.rs** — create, list, update, delete (软删除), stats
- [ ] **Step 3: 实现 data/habit.rs** — create, list, update, delete, checkin, calendar
- [ ] **Step 4: 实现 data/todo.rs** — create, list, update, delete, complete

- [ ] **Step 5: 实现 routes/data.rs** — 注册所有 CRUD handler

- [ ] **Step 6: 手动测试 CRUD**

```bash
TOKEN="..." # 从登录获取
curl -X POST http://localhost:8000/api/data/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"type":"expense","amount_cents":3500,"category":"餐饮","note":"午饭","record_date":"2026-06-11"}'
```

- [ ] **Step 7: Commit**

```bash
git add boxs-server/src/data/ boxs-server/src/routes/
git commit -m "feat(boxs-server): implement data CRUD for expenses, habits, todos"
```

---

## Task 7: Docker 部署配置

**Files:**
- Create: `boxs-server/Dockerfile`
- Create: `boxs-server/docker-compose.yml`

- [ ] **Step 1: 从 specs §十四 复制 Dockerfile + docker-compose.yml**

- [ ] **Step 2: 验证**

```bash
cd boxs-server && docker compose up -d --build
docker compose logs -f server
```

Expected: "Boxs Server 启动" + "数据库迁移完成"

- [ ] **Step 3: Commit**

```bash
git add boxs-server/Dockerfile boxs-server/docker-compose.yml
git commit -m "feat(boxs-server): add Docker deployment config"
```

---

## Task 8: iOS 项目初始化

**Files:**
- Create: `Boxs/` Xcode 项目

- [ ] **Step 1: 创建 Xcode 项目**

在 Xcode 中创建新项目 Boxs，iOS App，SwiftUI，iOS 16+。

或命令行：
```bash
mkdir -p Boxs && cd Boxs
# 手动创建 Package.swift 或使用 xcodegen
```

- [ ] **Step 2: 配置 SPM 依赖**

```swift
// Package.swift 或 Xcode SPM
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.0"),
]
```

- [ ] **Step 3: 创建目录结构**

```
Boxs/
├── App/          (BoxsApp.swift, AppDelegate.swift)
├── Core/
│   ├── Theme/
│   ├── Database/
│   ├── Network/
│   ├── NLU/
│   ├── STT/
│   └── Constants/
├── Models/
├── ViewModels/
├── Views/
│   ├── Components/
│   └── Pages/
└── Resources/
```

- [ ] **Step 4: 最小 BoxsApp.swift**

```swift
import SwiftUI

@main
struct BoxsApp: App {
    var body: some Scene {
        WindowGroup {
            MainPage()
        }
    }
}
```

- [ ] **Step 5: 验证运行**

Run: `xcodebuild build` 或 Xcode Run
Expected: App 启动显示空白 MainPage

- [ ] **Step 6: Commit**

```bash
git add Boxs/
git commit -m "feat(boxs): init iOS project with SPM dependencies"
```

---

## Task 9: iOS 主题系统

**Files:**
- Create: `Boxs/Core/Theme/AppColors.swift`
- Create: `Boxs/Core/Theme/AppSpacing.swift`
- Create: `Boxs/Core/Theme/AppRadius.swift`
- Create: `Boxs/Core/Theme/AppSize.swift`
- Create: `Boxs/Core/Theme/AppTypography.swift`

- [ ] **Step 1: 实现 AppColors.swift** — 从 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §六 复制 SwiftUI 版本（亮色 + 暗色全套色值）。包含 `AppColors` struct、`AppColorsKey` EnvironmentKey、`EnvironmentValues.appColors` 扩展。

- [ ] **Step 2: 实现 AppSpacing.swift** — `enum S { static let page: CGFloat = 16, card = 12, item = 4, row = 8 }`（完整值见 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §三）

- [ ] **Step 3: 实现 AppRadius.swift** — `enum R { static let card: CGFloat = 10, button = 8, tag = 6 }`

- [ ] **Step 4: 实现 AppSize.swift** — `enum Sz { static let listItem: CGFloat = 44, button = 36, voiceIdle = 40 }`

- [ ] **Step 5: 实现 AppTypography.swift** — 紧凑字号定义（14pt 主文字 / 12pt 副文字 / 15pt 金额 / 26pt 大金额）

- [ ] **Step 6: 验证编译**

Run: `xcodebuild build`

- [ ] **Step 7: Commit**

```bash
git add Boxs/Core/Theme/
git commit -m "feat(boxs): implement theme system"
```

---

## Task 10: iOS 本地数据库 (GRDB)

**Files:**
- Create: `Boxs/Core/Database/AppDatabase.swift`
- Create: `Boxs/Core/Database/ExpenseRecord.swift`
- Create: `Boxs/Core/Database/HabitDefinition.swift`
- Create: `Boxs/Core/Database/HabitRecord.swift`
- Create: `Boxs/Core/Database/TodoRecord.swift`

- [ ] **Step 1: 定义 GRDB 表模型** — 每个 record 为 `Codable + FetchableRecord + PersistableRecord`。字段与服务端 PostgreSQL 对齐（见 [`specs/03-architecture.md`](../../../specs/03-architecture.md) §三），用 camelCase。

表模型清单：`ExpenseRecord`、`HabitDefinition`、`HabitRecord`、`TodoRecord`。金额统一 `amountCents: Int`（分）。

- [ ] **Step 2: 实现 AppDatabase.swift** — DatabaseQueue + DatabaseMigrator，创建 v1 迁移建表。参考 [`native-architecture-design.md`](../specs/2026-06-11-native-architecture-design.md) §八。

- [ ] **Step 3: 验证编译 + 数据库创建测试**

Run: `xcodebuild build`

- [ ] **Step 4: Commit**

```bash
git add Boxs/Core/Database/ Boxs/Models/
git commit -m "feat(boxs): add local SQLite database with GRDB"
```

---

## Task 11: iOS 网络层

**Files:**
- Create: `Boxs/Core/Network/APIClient.swift`
- Create: `Boxs/Core/Network/TokenManager.swift`
- Create: `Boxs/Core/Network/Endpoints.swift`

- [ ] **Step 1: 实现 TokenManager.swift** — Keychain 存取 JWT。完整实现见 [`specs/12-rust-backend.md`](../../../specs/12-rust-backend.md) §十六（TokenManager + KeychainHelper）。

- [ ] **Step 2: 实现 APIClient.swift** — URLSession + async/await + 自动刷新。完整实现见 [`specs/12-rust-backend.md`](../../../specs/12-rust-backend.md) §十六（APIClient + APIError）。

- [ ] **Step 3: 实现 Endpoints.swift** — API 路径常量

- [ ] **Step 4: 验证编译**

Run: `xcodebuild build`

- [ ] **Step 5: Commit**

```bash
git add Boxs/Core/Network/
git commit -m "feat(boxs): implement API client with Keychain token management"
```

---

## Task 12: iOS NLU 规则引擎 + 测试

**Files:**
- Create: `Boxs/Core/Constants/Categories.swift`
- Create: `Boxs/Core/NLU/Preprocessor.swift`
- Create: `Boxs/Core/NLU/SingleIntentRuleEngine.swift`
- Create: `Boxs/Models/NLUResult.swift`
- Create: `BoxsTests/NLUTests/RuleEngineTests.swift`
- Create: `BoxsTests/NLUTests/PreprocessorTests.swift`

- [ ] **Step 1: 实现 Categories.swift** — 12 分类 + emoji + keywords。从 [`specs/04-nlu-design.md`](../../../specs/04-nlu-design.md) §一 复制为 Swift `enum ExpenseCategory`。

- [ ] **Step 2: 定义 NLUResult.swift** — 核心数据类型。从 [`native-architecture-design.md`](../specs/2026-06-11-native-architecture-design.md) §六 复制 `NLUResult` struct。

- [ ] **Step 3: 实现 Preprocessor.swift** — 文本清洗 + 中文数字转阿拉伯数字

- [ ] **Step 4: 实现 SingleIntentRuleEngine.swift** — 从 [`specs/06-rule-engine.md`](../../../specs/06-rule-engine.md) §一 转 Swift。正则模式 `pureAmount` / `amountWithNote` + 打卡关键词匹配。

- [ ] **Step 5: 编写 XCTest 测试**

```swift
final class RuleEngineTests: XCTestCase {
    let engine = SingleIntentRuleEngine()

    func testPureAmount() throws {
        let result = try XCTUnwrap(engine.tryMatch("35"))
        XCTAssertEqual(result.intent, "expense")
        XCTAssertEqual(result.amount, 35.0)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.85)
    }

    func testAmountWithNote() throws {
        let result = try XCTUnwrap(engine.tryMatch("午饭35"))
        XCTAssertEqual(result.intent, "expense")
        XCTAssertEqual(result.amount, 35.0)
        XCTAssertEqual(result.note, "午饭")
    }

    func testCheckinKeyword() throws {
        let result = try XCTUnwrap(engine.tryMatch("跑步打卡"))
        XCTAssertEqual(result.intent, "habit_checkin")
    }

    func testComplexInputReturnsNil() {
        XCTAssertNil(engine.tryMatch("这个月花了多少"))
        XCTAssertNil(engine.tryMatch("把上一条改成40"))
    }
}
```

- [ ] **Step 6: 运行测试**

Run: `xcodebuild test -scheme Boxs -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: 全部 PASS

- [ ] **Step 7: Commit**

```bash
git add Boxs/Core/Constants/ Boxs/Core/NLU/ Boxs/Models/ BoxsTests/
git commit -m "feat(boxs): implement preprocessor and single-intent rule engine with tests"
```

---

## Task 13: iOS 分句切割器 + 多意图引擎

**Files:**
- Create: `Boxs/Core/NLU/SentenceSplitter.swift`
- Create: `Boxs/Core/NLU/MultiIntentEngine.swift`
- Create: `BoxsTests/NLUTests/SentenceSplitterTests.swift`
- Create: `BoxsTests/NLUTests/MultiIntentTests.swift`

- [ ] **Step 1: 实现 SentenceSplitter.swift** — 从 [`specs/06-rule-engine.md`](../../../specs/06-rule-engine.md) §二 转 Swift。显式分隔符（逗号/句号/"然后"/"还有"）+ 模式边界切割（备注+金额模式）。

- [ ] **Step 2: 实现 MultiIntentEngine.swift** — 从 [`specs/06-rule-engine.md`](../../../specs/06-rule-engine.md) §三 转 Swift。分句后每段走单意图引擎，任一段失败则整体降级给 LLM。

- [ ] **Step 3: 编写测试** — 覆盖 specs §五 所有场景

- [ ] **Step 4: 运行测试**

Run: `xcodebuild test`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add Boxs/Core/NLU/SentenceSplitter.swift Boxs/Core/NLU/MultiIntentEngine.swift BoxsTests/
git commit -m "feat(boxs): implement sentence splitter and multi-intent rule engine"
```

---

## Task 14: iOS 置信度打分 + NLU Orchestrator

**Files:**
- Create: `Boxs/Core/NLU/ConfidenceScorer.swift`
- Create: `Boxs/Core/NLU/NLUOrchestrator.swift`
- Create: `Boxs/Core/NLU/LLMClient.swift`
- Create: `Boxs/Core/NLU/ResponseParser.swift`
- Create: `BoxsTests/NLUTests/ConfidenceScorerTests.swift`

- [ ] **Step 1: 实现 ConfidenceScorer.swift** — 从 [`specs/07-confidence-and-routing.md`](../../../specs/07-confidence-and-routing.md) §二 转 Swift。乘法因子模型：金额确信度 × 分类确信度 × 长句惩罚 × 指代惩罚。

- [ ] **Step 2: 实现 LLMClient.swift** — 调用后端 `/api/nlu/classify`。从 [`specs/04-nlu-design.md`](../../../specs/04-nlu-design.md) §四 复制。

- [ ] **Step 3: 实现 ResponseParser.swift** — JSON → NLUResult

- [ ] **Step 4: 实现 NLUOrchestrator.swift** — 调度器：规则引擎 → 多意图引擎 → LLM。从 [`specs/07-confidence-and-routing.md`](../../../specs/07-confidence-and-routing.md) §五 复制。阈值 0.85。

- [ ] **Step 5: 编写置信度测试** — 验证 specs §三 的打分示例

- [ ] **Step 6: 运行全部 NLU 测试**

Run: `xcodebuild test`
Expected: 全部 PASS

- [ ] **Step 7: Commit**

```bash
git add Boxs/Core/NLU/ BoxsTests/
git commit -m "feat(boxs): implement confidence scorer and NLU orchestrator"
```

---

## Task 15: iOS 语音录制 + STT

**Files:**
- Create: `Boxs/Core/STT/AudioRecorder.swift`
- Create: `Boxs/Core/STT/STTClient.swift`

- [ ] **Step 1: 实现 AudioRecorder.swift** — AVFoundation PCM 16kHz 录音

- [ ] **Step 2: 实现 STTClient.swift** — Starscream WebSocket 连接后端 `/ws/stt?token=xxx`

- [ ] **Step 3: 验证编译**

Run: `xcodebuild build`

- [ ] **Step 4: Commit**

```bash
git add Boxs/Core/STT/
git commit -m "feat(boxs): implement audio recorder and STT WebSocket client"
```

---

## Task 16: iOS 语音按钮集成

**Files:**
- Create: `Boxs/Views/Components/VoiceButton.swift`
- Create: `Boxs/ViewModels/NLUViewModel.swift`

- [ ] **Step 1: 实现 VoiceButton.swift** — 40pt 悬浮圆形按钮，铁锈红背景，按住脉冲动画

- [ ] **Step 2: 实现 NLUViewModel.swift** — @Observable，管理 NLU 处理状态

- [ ] **Step 3: 集成录音 + STT + NLU 流水线**

按下 → 开始录音 + 连接 STT → 松开 → 停止 → 获取文字 → NLU → ConfirmSheet

- [ ] **Step 4: 验证编译**

Run: `xcodebuild build`

- [ ] **Step 5: Commit**

```bash
git add Boxs/Views/Components/VoiceButton.swift Boxs/ViewModels/NLUViewModel.swift
git commit -m "feat(boxs): integrate NLU pipeline into voice button"
```

---

## Task 17: iOS MainPage

**Files:**
- Create: `Boxs/Views/Pages/MainPage.swift`
- Create: `Boxs/Views/Components/OverviewCard.swift`
- Create: `Boxs/Views/Components/CompactListItem.swift`
- Create: `Boxs/Views/Components/AppDivider.swift`
- Create: `Boxs/ViewModels/HomeViewModel.swift`

- [ ] **Step 1: 实现 OverviewCard.swift** — 横向概览卡片（待办/账单/打卡）。从 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §四-1 复制 `OverviewCard`。

- [ ] **Step 2: 实现 CompactListItem.swift** — 44pt 行高记录行。从 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §四-2 复制 `CompactListItem`。

- [ ] **Step 3: 实现 AppDivider.swift** — 1px 分割线。从 [`specs/14-ui-theme.md`](../../../specs/14-ui-theme.md) §四-3 复制 `AppDivider`。

- [ ] **Step 4: 实现 HomeViewModel.swift** — 概览数据 + 记录列表

- [ ] **Step 5: 实现 MainPage.swift** — 顶栏 + 横向卡片 + 记录列表 + 悬浮语音按钮。参考 [`native-architecture-design.md`](../specs/2026-06-11-native-architecture-design.md) §七 的布局结构。

- [ ] **Step 6: 验证 UI 渲染**

Run: `xcodebuild build` 或 Xcode Preview

- [ ] **Step 7: Commit**

```bash
git add Boxs/Views/ Boxs/ViewModels/HomeViewModel.swift
git commit -m "feat(boxs): implement MainPage with horizontal overview cards"
```

---

## Task 18: iOS ConfirmSheet

**Files:**
- Create/Modify: `Boxs/Views/Pages/ConfirmSheet.swift`

- [ ] **Step 1: 实现 ConfirmSheet** — 显示 NLU 解析结果（记账/打卡/待办），可编辑，确认后保存到本地数据库 + toast

- [ ] **Step 2: 验证交互**

- [ ] **Step 3: Commit**

```bash
git add Boxs/Views/Pages/ConfirmSheet.swift
git commit -m "feat(boxs): implement NLU result confirmation sheet"
```

---

## Task 19: iOS 二级页面

**Files:**
- Create: `Boxs/Views/Pages/ExpenseStatsPage.swift`
- Create: `Boxs/Views/Pages/TodoListPage.swift`
- Create: `Boxs/Views/Pages/HabitCalendarPage.swift`
- Create: `Boxs/Views/Pages/RecordDetailPage.swift`
- Create: `Boxs/Views/Pages/SettingsPage.swift`
- Create: `Boxs/ViewModels/ExpenseStatsViewModel.swift`
- Create: `Boxs/ViewModels/HabitViewModel.swift`
- Create: `Boxs/ViewModels/TodoViewModel.swift`
- Create: `Boxs/ViewModels/AuthViewModel.swift`

- [ ] **Step 1: 实现各 ViewModel** — 数据 Provider

- [ ] **Step 2: 实现 ExpenseStatsPage** — 分类排行、趋势图、月/周/日切换

- [ ] **Step 3: 实现 TodoListPage** — 待办列表，按优先级排序

- [ ] **Step 4: 实现 HabitCalendarPage** — 日历热力图

- [ ] **Step 5: 实现 RecordDetailPage** — 记录详情 + 编辑/删除

- [ ] **Step 6: 实现 SettingsPage** — 账号、主题切换

- [ ] **Step 7: 验证页面导航**

Run: `xcodebuild build`，通过各入口测试页面跳转

- [ ] **Step 8: Commit**

```bash
git add Boxs/Views/Pages/ Boxs/ViewModels/
git commit -m "feat(boxs): implement all secondary pages"
```

---

## Task 20: 端到端联调 + Bug 修复

- [ ] **Step 1: 启动后端 + iOS App，测试完整流程**

1. 注册 → 登录
2. 文字输入 → 规则引擎 → 确认 → 保存
3. 语音输入 → STT → NLU → 确认 → 保存
4. 多意图输入
5. 各二级页面数据展示

- [ ] **Step 2: 修复发现的 Bug**

- [ ] **Step 3: 边界测试**

- 无网络时本地功能正常
- LLM 超时时规则引擎结果可用
- 空数据时页面显示正常
- 重复打卡防护

- [ ] **Step 4: 最终 Commit**

```bash
git add -A
git commit -m "fix(boxs): end-to-end integration fixes"
```

---

## 里程碑检查清单

P0 完成时，以下功能应全部可用：

- [ ] 用户注册 / 登录
- [ ] 语音输入 → 文字识别（STT）
- [ ] 文字输入 → 意图识别（规则引擎 + LLM）
- [ ] 一句话记账（"午饭35" → 自动分类餐饮）
- [ ] 一句话打卡（"跑步5公里" → 习惯打卡记录）
- [ ] 一句话备忘（"周五下午三点开会" → 待办提醒）
- [ ] 多意图处理（"午饭35，打车28" → 两条记账）
- [ ] 确认弹窗（可编辑后确认）
- [ ] 本地数据持久化（离线可用）
- [ ] 主页横向概览卡片（待办/账单/打卡）
- [ ] 悬浮语音按钮
- [ ] 5 个二级页面均可正常访问
- [ ] 规则引擎处理 60-70% 请求（不消耗 LLM 额度）
