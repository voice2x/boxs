# 技术架构（概览）

> **权威文档分工：** 本文档定义架构决策和全局设计。后端实现细节见 [`12-rust-backend.md`](./12-rust-backend.md)，UI/主题见 [`14-ui-theme.md`](./14-ui-theme.md)，NLU 设计见 [`04-nlu-design.md`](./04-nlu-design.md)。

## 一、整体架构

```
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│         iOS App (Swift)         │  │       Android App (Kotlin)      │
│                                 │  │                                 │
│  SwiftUI / GRDB / URLSession   │  │  Compose / Room / OkHttp        │
│  Keychain / AVFoundation       │  │  EncryptedSharedPreferences     │
│  Starscream                     │  │  MediaRecorder                  │
│                                 │  │                                 │
│  所有网络请求 → Rust Backend     │  │  所有网络请求 → Rust Backend     │
│  本地数据   → SQLite (GRDB)     │  │  本地数据   → SQLite (Room)     │
│  推送通知   → APNs              │  │  推送通知   → FCM               │
└───────────────┬─────────────────┘  └───────────────┬─────────────────┘
                │ HTTPS / WSS                        │ HTTPS / WSS
                └──────────────┬─────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                    Rust Backend                           │
│                    (boxs-server)                          │
│                                                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │
│  │ Auth     │ │ NLU      │ │ Data     │ │ STT        │ │
│  │ 注册登录  │ │ LLM 代理  │ │ CRUD    │ │ WebSocket  │ │
│  │ JWT 签发  │ │ 额度控制  │ │ 统计查询  │ │ 实时透传    │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └─────┬──────┘ │
│       │            │            │              │         │
│       └────────────┴─────┬──────┴──────────────┘         │
│                          │                               │
│                    ┌─────┴─────┐                         │
│                    │ PostgreSQL│ ← 唯一数据存储            │
│                    │ (sqlx)    │                          │
│                    └───────────┘                         │
└──────────────────────────────────────────────────────────┘
        │                │                │
        ▼                ▼                ▼
  ┌───────────┐   ┌───────────┐   ┌───────────┐
  │ PostgreSQL │   │ LLM API   │   │ 讯飞 STT  │
  │ 数据库     │   │ OpenAI/   │   │ WebSocket │
  │            │   │ 智谱      │   │           │
  └───────────┘   └───────────┘   └───────────┘
```

### 组件职责

| 组件 | 职责 | 技术 |
|------|------|------|
| **iOS App** | UI、本地存储、录音、离线可用 | Swift + SwiftUI + GRDB (SQLite) |
| **Android App** | UI、本地存储、录音、离线可用 | Kotlin + Compose + Room (SQLite) |
| **Rust Backend** | 认证、LLM 代理、STT 透传、数据 CRUD、文件上传 | Axum + Tokio + sqlx |
| **PostgreSQL** | 唯一数据存储（用户、记账、打卡、待办、用量） | 独立部署或云托管 |
| **LLM API** | 意图识别、对话查询 | OpenAI / 智谱（Rust 代理调用） |
| **讯飞 STT** | 实时语音识别（降级备用） | Rust WebSocket 透传 |
| **Apple Speech** | iOS 主力语音识别 | Speech framework（免费、可离线） |
| **Google Speech** | Android 主力语音识别 | Android Speech API（免费） |
| **APNs / FCM** | 推送通知 | iOS: APNs / Android: FCM |
| **S3** | 票据图片存储（P2 阶段） | Cloudflare R2 / AWS S3 |

---

## 二、数据存储方案

### 本地优先 + 云端同步

