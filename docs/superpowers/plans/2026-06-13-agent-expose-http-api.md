# Agent 暴露为 HTTP API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `agent/` 这个 ADK-Rust Agent 从交互式 REPL 改为可被外部客户端（iOS 等）通过 HTTP `POST /chat` 调用的服务。

**Architecture:** 启用 adk-rust 的 `cli` + `server` feature，使 `adk_rust::Launcher` 自动 re-export 为 `adk_cli::Launcher`（自带 console + serve 模式）。现有 `Launcher::new(agent).run()` 几乎不变，运行 `serve` 子命令即起 HTTP 服务。由于 `adk_cli::Launcher` 的 serve API（子命令名、端口/绑定地址、`/chat` 契约）由 feature 门控且尚未下载，**本计划为「发现优先」**：Task 1-2 启用 feature 并读取真实源码确认 API，Task 3+ 按确认结果落地，并为「真机局域网必须绑 `0.0.0.0`」这一硬约束准备了具体的回退实现。

**Tech Stack:** Rust 2021、adk-rust 1.0（`cli`+`server` feature → adk-cli / adk-server）、axum（间接依赖）、tokio、本地 llama.cpp（OpenAI 兼容 API）。

**Working directory:** 所有命令在 `agent/` 下执行（仓库根：`/Users/huayang/Projects/boxs`）。即 `cd agent && ...`。

**Git 说明:** `agent/` 当前整体未被 git 跟踪（`?? agent/`）。本计划各任务的 commit 会 `git add` 指定文件（首次纳入版本控制）。**永远不要 commit `agent/.env`**（本地配置/可能含密钥），只 commit `agent/.env.example`。

**测试策略说明:** 本次改动本质是「启用框架 feature + 用框架自带的 serve 模式」，没有自定义业务逻辑可做单元测试。因此验证以**集成级 HTTP/curl 检查**为主（起服务 → `curl` 端点 → 断言响应）。仅当 Task 5 的「编程式 0.0.0.0 回退」需要执行时，那段自定义代码才有可测点，届时补一个绑定地址的单测。

---

## File Structure

| 文件 | 职责 | 本次动作 |
|------|------|----------|
| `agent/Cargo.toml` | 依赖与 feature 配置 | 修改：features 加 `cli`、`server` |
| `agent/src/main.rs` | Agent 构建 + launcher 启动 | 可能不改（feature 自动切换 launcher）；若回退则新增编程式 serve 分支 |
| `agent/src/server.rs` | （仅回退路径）编程式 `create_app` + `0.0.0.0` 绑定 | 条件创建 |
| `agent/.env` / `agent/.env.example` | 运行配置 | 修改：加 `AGENT_PORT`；仅 example 入库 |
| `agent/README.md` | 使用文档 | 修改：serve 运行方式、`/chat` 契约、真机 LAN 说明 |

---

## Task 1: 启用 `cli` + `server` feature 并编译

**Files:**
- Modify: `agent/Cargo.toml`

- [ ] **Step 1: 修改 `adk-rust` 的 features，新增 `cli` 与 `server`**

把 `agent/Cargo.toml` 中 `adk-rust` 的 features 改为：

```toml
adk-rust = { version = "1.0", features = [
    "openai",
    "ollama",
    "agents",
    "runner",
    "sessions",
    "tools",
    "cli",
    "server",
] }
```

- [ ] **Step 2: 编译，拉取并构建 adk-cli / adk-server**

Run:
```bash
cd agent && cargo build
```
Expected: 成功完成（首次会下载 adk-cli、adk-server 等并编译，耗时较长）。若报错，**完整保留报错信息**——可能需要补充 provider feature（如 `openai` 已在）或调整；不要臆测，按报错处理。

- [ ] **Step 3: Commit**

