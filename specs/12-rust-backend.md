# Rust 后端服务（boxs-server）

统一的 Rust 后端，承担认证、LLM 代理、STT 透传、数据 CRUD 全部服务端逻辑。

## 一、整体架构

```
┌──────────────────────────────────────────────────────────┐
│              iOS App (Swift) / Android App (Kotlin)       │
│                                                          │
│  iOS:  SwiftUI, GRDB.swift, URLSession, Keychain,        │
│        AVFoundation, Starscream                          │
│  Android: Compose, Room, OkHttp, EncryptedSharedPreferences │
│                                                          │
│  所有网络请求 → Rust Backend                              │
│  本地数据   → SQLite (GRDB / Room)                        │
│  推送通知   → APNs (iOS) / FCM (Android)                  │
└──────────────────────────┬───────────────────────────────┘
                           │ HTTPS / WSS
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
| **讯飞 STT** | 实时语音识别 | Rust WebSocket 透传 |
| **Firebase FCM** | 推送通知 | 客户端直连 |
| **S3** | 票据图片存储（P2 阶段） | Cloudflare R2 / AWS S3 |

---

## 二、技术栈与依赖

### 后端（Rust）

```toml
[package]
name = "boxs-server"
version = "0.1.0"
edition = "2024"

[dependencies]
# Web 框架
axum = { version = "0.8", features = ["ws", "macros"] }
tokio = { version = "1", features = ["full"] }

# WebSocket
tungstenite = "0.26"
tokio-tungstenite = "0.26"

# HTTP 客户端（LLM 调用）
reqwest = { version = "0.12", features = ["json"] }

# 序列化
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# JWT（自签发）
jsonwebtoken = "9"

# 密码哈希
argon2 = "0.5"

# 数据库
sqlx = { version = "0.8", features = ["runtime-tokio", "tls-rustls", "postgres", "chrono", "uuid"] }

# 讯飞签名
hmac = "0.12"
sha2 = "0.10"
base64 = "0.22"

# 邮件
lettre = "0.11"

# 配置
dotenvy = "0.15"

# 日志
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# 工具
futures-util = "0.3"
thiserror = "2"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }
rand = "0.8"
hex = "0.4"
tower-http = { version = "0.6", features = ["cors"] }
```

---

## 三、项目结构

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

---

## 四、环境变量

```bash
# .env

# ── 服务 ──
HOST=0.0.0.0
PORT=8000
RUST_LOG=info
MAX_WS_CONNECTIONS=10000

# ── 数据库 ──
POSTGRES_HOST=115.191.21.194
POSTGRES_PORT=7450
POSTGRES_USER=boxs
POSTGRES_PASSWORD=your-password
# DATABASE_URL 由以上参数拼装，也可直接设置完整 URL
# DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/boxs

# ── JWT ──
JWT_SECRET=your-random-secret-at-least-32-chars

# ── LLM ──
LLM_API_KEY=sk-xxx
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
LLM_TIMEOUT_SECS=5

# ── 讯飞 STT ──
XFYUN_APP_ID=xxx
XFYUN_API_KEY=xxx
XFYUN_API_SECRET=xxx

# ── 邮件（P2 阶段）──
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=xxx@gmail.com
SMTP_PASSWORD=xxx

# ── 文件存储（P2 阶段）──
S3_ENDPOINT=https://xxx.r2.cloudflarestorage.com
S3_BUCKET=boxs-receipts
S3_ACCESS_KEY=xxx
S3_SECRET_KEY=xxx
```

---

## 五、认证模块

### 用户模型

```rust
// src/auth/mod.rs

pub mod jwt;
pub mod password;
pub mod handler;
pub mod email;

use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: uuid::Uuid,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub subscription_tier: String,
    pub email_verified: bool,
    pub is_active: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// 返回给客户端的用户信息（不含敏感字段）
#[derive(Debug, Serialize)]
pub struct UserResponse {
    pub id: String,
    pub email: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub subscription_tier: String,
    pub email_verified: bool,
    pub created_at: String,
}

impl From<User> for UserResponse {
    fn from(u: User) -> Self {
        Self {
            id: u.id.to_string(),
            email: u.email,
            display_name: u.display_name,
            avatar_url: u.avatar_url,
            subscription_tier: u.subscription_tier,
            email_verified: u.email_verified,
            created_at: u.created_at.to_rfc3339(),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub user: UserResponse,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: u64,
}

#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    pub device_info: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub old_password: String,
    pub new_password: String,
}
```

### 密码哈希

```rust
// src/auth/password.rs

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use crate::error::AppError;

/// 哈希密码（Argon2id）
pub fn hash(password: &str) -> Result<String, AppError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();

    let hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(format!("密码哈希失败: {}", e)))?;

    Ok(hash.to_string())
}

/// 验证密码
pub fn verify(password: &str, hash: &str) -> Result<bool, AppError> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| AppError::Internal(format!("哈希格式错误: {}", e)))?;

    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok())
}
```

### JWT 自签发

```rust
// src/auth/jwt.rs

use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use crate::config::Config;
use crate::error::AppError;

/// Access Token 的 Claims
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AccessTokenClaims {
    pub sub: String,           // 用户 ID
    pub email: String,
    pub tier: String,          // free / pro
    pub exp: usize,            // 过期时间
    pub iat: usize,            // 签发时间
    pub jti: String,           // 唯一 ID（防重放）
}

/// 验证结果
#[derive(Debug, Clone)]
pub struct VerifiedUser {
    pub user_id: String,
    pub email: String,
    pub tier: String,
}