```
┌─────────────────────────────────────────────────────┐
│              iOS App / Android App                   │
│                                                      │
│   ┌─────────────┐         ┌──────────────────┐      │
│   │  UI 层       │←───────│  Repository 层    │      │
│   │  (SwiftUI / │         │  (统一读写入口)    │      │
│   │   Compose)  │         └────────┬─────────┘      │
│   └─────────────┘                  │                 │
│                           ┌────────┴────────┐       │
│                           ▼                 ▼        │
│                    ┌────────────┐   ┌──────────┐     │
│                    │ SQLite 本地 │   │ Rust API │     │
│                    │ (GRDB /    │   │ 云端 PG  │     │
│                    │  Room ORM) │   │ 同步目标  │     │
│                    │ 主数据源    │   └────┬─────┘     │
│                    └──────┬─────┘        │           │
│                           │              │           │
│                           └──────┬───────┘           │
│                                  ▼                   │
│                          ┌──────────────┐            │
│                          │  Sync Engine  │            │
│                          │  同步引擎      │            │
│                          └──────────────┘            │
└─────────────────────────────────────────────────────┘
```

- **所有读写先走本地 SQLite**，用户离线也能正常使用
- 网络恢复后，Sync Engine 异步同步到 PostgreSQL
- PostgreSQL 是同步目标，不是主数据源
- 即使后端宕机，App 不受影响

### 同步策略

**冲突解决：Last-Write-Wins + 操作日志**

```
同步规则：
  - 每条记录带 updated_at 时间戳
  - 同步时以时间戳较新的为准（Last-Write-Wins）
  - 删除用软删除（is_deleted = true），同步时传播删除标记
  - 操作日志保留 30 天（action_logs 表），支持误操作恢复
```

**增量同步：基于 sync_version**

```
同步协议：
  - 每条记录带 sync_version (递增整数)
  - 客户端上传：本地 sync_version > 服务端 → 更新服务端
  - 客户端拉取：WHERE updated_at > 上次同步时间
  - 批量同步：每次最多 100 条，避免大请求
  - 同步频率：网络恢复后自动触发，或 App 启动时检查
```

### 金额精度

**服务端和客户端统一使用整数（分），避免浮点误差。**

```
规则：
  - PostgreSQL: amount_cents INT（分为单位）
  - iOS 客户端: amountCents: Int（分），展示时除以 100
  - Android 客户端: amountCents: Long（分），展示时除以 100
  - NLU 规则引擎/LLM 解析：先解析为 Double，再乘以 100 取整存储
  - 展示格式化：String(format: "%.2f", Double(cents) / 100.0)
```

### 数据库 Schema

完整的 PostgreSQL 表结构。Rust 后端通过 sqlx 直连此数据库。

```sql
-- migrations/001_users.sql
-- 认证相关表

-- ── 用户表 ──
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,          -- Argon2id 哈希
  display_name TEXT,
  avatar_url TEXT,
  subscription_tier TEXT DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'pro')),
  stripe_customer_id TEXT,
  email_verified BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE users IS '用户主表';
COMMENT ON COLUMN users.password_hash IS 'Argon2id 哈希，不可逆';

-- ── 刷新令牌表 ──
-- 策略：一次性使用，刷新后旧令牌立即删除
-- 每用户最多保留 5 个活跃令牌（5 台设备）
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,             -- SHA-256 哈希，不存原文
  device_info TEXT,                     -- 设备描述（iOS Safari / Android App...）
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

COMMENT ON TABLE refresh_tokens IS '刷新令牌，一次性使用，哈希存储';
COMMENT ON COLUMN refresh_tokens.token_hash IS '令牌原文的 SHA-256 哈希';

-- ── 邮箱验证码表 ──
-- 策略：6 位数字，10 分钟有效，验证后标记 used_at
CREATE TABLE email_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,                   -- 6 位数字
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_email_verif_user ON email_verifications(user_id, created_at DESC);

COMMENT ON TABLE email_verifications IS '邮箱验证码，10 分钟有效';
```