```bash
git add agent/Cargo.toml
git commit -m "feat(agent): enable adk-rust cli+server features for HTTP serve mode

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: 发现 serve 模式的真实 API（读取已下载源码）

本任务只读不改代码，目的是把后续任务从「猜测」变为「按真实 API 实现」。把发现结果记到一个临时笔记（或直接填进 Task 5 的 README 契约）。

- [ ] **Step 1: 定位已下载的 adk-cli / adk-server 源码**

Run:
```bash
ls -d ~/.cargo/registry/src/*/adk-cli-* ~/.cargo/registry/src/*/adk-server-* 2>/dev/null
```
Expected: 打印出 adk-cli 和 adk-server 的版本目录路径。

- [ ] **Step 2: 查 launcher 的 CLI 定义（子命令名、--port、--host/绑定）**

Run（把 `<ADK-CLI>` 替换为 Step 1 的 adk-cli 路径）：
```bash
ADK_CLI=$(ls -d ~/.cargo/registry/src/*/adk-cli-* | head -1)
grep -rn -E "serve|--port|--host|0\.0\.0\.0|127\.0\.0\.1|TcpListener|bind\(|Subcommand|subcommand" "$ADK_CLI/src"
```
需确认并记录：
1. serve 子命令的确切名字（是 `serve` 吗？）
2. 是否有 `--port` / `--host` 参数
3. **绑定地址是 `0.0.0.0` 还是 `127.0.0.1`**（真机联调硬前提）
4. `/chat` 的请求体字段名与响应体结构

- [ ] **Step 3: 用 `--help` 交叉验证 CLI 形状**

Run:
```bash
cd agent && cargo run -- --help 2>&1 | head -40
```
以及（若上面显示了 serve 子命令）：
```bash
cd agent && cargo run -- serve --help 2>&1 | head -40
```
Expected: 打印出顶层子命令列表（应含 `serve`）及其参数。把确切用法记下来，供 Task 3/4/5 使用。

- [ ] **Step 4: 确认 `/chat` 契约（从 adk-server 源码）**

Run（替换路径）：
```bash
ADK_SRV=$(ls -d ~/.cargo/registry/src/*/adk-server-* | head -1)
grep -rn -E "\"/chat\"|/chat|/health|/sessions|ChatRequest|Message|reply|response" "$ADK_SRV/src" | head -40
```
记录 `/chat` 的请求字段（如 `{"message": "..."}` 还是 `{"text": "..."}`）与响应字段（如 `{"reply": "..."}`），写入 Task 5 的 README。

> 本任务无代码改动，无需 commit。所有下游任务以这里确认的 API 为准。

---

## Task 3: 启动 serve 并验证 `/health` 与 `/chat`

前置：本地 llama-server 已起（默认 `http://localhost:8080/v1`），见 `agent/README.md`。`agent/.env` 已配好 `LLM_BASE_URL`/`LLM_MODEL`。

- [ ] **Step 1: 起 serve 服务（用 Task 2 确认的子命令/参数）**

按 Task 2 发现的确切写法运行，预期形如：
```bash
cd agent && cargo run -- serve --port 8081
```
Expected: 控制台输出服务监听地址（记下它是 `0.0.0.0:8081` 还是 `127.0.0.1:8081`——供 Task 4 用）。保持运行。

- [ ] **Step 2: 验证 `/health`**