/// 签发 Access Token（15 分钟有效）
pub fn sign_access_token(user_id: &str, email: &str, tier: &str, config: &Config) -> Result<String, AppError> {
    let now = chrono::Utc::now();
    let claims = AccessTokenClaims {
        sub: user_id.to_string(),
        email: email.to_string(),
        tier: tier.to_string(),
        exp: (now + chrono::Duration::minutes(15)).timestamp() as usize,
        iat: now.timestamp() as usize,
        jti: uuid::Uuid::new_v4().to_string(),
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(config.jwt_secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(format!("JWT 签发失败: {}", e)))
}

/// 验证 Access Token
pub fn verify_access_token(token: &str, jwt_secret: &str) -> Result<VerifiedUser, AppError> {
    let mut validation = Validation::default();
    validation.set_audience(&[]);

    let token_data = decode::<AccessTokenClaims>(
        token,
        &DecodingKey::from_secret(jwt_secret.as_bytes()),
        &validation,
    )
    .map_err(|e| match e.kind() {
        jsonwebtoken::errors::ErrorKind::ExpiredSignature => {
            AppError::Unauthorized("Token 已过期".into())
        }
        _ => AppError::Unauthorized(format!("Token 无效: {}", e)),
    })?;

    Ok(VerifiedUser {
        user_id: token_data.claims.sub,
        email: token_data.claims.email,
        tier: token_data.claims.tier,
    })
}

/// 生成刷新令牌（随机 256bit）
pub fn generate_refresh_token() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill(&mut bytes);
    hex::encode(bytes)
}

/// 哈希刷新令牌（数据库不存原文）
pub fn hash_refresh_token(token: &str) -> String {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}
```

### 认证路由处理

```rust
// src/auth/handler.rs

use axum::{extract::State, Json};
use std::sync::Arc;
use tracing::{info, instrument};

use crate::auth::{
    email, jwt, password, AuthResponse, ChangePasswordRequest, LoginRequest,
    RefreshRequest, RegisterRequest, UserResponse,
};
use crate::error::AppError;
use crate::state::AppState;

/// POST /api/auth/register
#[instrument(skip(state), fields(email = %body.email))]
pub async fn register(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RegisterRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let email = body.email.trim().to_lowercase();
    let password = body.password.trim();

    if email.is_empty() || !email.contains('@') {
        return Err(AppError::BadRequest("邮箱格式不正确".into()));
    }
    if password.len() < 6 {
        return Err(AppError::BadRequest("密码至少 6 位".into()));
    }

    let exists: bool = sqlx::query_scalar!(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
        email,
    )
    .fetch_one(&state.pool)
    .await?
    .unwrap_or(false);

    if exists {
        return Err(AppError::BadRequest("该邮箱已注册".into()));
    }

    let password_hash = password::hash(password)?;

    let user = sqlx::query_as!(
        crate::auth::User,
        r#"INSERT INTO users (email, password_hash, display_name)
           VALUES ($1, $2, $3)
           RETURNING id, email, password_hash, display_name, avatar_url,
                     subscription_tier, email_verified, is_active,
                     created_at, updated_at"#,
        email,
        password_hash,
        body.display_name,
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        if e.to_string().contains("unique") {
            AppError::BadRequest("该邮箱已注册".into())
        } else {
            AppError::from(e)
        }
    })?;

    let access_token = jwt::sign_access_token(
        &user.id.to_string(),
        &user.email,
        &user.subscription_tier,
        &state.config,
    )?;

    let refresh_token = jwt::generate_refresh_token();
    let refresh_hash = jwt::hash_refresh_token(&refresh_token);

    sqlx::query!(
        "INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
         VALUES ($1, $2, $3, $4)",
        user.id,
        refresh_hash,
        None::<String>,
        chrono::Utc::now() + chrono::Duration::days(30),
    )
    .execute(&state.pool)
    .await?;

    // 发送验证邮件（异步，不阻塞）
    let pool = state.pool.clone();
    let user_email = user.email.clone();
    let user_id = user.id.to_string();
    tokio::spawn(async move {
        let _ = email::send_verification(&pool, &user_id, &user_email).await;
    });

    info!(user_id = %user.id, "用户注册成功");

    Ok(Json(AuthResponse {
        user: UserResponse::from(user),
        access_token,
        refresh_token,
        expires_in: 900,
    }))
}

/// POST /api/auth/login
#[instrument(skip(state), fields(email = %body.email))]
pub async fn login(
    State(state): State<Arc<AppState>>,
    Json(body): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let email = body.email.trim().to_lowercase();

    let user = sqlx::query_as!(
        crate::auth::User,
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE email = $1 AND is_active = true",
        email,
    )
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::Unauthorized("邮箱或密码错误".into()))?;

    let valid = password::verify(&body.password, &user.password_hash)?;
    if !valid {
        return Err(AppError::Unauthorized("邮箱或密码错误".into()));
    }

    let access_token = jwt::sign_access_token(
        &user.id.to_string(),
        &user.email,
        &user.subscription_tier,
        &state.config,
    )?;

    let refresh_token = jwt::generate_refresh_token();
    let refresh_hash = jwt::hash_refresh_token(&refresh_token);

    // 清理旧刷新令牌（保留最新 5 个，支持 5 台设备）
    sqlx::query!(
        "DELETE FROM refresh_tokens WHERE user_id = $1 AND id NOT IN (
            SELECT id FROM refresh_tokens WHERE user_id = $1 ORDER BY created_at DESC LIMIT 4
        )",
        user.id,
    )
    .execute(&state.pool)
    .await?;

    sqlx::query!(
        "INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
         VALUES ($1, $2, $3, $4)",
        user.id,
        refresh_hash,
        body.device_info,
        chrono::Utc::now() + chrono::Duration::days(30),
    )
    .execute(&state.pool)
    .await?;

    info!(user_id = %user.id, "用户登录成功");

    Ok(Json(AuthResponse {
        user: UserResponse::from(user),
        access_token,
        refresh_token,
        expires_in: 900,
    }))
}

/// POST /api/auth/refresh
pub async fn refresh(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RefreshRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let token_hash = jwt::hash_refresh_token(&body.refresh_token);

    let token_row = sqlx::query!(
        "SELECT rt.user_id, rt.expires_at, u.email, u.subscription_tier
         FROM refresh_tokens rt
         JOIN users u ON u.id = rt.user_id
         WHERE rt.token_hash = $1 AND u.is_active = true",
        token_hash,
    )
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::Unauthorized("刷新令牌无效".into()))?;

    if token_row.expires_at < chrono::Utc::now() {
        sqlx::query!("DELETE FROM refresh_tokens WHERE token_hash = $1", token_hash)
            .execute(&state.pool)
            .await?;
        return Err(AppError::Unauthorized("刷新令牌已过期".into()));
    }

    // 删除旧刷新令牌（一次性使用）
    sqlx::query!("DELETE FROM refresh_tokens WHERE token_hash = $1", token_hash)
        .execute(&state.pool)
        .await?;

    let access_token = jwt::sign_access_token(
        &token_row.user_id.to_string(),
        &token_row.email,
        &token_row.subscription_tier,
        &state.config,
    )?;

    let new_refresh_token = jwt::generate_refresh_token();
    let new_hash = jwt::hash_refresh_token(&new_refresh_token);

    sqlx::query!(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, $3)",
        token_row.user_id,
        new_hash,
        chrono::Utc::now() + chrono::Duration::days(30),
    )
    .execute(&state.pool)
    .await?;

    let user = sqlx::query_as!(
        crate::auth::User,
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
        token_row.user_id,
    )
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(AuthResponse {
        user: UserResponse::from(user),
        access_token,
        refresh_token: new_refresh_token,
        expires_in: 900,
    }))
}

