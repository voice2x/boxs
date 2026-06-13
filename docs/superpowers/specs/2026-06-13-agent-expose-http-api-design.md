# Agent 暴露为 HTTP API — 设计文档

- 日期：2026-06-13
- 范围：`agent/` crate
- 方案：A — 使用 ADK-Rust 内置 server（`cli` feature + `adk_cli::Launcher` 的 `serve` 模式）

## 1. 背景与目标

`agent/` 是基于 ADK-Rust 的本地 AI Agent，由本地 LLM（llama.cpp / Ollama，OpenAI 兼容 API）驱动，提供生活记录助手能力（记账、习惯打卡、备忘、查询、系统信息）。

当前 `agent/src/main.rs` 通过 `adk_rust::Launcher`（实为 `adk_runner::Launcher`，`runner` feature）跑一个**交互式 REPL**，只能从 stdin 读输入。

**目标**：把 Agent 暴露为 HTTP 服务，让外部客户端（iOS App、其他服务）能通过网络调用 Agent，发送自然语言、获取回复。

**非目标（本次不做，YAGNI）**：
- 工具真正落库（`record_expense` 等仍保留现状；对接 boxs-server 是独立的扩展方向）。
- 流式响应（SSE）。
- A2A 多 Agent 协作。
- 鉴权（v1 LAN 开发不强制；见 §8）。

## 2. 方案选择

在三种方案中选定 **方案 A**：

| 方案 | 做法 | 取舍 |
|------|------|------|
| **A（选定）** | 启用 ADK `cli` feature，用内置 `adk_cli::Launcher` 的 serve 模式 | 代码最少、忠于框架、自带 `POST /chat` 等端点；端点形状由框架定义 |
| B | 自写极简 axum + `Runner::run_str` | API 形状完全可控，但要自己接 Runner、重复造薄层 |
| C | `adk-server` 编程式 `create_app` | 标准协议 + 编程控制权，但需吃透 adk-server API、接线较多 |

选 A 的理由：消费者是自有 iOS App，需要一个能发一句话拿回复的端点；ADK serve 模式正好提供简单的 `POST /chat`，且启用 `cli` feature 后 launcher 自动切换，改动最小。

## 3. 核心机制（依据已读 crate 源码）

`adk-rust` 1.0.0 的 `lib.rs` 中，`Launcher` 的 re-export 由 feature 决定：

```rust
// adk-rust-1.0.0/src/lib.rs
#[cfg(all(feature = "runner", not(feature = "cli")))]
pub use adk_runner::Launcher;   // 简单 REPL（当前在用）

#[cfg(feature = "cli")]
pub use adk_cli::Launcher;       // 全功能 CLI launcher：console + serve 模式
```

启用 `cli` feature 后，`use adk_rust::Launcher` 自动解析为带 serve 模式的 `adk_cli::Launcher`，**`main.rs` 里的 `Launcher::new(Arc::new(agent)).run()` 无需改动**即可获得 CLI 子命令解析能力。

ADK serve 模式提供的端点（来自 adk-rust `lib.rs` 文档）：

- `POST /chat` — 发送消息，返回 Agent 回复
- `GET /sessions` — 列出会话
- `GET /health` — 健康检查

运行示例（文档）：`cargo run -- serve --port 8080`。

## 4. 代码改动

### 4.1 `agent/Cargo.toml`

在 `adk-rust` 的 features 列表中新增 `cli`：

```toml
adk-rust = { version = "1.0", features = [
    "openai",
    "ollama",
    "agents",
    "runner",
    "sessions",
    "tools",
    "cli",     # 新增：启用 adk_cli::Launcher（serve 模式）
] }
```

> 若启用 `cli` 后编译报缺少 server 能力，则同时启用 `server` feature（拉入 `adk-server`）。实现时以编译结果为准。

### 4.2 `agent/src/main.rs`

**Agent 构建逻辑完全不变**（`LlmAgentBuilder` + 5 个 `FunctionTool` + 本地模型）。