另开终端：
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8081/health
```
Expected: `200`。

- [ ] **Step 3: 验证 `/chat`（用 Task 2 确认的请求体字段）**

按 Task 2 发现的字段名，预期形如：
```bash
curl -s -X POST http://127.0.0.1:8081/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"午饭花了35块"}'
```
Expected: 返回 Agent 经 LLM + 工具处理后的中文回复（HTTP 200，响应体含回复字段）。若字段名不是 `message`，按 Task 2 Step 4 的发现替换。

> 验证通过即达成「Agent 暴露为 HTTP API」的核心目标。停止服务（Ctrl-C）后继续 Task 4。

---

## Task 4: 确保真机可达 —— `0.0.0.0` 绑定

这是真机局域网联调的硬约束（Task 3 Step 1 记下的监听地址决定走哪条路）。

### 情况 A：Task 3 显示监听 `0.0.0.0:8081`（或可用 `--host 0.0.0.0` 指定）

- [ ] **Step A1: 从另一台机器/真机验证 LAN 可达**

起服务后，从 iPhone（与 Mac 同一 Wi-Fi）或另一台主机：
```
http://192.168.0.102:8081/health
```
Expected: 返回 200。或在 Mac 上用 `lsof -iTCP:8081 -sTCP:LISTEN` 确认是 `*:8081`（即 0.0.0.0）而非仅 `127.0.0.1`。

- [ ] **Step A2: 记录正确的启动参数**

若需要显式 `--host 0.0.0.0`，把它写进 Task 5 的 README 启动命令。无需改代码。跳过情况 B，进入 Task 5。

### 情况 B：Task 3 显示仅监听 `127.0.0.1`，且 launcher 不支持改绑定地址

走编程式回退：自己用 `adk_rust::server` 构建 app 并显式绑定 `0.0.0.0`。

- [ ] **Step B1: 确认 `create_app` / `ServerConfig` / `AgentLoader` / `SessionService` 的真实签名**

Run：
```bash
ADK_SRV=$(ls -d ~/.cargo/registry/src/*/adk-server-* | head -1)
grep -rn -E "pub fn create_app|pub fn create_app_with_a2a|impl ServerConfig|pub fn new|trait AgentLoader|fn load" "$ADK_SRV/src" | head -40
```
以及：
```bash
grep -rn -E "pub use|pub mod|create_app|ServerConfig|AgentLoader|SessionService" ~/.cargo/registry/src/*/adk-rust-1.0.0/src/lib.rs | head
```
记录：`create_app`（非 a2a 版）的签名、`ServerConfig::new` 入参、`AgentLoader` trait 的方法、`SessionService` 的内存实现类型（如 `InMemorySessionService`）。

- [ ] **Step B2: 新建 `agent/src/server.rs`，编程式启动并绑定 `0.0.0.0`**

依据 Step B1 的真实签名实现；结构如下（字段/方法名以 Step B1 为准，**不要照抄占位名**）：

```rust
// agent/src/server.rs
use std::sync::Arc;
use adk_rust::server::{create_app, ServerConfig}; // 按 B1 确认的确切路径/函数名
use adk_rust::session::InMemorySessionService;     // 按 B1 确认
use adk_rust::AgentLoader;                          // trait

/// 按名称加载 agent 的实现；本服务只有一个固定 agent。
struct BoxsAgentLoader {
    agent: Arc<dyn adk_rust::Agent>,
}

impl AgentLoader for BoxsAgentLoader {
    // 按 B1 确认 trait 方法签名实现（通常是 async fn load(&self, name) -> ...）
}

/// 在 0.0.0.0:port 启动 HTTP 服务，供真机局域网访问。
pub async fn serve(agent: Arc<dyn adk_rust::Agent>, port: u16) -> anyhow::Result<()> {
    let loader: Arc<dyn AgentLoader> = Arc::new(BoxsAgentLoader { agent });
    let sessions = Arc::new(InMemorySessionService::default()); // 构造方式按 B1
    let config = ServerConfig::new(loader, sessions);           // 入参按 B1
    let app = create_app(config);                               // 非 a2a 版；按 B1

    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "Boxs Agent HTTP 服务启动（0.0.0.0）");
    axum::serve(listener, app).await?;
    Ok(())
}
```

- [ ] **Step B3: 在 `main.rs` 接入 `server::serve`，取代 REPL**

在 `agent/src/main.rs` 顶部加：
```rust
mod server;
```
把 `main.rs` 末尾的 launcher 启动：
```rust
    Launcher::new(Arc::new(agent)).run().await?;