/// POST /api/auth/logout
pub async fn logout(
    State(state): State<Arc<AppState>>,
    claims: crate::auth::jwt::VerifiedUser,
) -> Result<Json<serde_json::Value>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    sqlx::query!("DELETE FROM refresh_tokens WHERE user_id = $1", uid)
        .execute(&state.pool)
        .await?;

    info!(user_id = %uid, "用户登出");
    Ok(Json(serde_json::json!({ "success": true })))
}

/// POST /api/auth/change-password
pub async fn change_password(
    State(state): State<Arc<AppState>>,
    claims: crate::auth::jwt::VerifiedUser,
    Json(body): Json<ChangePasswordRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let user = sqlx::query_as!(
        crate::auth::User,
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
        uid,
    )
    .fetch_one(&state.pool)
    .await?;

    if !password::verify(&body.old_password, &user.password_hash)? {
        return Err(AppError::BadRequest("旧密码错误".into()));
    }

    let new_hash = password::hash(&body.new_password)?;
    sqlx::query!(
        "UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2",
        new_hash,
        uid,
    )
    .execute(&state.pool)
    .await?;

    // 使所有刷新令牌失效（强制重新登录）
    sqlx::query!("DELETE FROM refresh_tokens WHERE user_id = $1", uid)
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({ "success": true })))
}

/// GET /api/auth/me
pub async fn me(
    State(state): State<Arc<AppState>>,
    claims: crate::auth::jwt::VerifiedUser,
) -> Result<Json<UserResponse>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let user = sqlx::query_as!(
        crate::auth::User,
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
        uid,
    )
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(UserResponse::from(user)))
}
```

### 邮箱验证

```rust
// src/auth/email.rs

use sqlx::PgPool;
use rand::Rng;
use tracing::{info, error};

/// 生成验证码并发送邮件
pub async fn send_verification(
    pool: &PgPool,
    user_id: &str,
    email: &str,
) -> Result<(), String> {
    let code: String = (0..6)
        .map(|_| rand::thread_rng().gen_range(0..10).to_string())
        .collect();

    let uid = uuid::Uuid::parse_str(user_id).map_err(|e| e.to_string())?;

    sqlx::query!(
        "INSERT INTO email_verifications (user_id, code, expires_at)
         VALUES ($1, $2, $3)",
        uid,
        code,
        chrono::Utc::now() + chrono::Duration::minutes(10),
    )
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    // MVP 阶段：验证码打日志。正式上线接入 SMTP 或邮件 API（Resend / SendGrid）
    info!(email = %email, code = %code, "验证码已生成");

    Ok(())
}

/// 验证邮箱验证码
pub async fn verify_code(
    pool: &PgPool,
    user_id: &str,
    code: &str,
) -> Result<bool, String> {
    let uid = uuid::Uuid::parse_str(user_id).map_err(|e| e.to_string())?;

    let row = sqlx::query!(
        "SELECT id, expires_at, used_at FROM email_verifications
         WHERE user_id = $1 AND code = $2 AND used_at IS NULL
         ORDER BY created_at DESC LIMIT 1",
        uid,
        code,
    )
    .fetch_optional(pool)
    .await
    .map_err(|e| e.to_string())?;

    match row {
        Some(row) if row.expires_at > chrono::Utc::now() => {
            sqlx::query!(
                "UPDATE email_verifications SET used_at = now() WHERE id = $1",
                row.id,
            )
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;

            sqlx::query!(
                "UPDATE users SET email_verified = true WHERE id = $1",
                uid,
            )
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;

            Ok(true)
        }
        _ => Ok(false),
    }
}
```

### 认证中间件

```rust
// src/auth/middleware.rs

use axum::{
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use std::sync::Arc;
use crate::auth::jwt::{self, VerifiedUser};
use crate::error::AppError;
use crate::state::AppState;

/// Axum 中间件：从请求头提取并验证 JWT
pub async fn require_auth(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| AppError::Unauthorized("缺少 Authorization 头".into()))?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or_else(|| AppError::Unauthorized("Authorization 格式错误".into()))?;

    let verified = jwt::verify_access_token(token, &state.config.jwt_secret)?;

    request.extensions_mut().insert(verified);

    Ok(next.run(request).await)
}
```

### 接口限流中间件

```rust
// src/auth/rate_limit.rs

use axum::{
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use crate::error::AppError;

/// 限流配置
struct RateLimitConfig {
    path_prefix: &'static str,
    max_requests: u32,
    window_secs: u64,
}

const RATE_LIMITS: &[RateLimitConfig] = &[
    RateLimitConfig { path_prefix: "/api/auth/register", max_requests: 5, window_secs: 3600 },
    RateLimitConfig { path_prefix: "/api/auth/login",    max_requests: 10, window_secs: 60 },
    RateLimitConfig { path_prefix: "/api/data",          max_requests: 60, window_secs: 60 },
];

/// 基于 IP 的简易限流（生产环境建议用 Redis）
/// TODO: 当前为占位实现，上线前替换为 tower-http Governor + Redis sliding window
pub async fn rate_limit(
    request: Request,
    next: Next,
) -> Result<Response, AppError> {
    // TODO: 提取客户端 IP，匹配限流规则，检查计数
    // _ = request.headers()
    //     .get("x-forwarded-for")
    //     .and_then(|v| v.to_str().ok())
    //     .unwrap_or("unknown");
    Ok(next.run(request).await)
}
```

---

## 六、LLM 代理模块

### LLM 客户端

```rust
// src/llm/client.rs

use crate::config::Config;
use crate::error::AppError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct LlmClient {
    http: reqwest::Client,
    base_url: String,
    api_key: String,
    model: String,
    timeout: std::time::Duration,
}

#[derive(Debug, Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    temperature: f32,
    max_tokens: u32,
    response_format: ResponseFormat,
}