```sql
-- migrations/002_business.sql
-- 业务数据表

-- ── 记账表 ──
-- 金额策略：以「分」为单位存储整数，避免浮点误差
--   ¥35.50 → amount_cents = 3550
--   ¥0.01  → amount_cents = 1
--   查询时除以 100 展示，Rust/客户端层做转换
CREATE TABLE expense_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer')),
  amount_cents INT NOT NULL CHECK (amount_cents >= 0),
    -- 金额（分）。INT 范围 0 ~ 2,147,483,647 即 ¥21,474,836.47，远超日常需求
  currency TEXT DEFAULT 'CNY',          -- 币种，预留多币种
  category TEXT NOT NULL,
    -- 餐饮、交通、购物、娱乐、医疗、教育、居住、服饰、数码、社交、宠物、其他
  merchant TEXT,
  note TEXT,
  record_date DATE NOT NULL,            -- 记账日期（业务日期，非创建时间）
  source TEXT NOT NULL DEFAULT 'text'
    CHECK (source IN ('voice', 'text', 'ocr')),
  is_deleted BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);
CREATE INDEX idx_expense_user_date ON expense_records(user_id, record_date DESC);
CREATE INDEX idx_expense_user_cat  ON expense_records(user_id, category);
CREATE INDEX idx_expense_deleted   ON expense_records(is_deleted)
  WHERE is_deleted = true;             -- 部分索引：只索引软删除的，加速清理任务

COMMENT ON TABLE expense_records IS '记账表，金额以分为单位存储';
COMMENT ON COLUMN expense_records.amount_cents IS '金额（分），¥35.50 存为 3550';

-- ── 习惯定义表 ──
CREATE TABLE habit_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  icon TEXT,
  unit TEXT,                            -- km、页、分钟、杯、次
  goal_value TEXT,                       -- "5km"、"30分钟"、"8杯"
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── 习惯打卡记录表 ──
-- 策略：每天每习惯只打一次（UNIQUE 约束）
-- 打卡值可修改（比如改 "3km" → "5km"），用 updated_at 追踪
CREATE TABLE habit_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id UUID NOT NULL REFERENCES habit_definitions(id) ON DELETE CASCADE,
  value TEXT,                           -- "5km"、"30页"、NULL（纯打卡无数值）
  record_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE (habit_id, record_date)        -- 每天每习惯只打一次
);
CREATE INDEX idx_habit_records_user ON habit_records(user_id, record_date DESC);

COMMENT ON TABLE habit_records IS '习惯打卡，每天每习惯一次，值可修改';

-- ── 待办/备忘表 ──
CREATE TABLE todo_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('todo', 'memo', 'idea')),
  content TEXT NOT NULL,
  remind_at TIMESTAMPTZ,                -- 提醒时间，NULL = 不提醒
  priority TEXT DEFAULT 'medium'
    CHECK (priority IN ('high', 'medium', 'low')),
  is_completed BOOLEAN DEFAULT false,
  completed_at TIMESTAMPTZ,
  is_deleted BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);
CREATE INDEX idx_todo_user     ON todo_records(user_id, created_at DESC);
CREATE INDEX idx_todo_remind   ON todo_records(user_id, remind_at)
  WHERE remind_at IS NOT NULL AND is_completed = false AND is_deleted = false;
    -- 部分索引：只索引未完成且有待提醒的，用于推送通知查询
CREATE INDEX idx_todo_deleted  ON todo_records(is_deleted)
  WHERE is_deleted = true;

-- ── 操作日志表（撤销功能）──
-- 策略：保留最近 30 天，超期由定时任务清理
CREATE TABLE action_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
  target_type TEXT NOT NULL,             -- 'expense' / 'habit' / 'todo'
  target_id UUID NOT NULL,
  snapshot JSONB,                        -- 操作前的完整数据快照，用于撤销
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_action_logs_user ON action_logs(user_id, created_at DESC);

COMMENT ON TABLE action_logs IS '操作日志，支持撤销，30 天后清理';
COMMENT ON COLUMN action_logs.snapshot IS '操作前的数据快照，撤销时恢复用';
```

