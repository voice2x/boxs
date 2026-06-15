# Boxs Agent

基于 [ADK-Rust](https://adk-rust.com) 的本地 AI Agent，使用 llama.cpp 本地部署的 LLM 驱动，实现生活记录助手的意图识别与操作执行。

## 架构

```
用户自然语言输入
       │
       ▼
┌─────────────┐     HTTP (OpenAI 兼容 API)     ┌──────────────┐
│  ADK-Rust   │ ──────────────────────────────→ │  llama.cpp   │
│  Agent      │ ←────────────────────────────── │  llama-server│
│             │     function_call / response     │  (本地 GGUF) │
└──────┬──────┘                                  └──────────────┘
       │
       │ 本地执行工具
       ├── record_expense()   记账
       ├── record_habit()     习惯打卡
       ├── add_memo()         备忘
       ├── query_records()    查询记录
       └── get_system_info()  系统信息
```

## 前置条件

1. **llama.cpp 已安装** (你已有)

2. **下载模型** (推荐 Qwen3-8B，中文能力好):
```bash
# 方式一：直接从 HF 拉取
llama-server -hf unsloth/Qwen3-8B-GGUF:Q4_K_M -ngl 99

# 方式二：手动下载
wget "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf" \
  -O ~/models/Qwen3-8B-Q4_K_M.gguf
```

## 使用步骤

### 1. 启动 llama-server

```bash
llama-server \
  -m ~/models/Qwen3-8B-Q4_K_M.gguf \
  -c 4096 \
  -ngl 99 \
  --port 8080
```

看到 `llama server listening at http://127.0.0.1:8080` 表示就绪。

### 2. 配置 Agent

```bash
cd agent
cp .env.example .env
# 默认配置已指向 localhost:8080，无需修改
```

### 3. 运行 Agent（HTTP 服务）

```bash
cargo run
```

默认读取 `.env` 中的 `AGENT_PORT`（默认 8081），启动 HTTP 服务并监听 `0.0.0.0:8081`。
控制台看到 `Boxs Agent HTTP 服务启动（0.0.0.0），POST /api/chat` 即就绪。`Ctrl+C` 停止。

> 旧版本是交互式 REPL；启用 ADK `cli`+`server` feature 后已改为 HTTP 服务模式（`src/server.rs`）。
> ADK 自带的 `/api/run_sse`、`/api/sessions`、Web UI 等也一并可用；下面只记录给客户端用的极简 `/api/chat`。

### 4. HTTP 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/chat` | 发一句自然语言，返回 Agent（经 LLM + 工具）处理后的回复，纯 JSON，非流式 |
| `GET`  | `/api/health` | 健康检查（ADK 自带）→ `{"status":"healthy"}` |
| `GET`  | `/api/sessions` 等 | ADK 原生接口（SSE 流式，需先建会话） |

#### `/api/chat`

请求体（仅一个字段）：

```json
{ "message": "午饭花了35块" }
```

响应体：

```json
{ "reply": "已记录：餐饮 ¥35.00" }
```

行为：服务端为每次请求新建一个一次性会话、运行 Agent 一个回合、汇总文本回复后**立即删除会话**（无状态、无跨请求记忆）。请求超时 120s，请求体上限 1 MiB。任何失败返回 `500`，空回复返回 `{"reply":"（无回复）"}`。

curl 示例：

```bash
curl -X POST http://127.0.0.1:8081/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"今天跑了5公里"}'
# {"reply":"已打卡：运动 ✓"}
```

### 5. 交互示例（语义）

下列输入会触发对应工具调用并得到回复（实际经本地 LLM 意图识别）：

```
"午饭花了35块"        → record_expense → "已记录：餐饮 ¥35.00"
"今天跑了5公里"        → record_habit   → "已打卡：运动 ✓"
"周五下午三点跟老王开会" → add_memo       → "已添加备忘：跟老王开会"
"昨天打车28，奶茶15"    → record_expense ×2
"磁盘空间还剩多少"      → get_system_info → df -h 真实数据
```


## 项目结构

```
agent/
├── Cargo.toml          # 依赖配置（adk-rust cli+server feature）
├── .env.example        # 环境变量模板
├── README.md
└── src/
    ├── main.rs         # Agent 构建（5 个 FunctionTool + 本地模型）+ 启动 server::serve
    └── server.rs       # HTTP 服务：自定义 POST /api/chat（一次性运行）+ 0.0.0.0 绑定
```

## 切换模型后端

### 用 Ollama (如果你安装了)

```bash
# .env
LLM_BASE_URL=http://localhost:11434
LLM_MODEL=qwen3:8b
```

代码中把 `create_openai_model()` 替换为：

```rust
use adk_model::ollama::{OllamaModel, OllamaConfig};

let model = OllamaModel::new(OllamaConfig::new("qwen3:8b"))?;
```

### 用云端模型 (Gemini/OpenAI/Claude)

```bash
# .env
LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
LLM_MODEL=gemini-2.5-flash
GOOGLE_API_KEY=your-key
```

## 模型选择参考 (M5 24GB)

| 模型 | 量化 | 大小 | 推荐场景 |
|------|------|------|----------|
| Qwen3-4B | Q4_K_M | ~2.5 GB | 快速响应，基础能力 |
| Qwen3-8B | Q4_K_M | ~5 GB | **推荐**，中文+工具调用好 |
| Qwen3.6-35B-A3B | UD-Q4_K_M | ~20.6 GB | MoE，质量更高 |

## 扩展方向

- [ ] 对接 boxs-server 的 PostgreSQL 数据库
- [ ] 添加 STT（语音转文字）接入
- [x] 部署为 HTTP API 服务（自定义 `POST /api/chat` + ADK 原生 `/api/run_sse`）
- [ ] 添加 A2A 协议支持多 Agent 协作
- [ ] 添加 Guardrails 输入/输出安全过滤