#[derive(Debug, Serialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct ResponseFormat {
    #[serde(rename = "type")]
    type_: String,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
    usage: Option<Usage>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    message: ChoiceMessage,
}

#[derive(Debug, Deserialize)]
struct ChoiceMessage {
    content: String,
}

#[derive(Debug, Deserialize)]
struct Usage {
    prompt_tokens: u32,
    completion_tokens: u32,
}

pub struct LlmResult {
    pub content: String,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub model: String,
}

impl LlmClient {
    pub fn new(config: &Config) -> Self {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(config.llm_timeout_secs))
            .build()
            .expect("构建 HTTP 客户端失败");

        Self {
            http,
            base_url: config.llm_base_url.clone(),
            api_key: config.llm_api_key.clone(),
            model: config.llm_model.clone(),
            timeout: std::time::Duration::from_secs(config.llm_timeout_secs),
        }
    }

    /// 调用 LLM，返回 JSON 文本
    pub async fn chat(
        &self,
        system_prompt: &str,
        user_message: &str,
    ) -> Result<LlmResult, AppError> {
        let url = format!("{}/chat/completions", self.base_url);

        let body = ChatRequest {
            model: self.model.clone(),
            messages: vec![
                Message { role: "system".into(), content: system_prompt.into() },
                Message { role: "user".into(), content: user_message.into() },
            ],
            temperature: 0.1,
            max_tokens: 500,
            response_format: ResponseFormat { type_: "json_object".into() },
        };

        let resp = self.http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .timeout(self.timeout)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::error!(status = %status, body = %text, "LLM API 错误");
            return Err(AppError::LlmError(format!("LLM 返回 {}", status)));
        }

        let chat_resp: ChatResponse = resp.json().await?;

        let choice = chat_resp.choices.into_iter().next()
            .ok_or_else(|| AppError::LlmError("LLM 返回空结果".into()))?;

        Ok(LlmResult {
            content: choice.message.content,
            prompt_tokens: chat_resp.usage.as_ref().map(|u| u.prompt_tokens).unwrap_or(0),
            completion_tokens: chat_resp.usage.as_ref().map(|u| u.completion_tokens).unwrap_or(0),
            model: self.model.clone(),
        })
    }
}
```

### 额度检查

```rust
// src/llm/quota.rs

use sqlx::PgPool;
use crate::error::AppError;

#[derive(Debug, Clone)]
pub struct QuotaInfo {
    pub allowed: bool,
    pub tier: String,
    pub daily_used: i64,
    pub daily_limit: i64,
}