```sql
-- migrations/003_usage.sql
-- 用量统计表 + 日归档表

-- ── LLM 调用明细表 ──
-- 策略：明细保留 90 天，超期聚合到 llm_usage_daily 后删除
CREATE TABLE llm_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model TEXT NOT NULL,                   -- gpt-4o-mini / glm-4-flash
  prompt_tokens INT NOT NULL DEFAULT 0,
  completion_tokens INT NOT NULL DEFAULT 0,
  total_tokens INT NOT NULL DEFAULT 0,  -- 冗余存储，避免每次相加
  intent TEXT,                           -- 识别出的意图（expense / query / correction）
  latency_ms INT,                       -- LLM 响应耗时
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_llm_usage_user_date ON llm_usage_logs(user_id, created_at DESC);

-- ── LLM 用量日归档表 ──
-- 由定时任务从 llm_usage_logs 聚合生成
-- 查询"本月用了多少"直接查此表，不需要 SUM 明细
CREATE TABLE llm_usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL,
  call_count INT NOT NULL DEFAULT 0,
  total_tokens INT NOT NULL DEFAULT 0,
  models JSONB DEFAULT '{}',            -- {"gpt-4o-mini": 8, "glm-4-flash": 2}
  intents JSONB DEFAULT '{}',           -- {"expense": 5, "query": 3}
  UNIQUE (user_id, stat_date)
);
CREATE INDEX idx_llm_daily_user_date ON llm_usage_daily(user_id, stat_date DESC);

COMMENT ON TABLE llm_usage_logs IS 'LLM 调用明细，保留 90 天';
COMMENT ON TABLE llm_usage_daily IS 'LLM 日用量归档，由定时任务聚合，长期保留';

-- ── STT 调用明细表 ──
-- 策略：同上，明细 90 天，归档到 stt_usage_daily
CREATE TABLE stt_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,                -- xfyun / baidu / volcengine
  audio_duration_ms INT,                 -- 音频时长
  language TEXT DEFAULT 'zh',
  latency_ms INT,                        -- 识别耗时
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stt_usage_user_date ON stt_usage_logs(user_id, created_at DESC);

-- ── STT 用量日归档表 ──
CREATE TABLE stt_usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL,
  call_count INT NOT NULL DEFAULT 0,
  total_duration_ms INT NOT NULL DEFAULT 0,
  providers JSONB DEFAULT '{}',          -- {"xfyun": 8, "baidu": 2}
  UNIQUE (user_id, stat_date)
);
CREATE INDEX idx_stt_daily_user_date ON stt_usage_daily(user_id, stat_date DESC);

COMMENT ON TABLE stt_usage_logs IS 'STT 调用明细，保留 90 天';
COMMENT ON TABLE stt_usage_daily IS 'STT 日用量归档，长期保留';
```

```sql
-- migrations/004_housekeeping.sql
-- 定时清理任务：用 PostgreSQL pg_cron 扩展
-- 如果托管商不支持 pg_cron，则在 Rust 后端用 tokio 定时任务执行

-- ── 每天凌晨 3 点执行 ──

-- 1. 清理过期刷新令牌
-- DELETE FROM refresh_tokens WHERE expires_at < now();

-- 2. 清理过期邮箱验证码
-- DELETE FROM email_verifications WHERE expires_at < now() AND used_at IS NULL;

-- 3. 物理删除软删除超过 30 天的记录
-- DELETE FROM expense_records
--   WHERE is_deleted = true AND deleted_at < now() - INTERVAL '30 days';
-- DELETE FROM todo_records
--   WHERE is_deleted = true AND deleted_at < now() - INTERVAL '30 days';

-- 4. 清理 30 天前的操作日志
-- DELETE FROM action_logs WHERE created_at < now() - INTERVAL '30 days';

-- 5. LLM/STT 用量归档：先聚合到日表，再删除 90 天前的明细
-- 注：聚合逻辑在 Rust 后端用 sqlx 分步执行更清晰可靠
-- DELETE FROM llm_usage_logs WHERE created_at < now() - INTERVAL '90 days';
-- DELETE FROM stt_usage_logs WHERE created_at < now() - INTERVAL '90 days';
```

