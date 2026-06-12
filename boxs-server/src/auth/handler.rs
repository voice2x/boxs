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

#[derive(Debug, sqlx::FromRow)]
struct RefreshTokenRow {
    user_id: uuid::Uuid,
    expires_at: chrono::DateTime<chrono::Utc>,
    email: String,
    subscription_tier: String,
}

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

    let exists: bool = sqlx::query_scalar::<_, Option<bool>>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
    )
    .bind(&email)
    .fetch_one(&state.pool)
    .await?
    .unwrap_or(false);

    if exists {
        return Err(AppError::BadRequest("该邮箱已注册".into()));
    }

    let password_hash = password::hash(password)?;

    let user = sqlx::query_as::<_, crate::auth::User>(
        "INSERT INTO users (email, password_hash, display_name)
           VALUES ($1, $2, $3)
           RETURNING id, email, password_hash, display_name, avatar_url,
                     subscription_tier, email_verified, is_active,
                     created_at, updated_at",
    )
    .bind(email)
    .bind(password_hash)
    .bind(&body.display_name)
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

    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(user.id)
    .bind(&refresh_hash)
    .bind(None::<String>)
    .bind(chrono::Utc::now() + chrono::Duration::days(30))
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

    let user = sqlx::query_as::<_, crate::auth::User>(
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE email = $1 AND is_active = true",
    )
    .bind(&email)
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
    sqlx::query(
        "DELETE FROM refresh_tokens WHERE user_id = $1 AND id NOT IN (
            SELECT id FROM refresh_tokens WHERE user_id = $1 ORDER BY created_at DESC LIMIT 4
        )",
    )
    .bind(user.id)
    .execute(&state.pool)
    .await?;

    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(user.id)
    .bind(&refresh_hash)
    .bind(&body.device_info)
    .bind(chrono::Utc::now() + chrono::Duration::days(30))
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

    let token_row = sqlx::query_as::<_, RefreshTokenRow>(
        "SELECT rt.user_id, rt.expires_at, u.email, u.subscription_tier
         FROM refresh_tokens rt
         JOIN users u ON u.id = rt.user_id
         WHERE rt.token_hash = $1 AND u.is_active = true",
    )
    .bind(&token_hash)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::Unauthorized("刷新令牌无效".into()))?;

    if token_row.expires_at < chrono::Utc::now() {
        sqlx::query("DELETE FROM refresh_tokens WHERE token_hash = $1")
            .bind(&token_hash)
            .execute(&state.pool)
            .await?;
        return Err(AppError::Unauthorized("刷新令牌已过期".into()));
    }

    // 删除旧刷新令牌（一次性使用）
    sqlx::query("DELETE FROM refresh_tokens WHERE token_hash = $1")
        .bind(&token_hash)
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

    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, $3)",
    )
    .bind(token_row.user_id)
    .bind(&new_hash)
    .bind(chrono::Utc::now() + chrono::Duration::days(30))
    .execute(&state.pool)
    .await?;

    let user = sqlx::query_as::<_, crate::auth::User>(
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
    )
    .bind(token_row.user_id)
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

    sqlx::query("DELETE FROM refresh_tokens WHERE user_id = $1")
        .bind(uid)
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

    let user = sqlx::query_as::<_, crate::auth::User>(
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
    )
    .bind(uid)
    .fetch_one(&state.pool)
    .await?;

    if !password::verify(&body.old_password, &user.password_hash)? {
        return Err(AppError::BadRequest("旧密码错误".into()));
    }

    let new_hash = password::hash(&body.new_password)?;
    sqlx::query(
        "UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2",
    )
    .bind(&new_hash)
    .bind(uid)
    .execute(&state.pool)
    .await?;

    // 使所有刷新令牌失效（强制重新登录）
    sqlx::query("DELETE FROM refresh_tokens WHERE user_id = $1")
        .bind(uid)
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

    let user = sqlx::query_as::<_, crate::auth::User>(
        "SELECT id, email, password_hash, display_name, avatar_url,
                subscription_tier, email_verified, is_active,
                created_at, updated_at
         FROM users WHERE id = $1",
    )
    .bind(uid)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(UserResponse::from(user)))
}

/// POST /api/auth/verify-email
pub async fn verify_email(
    State(state): State<Arc<AppState>>,
    claims: crate::auth::jwt::VerifiedUser,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, AppError> {
    let code = body["code"]
        .as_str()
        .ok_or_else(|| AppError::BadRequest("缺少验证码".into()))?;

    let verified = email::verify_code(&state.pool, &claims.user_id, code)
        .await
        .map_err(|e| AppError::Internal(e))?;

    if verified {
        Ok(Json(serde_json::json!({ "success": true })))
    } else {
        Err(AppError::BadRequest("验证码无效或已过期".into()))
    }
}