/// 检查用户 LLM 调用额度
pub async fn check_quota(pool: &PgPool, user_id: &str) -> Result<QuotaInfo, AppError> {
    let uid = uuid::Uuid::parse_str(user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    // 查用户等级
    let tier: String = sqlx::query_scalar!(
        "SELECT subscription_tier FROM users WHERE id = $1",
        uid,
    )
    .fetch_optional(pool)
    .await?
    .flatten()
    .unwrap_or_else(|| "free".to_string());

    let daily_limit: i64 = if tier == "pro" { 9999 } else { 10 };

    // 查今日用量
    let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let daily_used: i64 = sqlx::query_scalar!(
        r#"SELECT count(*)::bigint as "count!" FROM llm_usage_logs
           WHERE user_id = $1 AND created_at >= $2::date"#,
        uid,
        today,
    )
    .fetch_one(pool)
    .await?
    .unwrap_or(0);

    Ok(QuotaInfo {
        allowed: daily_used < daily_limit,
        tier,
        daily_used,
        daily_limit,
    })
}

/// 记录一次 LLM 调用
pub async fn record_usage(
    pool: &PgPool,
    user_id: &str,
    model: &str,
    prompt_tokens: u32,
    completion_tokens: u32,
    intent: Option<&str>,
) -> Result<(), AppError> {
    let uid = uuid::Uuid::parse_str(user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    sqlx::query!(
        r#"INSERT INTO llm_usage_logs (user_id, model, prompt_tokens, completion_tokens, intent)
           VALUES ($1, $2, $3, $4, $5)"#,
        uid,
        model,
        prompt_tokens as i32,
        completion_tokens as i32,
        intent,
    )
    .execute(pool)
    .await?;

    Ok(())
}
```

### Prompt 模板

详见 `05-nlu-prompts.md`，Rust 中的 `prompts.rs` 将其实现为字符串格式化函数。

---

## 七、STT 语音识别模块

### 服务商对比

| 维度 | 讯飞 | 百度 | 火山引擎 |
|------|------|------|---------|
| **协议** | WebSocket | REST POST | WebSocket / REST |
| **鉴权** | HMAC-SHA256 签名 | OAuth2.0 access_token | API Key |
| **中文普通话** | ⭐ 优秀 | ⭐ 优秀 | ⭐ 优秀 |
| **方言支持** | 粤语/四川话/河南话等 | 粤语/四川话等 | 有限 |
| **免费额度** | 500次/天 | 50000次/天 | 试用额度 |
| **价格** | ¥0.0034/次 | ¥0.0034/次 | ¥0.008/次 |
| **实时流式** | ✅ WebSocket | ✅ WebSocket | ✅ WebSocket |

**选型**：讯飞为主力（中文识别准确率最高），百度为备用降级。

### 讯飞上游连接

```rust
// src/stt/xfyun.rs

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use tokio_tungstenite::{connect_async, tungstenite};
use futures_util::{SinkExt, StreamExt};
use tracing::{info, warn, error};
use serde_json::Value;

type HmacSha256 = Hmac<Sha256>;

/// 讯飞 WebSocket 连接
pub struct XfyunUpstream {
    ws: futures_util::stream::SplitStream<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    >,
    sink: futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        tungstenite::Message,
    >,
}

impl XfyunUpstream {
    /// 建立到讯飞的 WebSocket 连接（带签名鉴权）
    pub async fn connect(
        app_id: &str,
        api_key: &str,
        api_secret: &str,
        language: &str,
        accent: &str,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let auth_url = build_auth_url(api_key, api_secret)?;

        info!(url = %auth_url, "连接讯飞上游");

        let (ws_stream, _) = connect_async(&auth_url).await?;
        let (sink, ws) = ws_stream.split();

        Ok(Self { ws, sink })
    }

    /// 发送音频帧
    /// status: 0=首帧(带参数) 1=中间帧 2=末帧
    pub async fn send_audio(
        &mut self,
        app_id: &str,
        audio: &[u8],
        status: i32,
        language: &str,
        accent: &str,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let audio_b64 = BASE64.encode(audio);

        let frame = serde_json::json!({
            "header": {
                "app_id": app_id,
                "status": status,
            },
            "parameter": {
                "iat": {
                    "domain": "iat",
                    "language": language,
                    "accent": accent,
                    "vad_eos": 2000,
                    "dnn_model": "",
                    "pd": "educational",
                }
            },
            "payload": {
                "data": {
                    "status": status,
                    "format": "audio/L16;rate=16000",
                    "encoding": "raw",
                    "audio": audio_b64,
                }
            },
        });

        self.sink
            .send(tungstenite::Message::Text(frame.to_string()))
            .await?;

        Ok(())
    }

    /// 接收识别结果
    pub async fn recv_result(
        &mut self,
    ) -> Option<Result<String, Box<dyn std::error::Error + Send + Sync>>> {
        match self.ws.next().await {
            Some(Ok(tungstenite::Message::Text(text))) => {
                Some(extract_text_from_response(&text))
            }
            Some(Ok(tungstenite::Message::Close(_))) => None,
            Some(Err(e)) => {
                error!(error = %e, "讯飞上游读取错误");
                Some(Err(e.into()))
            }
            None => None,
            _ => None,
        }
    }

    /// 关闭连接
    pub async fn close(&mut self) {
        let _ = self.sink.close().await;
    }
}

/// 生成讯飞 HMAC-SHA256 签名 URL
fn build_auth_url(
    api_key: &str,
    api_secret: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let host = "iat-api.xfyun.cn";
    let path = "/v2/iat";

    let timestamp = chrono::Utc::now().format("%a, %d %b %Y %H:%M:%S GMT").to_string();

    let signature_origin = format!(
        "host: {}\ndate: {}\nGET {} HTTP/1.1",
        host, &timestamp, path
    );

    let mut mac = HmacSha256::new_from_slice(api_secret.as_bytes())?;
    mac.update(signature_origin.as_bytes());
    let signature_bytes = mac.finalize().into_bytes();
    let signature = BASE64.encode(signature_bytes);

    let authorization_origin = format!(
        r#"api_key="{}", algorithm="hmac-sha256", headers="host date request-line", signature="{}""#,
        api_key, signature
    );
    let authorization = BASE64.encode(authorization_origin);
    let date_encoded = BASE64.encode(timestamp.as_bytes());

    Ok(format!(
        "wss://{}{}?authorization={}&date={}&host={}",
        host, path, authorization, date_encoded, host
    ))
}

/// 从讯飞返回中提取文本
fn extract_text_from_response(
    raw: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let json: Value = serde_json::from_str(raw)?;

    let code = json["header"]["code"].as_i64().unwrap_or(0);
    if code != 0 {
        let msg = json["header"]["message"].as_str().unwrap_or("未知错误");
        return Err(format!("讯飞错误 {}: {}", code, msg).into());
    }

    let data_b64 = json["payload"]["result"]["data"].as_str().unwrap_or("");
    if data_b64.is_empty() {
        return Ok(String::new());
    }

    let data_bytes = BASE64.decode(data_b64)?;
    let data_json: Value = serde_json::from_slice(&data_bytes)?;

    let text: String = data_json["ws"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .flat_map(|ws| {
            ws["cw"]
                .as_array()
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|cw| cw["w"].as_str().map(String::from))
        })
        .collect();

    Ok(text)
}
```

### WebSocket 透传中继

```rust
// src/stt/relay.rs

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::Response,
    http::HeaderMap,
};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{info, warn, error, instrument};

use crate::auth::jwt::VerifiedUser;
use crate::stt::xfyun::XfyunUpstream;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    token: Option<String>,
}