### 数据安全

```
传输安全：
  - 全链路 HTTPS（Nginx TLS 终止）
  - WebSocket over TLS (wss://)

数据库安全：
  - Rust 层检查 user_id，每条 SQL 带 WHERE user_id = $1
  - 参数化查询（sqlx 宏编译期检查），无 SQL 注入风险
  - 密码 Argon2id 哈希，数据库泄露也无法还原密码

客户端安全：
  - Access Token / Refresh Token 安全存储
    iOS → Keychain（Security framework）
    Android → EncryptedSharedPreferences（AndroidX Security Crypto）
  - 本地 SQLite 可选 SQLCipher 加密（Pro 功能）
```

---

## 三、数据库托管选项

| 托管选项 | 说明 | 费用 |
|---------|------|------|
| **Neon** | Serverless PostgreSQL，自动扩缩容，有免费额度 | Free: 0.5GB / Pro: $19/月 |
| **Supabase** | 仅用 PostgreSQL 托管功能，不用 Auth/Storage | Free: 500MB / Pro: $25/月 |
| **Railway** | 简单部署，适合小项目 | $5/月起 |
| **AWS RDS** | 企业级，最灵活 | 按用量 |
| **自建** | 完全控制，运维成本高 | 服务器费用 |

**推荐**：Neon（Serverless，冷启动快，免费额度够 MVP）。

---

## 四、Rust 后端项目结构

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
│   ├── main.rs                    # 入口：启动服务、数据库迁移
│   ├── config.rs                  # 环境变量
│   ├── error.rs                   # 统一错误处理
│   ├── state.rs                   # 全局状态（DB pool、LLM client）
│   │
│   ├── auth/                      # ── 认证 ──
│   │   ├── mod.rs                 # User 模型、请求/响应类型
│   │   ├── password.rs            # Argon2 密码哈希/验证
│   │   ├── jwt.rs                 # JWT 签发/验证、刷新令牌
│   │   ├── handler.rs             # 注册/登录/刷新/登出/改密码
│   │   ├── middleware.rs          # require_auth 中间件
│   │   └── email.rs               # 邮箱验证码
│   │
│   ├── routes/                    # ── 路由注册 ──
│   │   ├── mod.rs
│   │   ├── auth.rs                # /api/auth/*
│   │   ├── nlu.rs                 # /api/nlu/*
│   │   ├── data.rs                # /api/data/*
│   │   ├── stt.rs                 # /ws/stt
│   │   └── health.rs              # /health
│   │
│   ├── llm/                       # ── LLM 代理 ──
│   │   ├── mod.rs
│   │   ├── client.rs              # HTTP 客户端调用 OpenAI/智谱
│   │   ├── quota.rs               # 额度检查（查 PG llm_usage_logs）
│   │   └── prompts.rs             # Prompt 模板
│   │
│   ├── stt/                       # ── STT 透传 ──
│   │   ├── mod.rs
│   │   ├── relay.rs               # WebSocket 双向管道
│   │   └── xfyun.rs               # 讯飞上游连接 + HMAC 签名
│   │
│   └── data/                      # ── 数据 CRUD ──
│       ├── mod.rs
│       ├── expense.rs             # 记账
│       ├── habit.rs               # 习惯打卡
│       └── todo.rs                # 待办备忘
│
├── Dockerfile
└── docker-compose.yml
```

> 后端完整实现代码见 [`12-rust-backend.md`](./12-rust-backend.md)。

---

## 五、路由总表

### 公开接口（不需要认证）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/auth/register` | 注册 |
| POST | `/api/auth/login` | 登录 |
| POST | `/api/auth/refresh` | 刷新 Token |
| GET | `/health` | 健康检查 |

