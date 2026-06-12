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
    let tier: String = sqlx::query_scalar::<_, Option<String>>(
        "SELECT subscription_tier FROM users WHERE id = $1",
    )
    .bind(uid)
    .fetch_optional(pool)
    .await?
    .flatten()
    .unwrap_or_else(|| "free".to_string());

    let daily_limit: i64 = if tier == "pro" { 9999 } else { 10 };

    // 查今日用量
    let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let daily_used: i64 = sqlx::query_scalar::<_, i64>(
        "SELECT count(*)::bigint FROM llm_usage_logs
           WHERE user_id = $1 AND created_at >= $2::date",
    )
    .bind(uid)
    .bind(&today)
    .fetch_one(pool)
    .await?;

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

    sqlx::query(
        "INSERT INTO llm_usage_logs (user_id, model, prompt_tokens, completion_tokens, intent)
           VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(uid)
    .bind(model)
    .bind(prompt_tokens as i32)
    .bind(completion_tokens as i32)
    .bind(intent)
    .execute(pool)
    .await?;

    Ok(())
}