/// HTTP 升级到 WebSocket
pub async fn ws_upgrade(
    ws: WebSocketUpgrade,
    Query(query): Query<WsQuery>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> Response {
    // 认证
    let token = query.token.or_else(|| {
        headers.get("authorization").and_then(|v| {
            v.to_str().ok().and_then(|s| s.strip_prefix("Bearer ").map(String::from))
        })
    });

    let claims = match token {
        Some(t) => match crate::auth::jwt::verify_access_token(&t, &state.config.jwt_secret) {
            Ok(c) => c,
            Err(e) => {
                warn!(error = %e, "WebSocket JWT 验证失败");
                return Response::builder().status(401).body("Unauthorized".into()).unwrap();
            }
        },
        None => {
            return Response::builder().status(401).body("Missing token".into()).unwrap();
        }
    };

    // 连接数检查
    if state.active_ws() as usize >= state.config.max_ws_connections {
        return Response::builder().status(429).body("Too many connections".into()).unwrap();
    }

    ws.on_upgrade(move |socket| handle_relay(socket, claims, state))
}

/// WebSocket 透传核心
#[instrument(skip(client_ws, state), fields(user_id = %claims.user_id))]
async fn handle_relay(client_ws: WebSocket, claims: VerifiedUser, state: Arc<AppState>) {
    let conn_id = state.inc_ws();
    info!(conn_id, "WebSocket 连接建立");

    let mut upstream = match XfyunUpstream::connect(
        &state.config.xfyun_app_id,
        &state.config.xfyun_api_key,
        &state.config.xfyun_api_secret,
        "zh_cn",
        "mandarin",
    ).await {
        Ok(u) => u,
        Err(e) => {
            error!(error = %e, "讯飞上游连接失败");
            let (mut sink, _) = client_ws.split();
            let _ = sink.send(Message::Text(
                r#"{"type":"error","message":"STT服务不可用"}"#.into(),
            )).await;
            state.dec_ws();
            return;
        }
    };

    let (client_sink, client_stream) = client_ws.split();
    let client_sink = Arc::new(tokio::sync::Mutex::new(client_sink));
    let sink_clone = client_sink.clone();
    let app_id = state.config.xfyun_app_id.clone();

    let pipe_up = async { pipe_up(client_stream, &mut upstream, &app_id).await };
    let pipe_down = async { pipe_down(&mut upstream, &sink_clone).await };

    tokio::select! {
        r = pipe_up => {
            match r {
                Ok(()) => info!(conn_id, "上行管道正常结束"),
                Err(e) => warn!(conn_id, error = %e, "上行管道异常"),
            }
        }
        r = pipe_down => {
            match r {
                Ok(()) => info!(conn_id, "下行管道正常结束"),
                Err(e) => warn!(conn_id, error = %e, "下行管道异常"),
            }
        }
    }

    upstream.close().await;
    state.dec_ws();
    info!(conn_id, "WebSocket 连接关闭");
}

/// 上行管道：客户端音频 → 讯飞
async fn pipe_up(
    mut client: futures_util::stream::SplitStream<WebSocket>,
    upstream: &mut XfyunUpstream,
    app_id: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut first_frame = true;

    while let Some(msg) = client.next().await {
        let msg = msg?;

        match msg {
            Message::Binary(audio) => {
                let status = if first_frame { 0 } else { 1 };
                first_frame = false;
                upstream.send_audio(app_id, &audio, status, "zh_cn", "mandarin").await?;
            }
            Message::Text(text) => {
                let json: serde_json::Value = serde_json::from_str(&text)?;
                match json["type"].as_str() {
                    Some("audio") => {
                        let audio_b64 = json["data"].as_str().unwrap_or("");
                        let audio = base64::engine::general_purpose::STANDARD
                            .decode(audio_b64).unwrap_or_default();
                        let status = json["status"].as_i64().unwrap_or(1) as i32;
                        upstream.send_audio(app_id, &audio, status, "zh_cn", "mandarin").await?;
                    }
                    Some("end") => {
                        upstream.send_audio(app_id, &[], 2, "zh_cn", "mandarin").await?;
                        break;
                    }
                    _ => { warn!(msg = %text, "未知控制消息"); }
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    Ok(())
}

/// 下行管道：讯飞结果 → 客户端
async fn pipe_down(
    upstream: &mut XfyunUpstream,
    client_sink: &Arc<tokio::sync::Mutex<
        futures_util::stream::SplitSink<WebSocket, Message>,
    >>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    loop {
        match upstream.recv_result().await {
            Some(Ok(text)) => {
                let response = serde_json::json!({
                    "type": "result",
                    "text": text,
                    "is_final": false,
                });
                let mut sink = client_sink.lock().await;
                sink.send(Message::Text(response.to_string().into())).await?;
            }
            Some(Err(e)) => {
                let error_msg = serde_json::json!({
                    "type": "error",
                    "message": e.to_string(),
                });
                let mut sink = client_sink.lock().await;
                let _ = sink.send(Message::Text(error_msg.to_string().into())).await;
                break;
            }
            None => {
                let final_msg = serde_json::json!({
                    "type": "result",
                    "text": "",
                    "is_final": true,
                });
                let mut sink = client_sink.lock().await;
                let _ = sink.send(Message::Text(final_msg.to_string().into())).await;
                break;
            }
        }
    }

    Ok(())
}
```

---

## 八、数据 CRUD 模块

数据表 Schema 详见 `03-architecture.md`。Rust 后端通过 sqlx 直连 PostgreSQL，每个请求通过 JWT 中间件获取 `user_id`，所有 SQL 带 `WHERE user_id = $1` 保证数据隔离。

模块包含：
- `src/data/expense.rs` — 记账 CRUD + 统计查询
- `src/data/habit.rs` — 习惯定义 CRUD + 打卡记录
- `src/data/todo.rs` — 待办/备忘 CRUD + 完成状态切换

---

## 九、路由总表

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

### 路由注册

```rust
// src/main.rs 路由注册部分

use axum::{routing::{get, post}, Router, middleware};

// 公开路由
let public = Router::new()
    .route("/register", post(auth::handler::register))
    .route("/login",    post(auth::handler::login))
    .route("/refresh",  post(auth::handler::refresh));

// 需要认证的路由
let protected = Router::new()
    .route("/auth/logout",           post(auth::handler::logout))
    .route("/auth/me",               get(auth::handler::me))
    .route("/auth/change-password",  post(auth::handler::change_password))
    .route("/auth/verify-email",     post(auth::handler::verify_email))
    .route("/nlu/classify",          post(routes::nlu::classify))
    .route("/nlu/query",             post(routes::nlu::query))
    .route("/nlu/correct",           post(routes::nlu::correct))
    .route("/data/expenses",         get(routes::data::list_expenses))
    .route("/data/expenses",         post(routes::data::create_expense))
    .route("/data/habits",           get(routes::data::list_habits))
    .route("/data/habits/checkin",   post(routes::data::checkin_habit))
    .route("/data/todos",            get(routes::data::list_todos))
    .route("/data/todos",            post(routes::data::create_todo))
    .layer(middleware::from_fn_with_state(
        state.clone(),
        auth::middleware::require_auth,
    ));

let ws_routes = Router::new()
    .route("/stt", get(routes::stt::ws_upgrade));

let app = Router::new()
    .route("/health", get(routes::health::health))
    .nest("/api/auth", public)
    .nest("/api", protected)
    .nest("/ws", ws_routes)
    .layer(cors)
    .with_state(state);
```

---

## 十、错误处理

```rust
// src/error.rs

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("认证失败: {0}")]
    Unauthorized(String),

    #[error("额度不足")]
    QuotaExceeded {
        daily_used: i64,
        daily_limit: i64,
        tier: String,
    },

    #[error("参数错误: {0}")]
    BadRequest(String),

    #[error("LLM 调用失败: {0}")]
    LlmError(String),

    #[error("LLM 超时")]
    LlmTimeout,

    #[error("STT 服务不可用: {0}")]
    SttError(String),

    #[error("内部错误: {0}")]
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, body) = match &self {
            AppError::Unauthorized(_) => (
                StatusCode::UNAUTHORIZED,
                json!({ "error": self.to_string() }),
            ),
            AppError::QuotaExceeded { daily_used, daily_limit, tier } => (
                StatusCode::TOO_MANY_REQUESTS,
                json!({
                    "error": "今日 AI 额度已用完",
                    "quota": { "daily_used": daily_used, "daily_limit": daily_limit, "tier": tier }
                }),
            ),
            AppError::BadRequest(_) => (
                StatusCode::BAD_REQUEST,
                json!({ "error": self.to_string() }),
            ),
            AppError::LlmError(_) => (
                StatusCode::BAD_GATEWAY,
                json!({ "error": self.to_string() }),
            ),
            AppError::LlmTimeout => (
                StatusCode::GATEWAY_TIMEOUT,
                json!({ "error": "AI 服务响应超时" }),
            ),
            AppError::SttError(_) => (
                StatusCode::SERVICE_UNAVAILABLE,
                json!({ "error": self.to_string() }),
            ),
            AppError::Internal(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": "服务器内部错误" }),
            ),
        };

        (status, axum::Json(body)).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self { AppError::Internal(e.to_string()) }
}

impl From<reqwest::Error> for AppError {
    fn from(e: reqwest::Error) -> Self {
        if e.is_timeout() { AppError::LlmTimeout } else { AppError::LlmError(e.to_string()) }
    }
}
```

---

## 十一、Token 生命周期

```
注册/登录
  用户 ──email+password──→ Rust ──→ 返回 { access_token (15min), refresh_token (30d) }

正常请求
  App ──Bearer access_token──→ Rust 中间件验证 ──→ 放行

Access Token 过期（15分钟后）
  App ──refresh_token──→ Rust ──→ 返回新的 { access_token, refresh_token }
  旧 refresh_token 立即失效（一次性使用）

Refresh Token 也过期（30天后）
  App ──→ 401 → 弹出登录页，重新输入密码
```

### iOS 端 Token 管理（Keychain）

> 完整实现见本文档 §十六「Token 管理（Keychain）」。

---

## 十二、全局状态

```rust
// src/state.rs

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use sqlx::PgPool;

use crate::config::Config;
use crate::llm::client::LlmClient;

#[derive(Debug, Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub pool: PgPool,
    pub llm_client: Arc<LlmClient>,
    pub active_ws_connections: Arc<AtomicU64>,
    pub total_connections: Arc<AtomicU64>,
}

impl AppState {
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let pool = PgPool::connect(&config.database_url).await?;
        let llm_client = LlmClient::new(&config);

        Ok(Self {
            config: Arc::new(config),
            pool,
            llm_client: Arc::new(llm_client),
            active_ws_connections: Arc::new(AtomicU64::new(0)),
            total_connections: Arc::new(AtomicU64::new(0)),
        })
    }

    pub fn inc_ws(&self) -> u64 {
        self.total_connections.fetch_add(1, Ordering::Relaxed);
        self.active_ws_connections.fetch_add(1, Ordering::Relaxed) + 1
    }

    pub fn dec_ws(&self) {
        self.active_ws_connections.fetch_sub(1, Ordering::Relaxed);
    }

    pub fn active_ws(&self) -> u64 {
        self.active_ws_connections.load(Ordering::Relaxed)
    }
}
```

---

## 十三、入口

```rust
// src/main.rs