### 认证接口（需要 Bearer Token）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/auth/logout` | 登出 |
| GET | `/api/auth/me` | 获取用户信息 |
| POST | `/api/auth/change-password` | 修改密码 |
| POST | `/api/auth/verify-email` | 验证邮箱 |

### NLU 接口（LLM 代理）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/nlu/classify` | 意图分类 + 实体提取 |
| POST | `/api/nlu/query` | AI 对话查询 |
| POST | `/api/nlu/correct` | 纠错 |

### 数据 CRUD 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/data/expenses` | 记账列表（分页、按月筛选） |
| POST | `/api/data/expenses` | 新增记账 |
| PUT | `/api/data/expenses/:id` | 修改记账 |
| DELETE | `/api/data/expenses/:id` | 删除记账（软删除） |
| GET | `/api/data/expenses/stats` | 记账统计（日/周/月） |
| GET | `/api/data/habits` | 习惯列表 |
| POST | `/api/data/habits` | 新增习惯 |
| PUT | `/api/data/habits/:id` | 修改习惯 |
| DELETE | `/api/data/habits/:id` | 删除习惯 |
| POST | `/api/data/habits/checkin` | 打卡 |
| GET | `/api/data/habits/calendar` | 打卡日历 |
| GET | `/api/data/todos` | 待办列表 |
| POST | `/api/data/todos` | 新增待办 |
| PUT | `/api/data/todos/:id` | 修改待办 |
| DELETE | `/api/data/todos/:id` | 删除待办（软删除） |
| POST | `/api/data/todos/:id/complete` | 完成待办 |

### WebSocket 接口

| 协议 | 路径 | 说明 |
|------|------|------|
| WS | `/ws/stt?token=xxx` | STT 实时语音识别透传 |

### 规则热更新接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/rules/config?current_version=N` | 获取最新规则配置 |

---

## 六、开发阶段

| 阶段 | 后端范围 | 数据库 | iOS | Android |
|------|---------|--------|-----|---------|
| **P0** | Auth + NLU classify + STT WebSocket | PostgreSQL | SwiftUI 基础 UI + GRDB 本地存储 + AVFoundation 录音 | Compose 基础 UI + Room 本地存储 + MediaRecorder 录音 |
| **P1** | + NLU query/correct + Data CRUD | 同上 | 完整 UI + 数据同步 + Starscream WebSocket | 完整 UI + 数据同步 + OkHttp WebSocket |
| **P2** | + 文件上传（S3）+ 邮件验证 | 同上 | Keychain 安全存储 + OCR + 推送通知 | EncryptedSharedPreferences + OCR + FCM 推送 |
| **P3** | + 数据同步 API + 推送通知 | 同上 | 多设备同步 + APNs 提醒 | 多设备同步 + FCM 提醒 |

---

## 七、各 Spec 文件索引

| 文件 | 内容 |
|------|------|
| `01-product-overview.md` | 产品定位、竞品分析 |
| `02-features.md` | 功能模块设计 |
| `03-architecture.md` | **技术架构概览（本文档）** |
| `04-nlu-design.md` | NLU 意图分类体系、处理管线 |
| `05-nlu-prompts.md` | LLM Prompt 工程 |
| `06-rule-engine.md` | 规则引擎、分句切割 |
| `07-confidence-and-routing.md` | 置信度打分、路由决策 |
| `08-development-plan.md` | 开发计划、成本估算 |
| `12-rust-backend.md` | **Rust 后端完整实现（认证 + LLM + STT + 数据 CRUD）** |
| `14-ui-theme.md` | UI 主题与视觉风格 |

> **Spec 编号说明：** 09-11、13 编号对应的文档内容已合并到现有文档中（API 细节合并到 12，UI 组件合并到 14，测试策略合并到 08），不再单独成文。