唯一变化是 `Launcher` 的来源在 `cli` feature 下自动切换为 `adk_cli::Launcher`，`.run()` 会解析 CLI 子命令。因此：

- `cargo run` / `cargo run -- serve --port 8081`：HTTP serve 模式（新默认形态）。
- （若 launcher 仍保留 console 子命令）`cargo run -- chat` 之类：保留交互式 REPL 作为可选。

确切子命令名与参数（`serve`、`--port`、绑定地址）在实现时按 `adk_cli::Launcher` 的实际 CLI 定义确认并补到 README。

### 4.3 `agent/.env` / `agent/.env.example`

新增：

```env
# Agent HTTP 服务端口（避开 llama-server:8080、boxs-server:8000）
AGENT_PORT=8081
```

## 5. 运行方式

```bash
cd agent
cargo run -- serve --port 8081
```

serve 模式取代交互式 REPL 作为默认运行形态。

## 6. iOS 对接

Agent 作为独立服务，与 boxs-server（`:8000`）并列：

```
iOS ──► POST http://<host>:8081/chat   (Agent，自然语言→回复)
   ──► http://<host>:8000/api/...       (boxs-server，业务数据)
```

`/chat` 的请求/响应 JSON 确切字段在实现时按 `adk_cli` 实际形状整理一份契约，更新到 `agent/README.md` 供 iOS 端使用。

## 7. 真机局域网访问（关键风险）

延续此前 iOS 真机联调的约束，Agent 服务必须绑定 **`0.0.0.0`** 才能被真机访问：

- 若 `adk_cli::Launcher` serve 模式默认绑定回环（`127.0.0.1`），真机无法访问。
- **回退策略**：若 launcher 不暴露绑定地址参数，则改走方案 C 形态——编程式构建 `adk_rust::server::create_app(...)` 并显式 `tokio::net::TcpListener::bind("0.0.0.0:8081")` + `axum::serve`，保证 LAN 可达。
- 实现时第一步即验证绑定地址；这是真机联调的硬性前提。

iOS 端为原生 HTTP 调用，无浏览器 CORS 问题。

## 8. 鉴权 / 安全

- v1 不加鉴权（LAN 开发）。
- 若未来需要：优先看 `adk_cli::Launcher` 是否支持中间件 / API key；不支持则切方案 C 的编程式路径加薄层（`AGENT_API_KEY` 校验中间件）。
- 本地 LLM 的 `Authorization` 头（llama.cpp 的 `not-needed` 占位 key）与对外 HTTP 服务无关。

## 9. 需在实现时确认的点

1. `adk_cli::Launcher` 的确切 serve 子命令写法、`--port` 参数、**绑定地址是否为 `0.0.0.0`**。
2. `cli` feature 单独是否足够，是否需要同时启用 `server`。
3. `/chat` 请求/响应 JSON 结构（产出 iOS 契约）。
4. 是否保留 console REPL 子命令（决定 README 交互示例是否保留）。

以上均不影响方案成立，属实现细节，在「writing-plans」产出的实现计划中逐项落地。

## 10. 验收标准

- `cargo run -- serve --port 8081` 能起 HTTP 服务，`GET /health` 返回正常。
- `POST /chat` 接收一句话，返回 Agent 经 LLM + 工具处理后的回复。
- 服务绑定 `0.0.0.0`，iOS 真机（与 Mac 同一 Wi-Fi）能访问到。
- `agent/README.md` 更新运行方式与 `/chat` 契约。
- 现有 5 个工具行为不回归（serve 模式仅改变入口，不改工具实现）。

## 11. 参考资料

- adk-cli Launcher：https://docs.rs/adk-cli/latest/adk_cli/launcher/struct.Launcher.html
- adk_cli::launcher 模块：https://docs.rs/adk-cli/latest/adk_cli/launcher/index.html
- zavora-ai/adk-rust（GitHub）：https://github.com/zavora-ai/adk-rust
- crates.io/adk-cli：https://crates.io/crates/adk-cli