```
替换为：
```rust
    let port: u16 = std::env::var("AGENT_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8081);
    server::serve(Arc::new(agent), port).await?;
```

- [ ] **Step B4: 编译**

```bash
cd agent && cargo build
```
Expected: 成功。若有类型不匹配，回到 B1 校对真实签名后修正（不要硬凑）。

- [ ] **Step B5: 加一个绑定地址单测（这段是自定义代码，值得测）**

在 `agent/src/server.rs` 末尾加：
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_address_is_wildcard() {
        // 确保我们构造的是 0.0.0.0 而非回环
        let port = 8081u16;
        let addr = format!("0.0.0.0:{port}");
        assert_eq!(addr, "0.0.0.0:8081");
        assert!(!addr.starts_with("127.0.0.1"));
    }
}
```
Run:
```bash
cd agent && cargo test bind_address_is_wildcard
```
Expected: PASS。

- [ ] **Step B6: 起 + 验证 0.0.0.0 + 验证 /health、/chat**

```bash
cd agent && AGENT_PORT=8081 cargo run
```
另开终端：
```bash
lsof -iTCP:8081 -sTCP:LISTEN   # 期望显示 *:8081
curl -s -o /dev/null -w "%{http_code}\n" http://0.0.0.0:8081/health   # 200
```

- [ ] **Step B7: Commit（情况 B 才执行）**

```bash
git add agent/src/server.rs agent/src/main.rs
git commit -m "feat(agent): programmatic adk-server with explicit 0.0.0.0 bind for LAN access

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: 配置与文档（`.env.example` + `README.md`）

- [ ] **Step 1: 在 `agent/.env` 与 `agent/.env.example` 增加 `AGENT_PORT`**

两个文件末尾各加（情况 A 用 launcher `--port` 时，此变量供文档/脚本参考；情况 B 是实际生效的端口源）：
```env
# Agent HTTP 服务端口（避开 llama-server:8080、boxs-server:8000）
AGENT_PORT=8081
```

- [ ] **Step 2: 更新 `agent/README.md`——新增「作为 HTTP 服务运行」小节**

在「使用步骤」之后插入（命令与 `/chat` 字段以 Task 2 发现为准）：

````markdown
## 作为 HTTP 服务运行（供 iOS / 外部客户端调用）

### 启动

```bash
# 先起 llama-server（见上文），再起 agent 的 HTTP 服务
cargo run -- serve --port 8081
```

服务监听 `0.0.0.0:8081`（真机与 Mac 同一 Wi-Fi 即可访问）。

### 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/chat` | 发送自然语言，返回 Agent 回复 |
| GET  | `/sessions` | 列出会话 |
| GET  | `/health` | 健康检查 |

#### `/chat` 示例

> ⚠️ 字段名以实际为准（见下）；本节在 Task 2 确认后回填确切字段。

```bash
curl -X POST http://192.168.0.102:8081/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"午饭花了35块"}'
```

响应示例：
```json
{ "reply": "已记录：餐饮 ¥35.00" }
```

### 真机局域网访问

- 服务绑定 `0.0.0.0`，iPhone 与 Mac 同一 Wi-Fi 即可。
- 替换 `192.168.0.102` 为 Mac 的实际局域网 IP（`ipconfig getifaddr en0`）。
- 注意路由器是否开启了「AP 隔离 / 客户端隔离」——开启会阻断设备互访。
````

- [ ] **Step 3: 把 Task 2 发现的确切 `/chat` 字段回填进 README**

用 Task 2 Step 4 确认的请求/响应字段，替换上面 `⚠️` 处的 `message` / `reply` 占位。

- [ ] **Step 4: Commit（只入库 `.env.example` 与 `README.md`，**不含 `.env`**）**

```bash
git add agent/.env.example agent/README.md
git commit -m "docs(agent): document HTTP serve mode, /chat contract, and LAN access

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: 真机局域网联调验证（手动）

- [ ] **Step 1: Mac 起 llama-server，再起 agent HTTP 服务**

```bash
# 终端1
llama-server -m ~/models/Qwen3-8B-Q4_K_M.gguf -c 4096 -ngl 99 --port 8080
# 终端2
cd /Users/huayang/Projects/boxs/agent && cargo run -- serve --port 8081   # 或情况 B 的 AGENT_PORT 方式
```

- [ ] **Step 2: iPhone（同一 Wi-Fi）访问健康检查**

iPhone Safari 访问 `http://192.168.0.102:8081/health`，Expected: 返回成功（200 / JSON）。

- [ ] **Step 3: iPhone 发一句话验证 `/chat`**

用任意 HTTP 工具（如 Safari + 在线 curl、或 iOS 侧临时代码）`POST http://192.168.0.102:8081/chat`，body 用 Task 2 确认的字段，内容如「今天跑了5公里」。
Expected: 收到 Agent 中文回复（如「已打卡：运动 ✓」）。

- [ ] **Step 4: 记录结果**

把真机联调的成功截图/输出贴回会话，确认验收标准全部达成。

---

## 验收标准（对照 spec §10）

- [ ] `serve` 能起 HTTP 服务，`GET /health` 返回 200。
- [ ] `POST /chat` 接收一句话，返回经 LLM + 工具处理的回复。
- [ ] 服务绑定 `0.0.0.0`，iPhone 真机同 Wi-Fi 可访问（Task 4 + Task 6）。
- [ ] `agent/README.md` 更新了运行方式与 `/chat` 契约。
- [ ] 5 个工具行为不回归（serve 模式只改入口，工具实现未动）。