mod auth;
mod config;
mod error;
mod llm;
mod routes;
mod state;
mod stt;

use axum::routing::{get, post};
use std::sync::Arc;
use state::AppState;

static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let config = config::Config::from_env();
    let addr = format!("{}:{}", config.host, config.port);

    let state = AppState::new(config).await.expect("初始化失败");

    // 自动数据库迁移
    MIGRATOR.run(&state.pool).await.expect("数据库迁移失败");
    tracing::info!("数据库迁移完成");

    // CORS
    let cors = tower_http::cors::CorsLayer::permissive();

    // 公开路由
    let public = Router::new()
        .route("/register", post(auth::handler::register))
        .route("/login",    post(auth::handler::login))
        .route("/refresh",  post(auth::handler::refresh));

    // 需要认证的路由
    let protected = Router::new()
        .route("/auth/logout",           post(auth::handler::logout))
        .route("/auth/me",               get(auth::handler::me))
        .route("/auth/change-password",  post(auth::handler::change_password))
        .route("/auth/verify-email",     post(auth::handler::verify_email))
        .route("/nlu/classify",          post(routes::nlu::classify))
        .route("/nlu/query",             post(routes::nlu::query))
        .route("/nlu/correct",           post(routes::nlu::correct))
        .route("/data/expenses",         get(routes::data::list_expenses).post(routes::data::create_expense))
        .route("/data/habits",           get(routes::data::list_habits).post(routes::data::create_habit))
        .route("/data/todos",            get(routes::data::list_todos).post(routes::data::create_todo))
        .layer(axum::middleware::from_fn_with_state(
            Arc::new(state.clone()),
            auth::middleware::require_auth,
        ));

    let ws_routes = Router::new()
        .route("/stt", get(routes::stt::ws_upgrade));

    let app = Router::new()
        .route("/health", get(routes::health::health))
        .nest("/api/auth", public)
        .nest("/api", protected)
        .nest("/ws", ws_routes)
        .layer(cors)
        .with_state(Arc::new(state));

    tracing::info!(%addr, "Boxs Server 启动");

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.expect("监听 Ctrl+C 失败");
    tracing::info!("收到关闭信号");
}
```

---

## 十四、部署

### Dockerfile

```dockerfile
FROM rust:1.85-slim AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src
COPY src/ src/
COPY migrations/ migrations/
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/boxs-server /usr/local/bin/
COPY --from=builder /app/migrations /migrations
EXPOSE 8000
CMD ["boxs-server"]
```

### docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: boxs
      POSTGRES_USER: ${POSTGRES_USER:-boxs}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U boxs"]
      interval: 5s
      retries: 5

  server:
    build: .
    ports:
      - "8000:8000"
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      retries: 3

volumes:
  pgdata:
```

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name api.boxs.app;

    ssl_certificate /etc/ssl/boxs.app.pem;
    ssl_certificate_key /etc/ssl/boxs.app.key;

    # REST API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000;
    }
}
```

---

## 十五、安全性

```
密码安全：
  - Argon2id 哈希（OWASP 推荐）
  - 不存明文，不可逆

Token 安全：
  - Access Token: 15分钟短期，JWT 自包含
  - Refresh Token: 30天长期，SHA-256 哈希存 DB，一次性使用
  - 刷新时旧 Refresh Token 立即失效
  - Refresh Token 绑定 device_info，换设备时旧令牌自动失效
  - 异地登录检测：IP 变化时记录日志，可选通知用户

传输安全：
  - 全链路 HTTPS（Nginx TLS 终止）
  - WebSocket over TLS (wss://)

客户端存储：
  - iOS Keychain（Security framework）/ Android EncryptedSharedPreferences
  - 不存明文密码

接口限流：
  - /api/auth/register: 同 IP 每小时 5 次
  - /api/auth/login: 同 IP 每分钟 10 次
  - /api/data/*: 每用户每分钟 60 次
  - /api/nlu/*: 额度控制见 llm/quota.rs（免费用户 10 次/天）
  - 实现方式：tower-http Governor 中间件（生产环境用 Redis 存储）

防暴力破解：
  - 登录失败统一提示"邮箱或密码错误"
  - 连续 5 次登录失败 → 该 IP 锁定 15 分钟
  - 注册接口加 CAPTCHA（P2 阶段）

数据库安全：
  - Rust 层检查 user_id，每条 SQL 带 WHERE user_id = $1
  - 参数化查询（sqlx 宏编译期检查），无 SQL 注入风险
```

---

## 十六、iOS 客户端适配

iOS 客户端使用 SPM 依赖：

```swift
// Package.swift 核心依赖
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.0"),
]
```

### HTTP 客户端封装（类型安全 + 自动重试）

```swift
// Core/Network/APIClient.swift

import Foundation

// ── 类型安全的响应模型 ──

/// 通用 API 响应包装
struct APIResponse<T: Decodable> {
    let data: T
}

actor APIClient {
    let baseURL: String
    let tokenManager = TokenManager()

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func get(_ path: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        if let token = await tokenManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handle(data: data, response: response)
    }

    func post(_ path: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let token = await tokenManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handle(data: data, response: response)
    }

    private func handle(data: Data, response: URLResponse) throws -> [String: Any] {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            // 尝试刷新 Token
            if let refreshed = try? await tryRefresh(), refreshed {
                // 调用方需要重试请求
            }
            throw APIError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError.quotaExceeded(json ?? [:])
        }

        guard (200...201).contains(httpResponse.statusCode) else {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = json?["error"] as? String ?? "未知错误"
            throw APIError.httpError(httpResponse.statusCode, message)
        }

        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func tryRefresh() async throws -> Bool {
        guard let refreshToken = await tokenManager.getRefreshToken() else { return false }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/auth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }

        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try await tokenManager.save(
            accessToken: body["access_token"] as! String,
            refreshToken: body["refresh_token"] as! String
        )
        return true
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case quotaExceeded([String: Any])
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .unauthorized: return "认证失败"
        case .quotaExceeded: return "今日 AI 额度已用完"
        case .httpError(let code, let msg): return "错误 \(code): \(msg)"
        }
    }
}
```

### Token 管理（Keychain）

```swift
// Core/Network/TokenManager.swift

import Foundation
import Security

actor TokenManager {
    private static let accessTokenKey = "com.boxs.accessToken"
    private static let refreshTokenKey = "com.boxs.refreshToken"

    func save(accessToken: String, refreshToken: String) throws {
        try KeychainHelper.save(key: Self.accessTokenKey, data: Data(accessToken.utf8))
        try KeychainHelper.save(key: Self.refreshTokenKey, data: Data(refreshToken.utf8))
    }

    func getAccessToken() -> String? {
        guard let data = KeychainHelper.load(key: Self.accessTokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func getRefreshToken() -> String? {
        guard let data = KeychainHelper.load(key: Self.refreshTokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        KeychainHelper.delete(key: Self.accessTokenKey)
        KeychainHelper.delete(key: Self.refreshTokenKey)
    }

    var isLoggedIn: Bool { getRefreshToken() != nil }
}

enum KeychainHelper {
    static func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### STT WebSocket 客户端

```swift
// Core/STT/STTClient.swift

import Foundation
import Starscream

actor STTClient {
    let baseURL: String
    let tokenManager = TokenManager()

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    /// 建立 STT WebSocket 连接，通过 AsyncStream 返回识别结果
    func connect() async throws -> AsyncStream<STTResult> {
        let token = await tokenManager.getAccessToken()
        let wsURL = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let url = URL(string: "\(wsURL)/ws/stt?token=\(token ?? "")")!

        return AsyncStream { continuation in
            var socket: WebSocket? = nil
            DispatchQueue.global().async {
                let request = URLRequest(url: url)
                let ws = WebSocket(request: request)
                socket = ws

                ws.onEvent = { event in
                    switch event {
                    case .text(let string):
                        guard let data = string.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        let type = json["type"] as? String
                        if type == "result" {
                            let text = json["text"] as? String ?? ""
                            let isFinal = json["is_final"] as? Bool ?? false
                            continuation.yield(STTResult(text: text, isFinal: isFinal))
                        } else if type == "error" {
                            continuation.finish()
                        }
                    case .error(let error):
                        continuation.finish()
                    case .disconnected:
                        continuation.finish()
                    default:
                        break
                    }
                }
                ws.connect()
            }
        }
    }

    /// 发送音频帧
    func sendAudio(_ audio: Data, status: Int, socket: WebSocket) {
        let payload: [String: Any] = [
            "type": "audio",
            "data": audio.base64EncodedString(),
            "status": status,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        socket.write(string: jsonString)
    }
}

struct STTResult: Sendable {
    let text: String
    let isFinal: Bool
}
```

---

## 十七、性能预估

```
单实例性能（2 核 4GB VM）：

  并发 WebSocket 连接: ~50,000（每个 ~40KB 内存）
  音频转发延迟:        ~0.1ms（纯内存搬运）
  CPU 占用 @ 1000 并发: ~5%
  内存占用 @ 10,000 并发: ~200MB
  REST API 延迟:       < 1ms（不含 LLM 调用）
```
