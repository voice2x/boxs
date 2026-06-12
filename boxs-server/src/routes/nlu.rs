// src/routes/nlu.rs

use axum::{extract::State, Json};
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::error::AppError;
use crate::state::AppState;

/// POST /api/nlu/classify
pub async fn classify(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, AppError> {
    let text = body["text"]
        .as_str()
        .ok_or_else(|| AppError::BadRequest("缺少 text 字段".into()))?;

    // 检查额度
    let quota = crate::llm::quota::check_quota(&state.pool, &claims.user_id).await?;
    if !quota.allowed {
        return Err(AppError::QuotaExceeded {
            daily_used: quota.daily_used,
            daily_limit: quota.daily_limit,
            tier: quota.tier,
        });
    }

    let result = state
        .llm_client
        .chat(crate::llm::prompts::classify_prompt(), text)
        .await?;

    // 记录用量
    crate::llm::quota::record_usage(
        &state.pool,
        &claims.user_id,
        &result.model,
        result.prompt_tokens,
        result.completion_tokens,
        Some("classify"),
    )
    .await?;

    // 解析并返回
    let parsed: serde_json::Value =
        serde_json::from_str(&result.content).unwrap_or_else(|_| {
            serde_json::json!({ "raw": result.content })
        });

    Ok(Json(parsed))
}

/// POST /api/nlu/query
pub async fn query(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, AppError> {
    let text = body["text"]
        .as_str()
        .ok_or_else(|| AppError::BadRequest("缺少 text 字段".into()))?;

    let quota = crate::llm::quota::check_quota(&state.pool, &claims.user_id).await?;
    if !quota.allowed {
        return Err(AppError::QuotaExceeded {
            daily_used: quota.daily_used,
            daily_limit: quota.daily_limit,
            tier: quota.tier,
        });
    }

    let context = body["context"].as_str().unwrap_or("");
    let user_message = if context.is_empty() {
        text.to_string()
    } else {
        format!("上下文数据：{}\n\n用户问题：{}", context, text)
    };

    let result = state
        .llm_client
        .chat(crate::llm::prompts::query_prompt(), &user_message)
        .await?;

    crate::llm::quota::record_usage(
        &state.pool,
        &claims.user_id,
        &result.model,
        result.prompt_tokens,
        result.completion_tokens,
        Some("query"),
    )
    .await?;

    Ok(Json(serde_json::json!({
        "answer": result.content,
    })))
}

/// POST /api/nlu/correct
pub async fn correct(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, AppError> {
    let text = body["text"]
        .as_str()
        .ok_or_else(|| AppError::BadRequest("缺少 text 字段".into()))?;

    let quota = crate::llm::quota::check_quota(&state.pool, &claims.user_id).await?;
    if !quota.allowed {
        return Err(AppError::QuotaExceeded {
            daily_used: quota.daily_used,
            daily_limit: quota.daily_limit,
            tier: quota.tier,
        });
    }

    let result = state
        .llm_client
        .chat(crate::llm::prompts::correct_prompt(), text)
        .await?;

    crate::llm::quota::record_usage(
        &state.pool,
        &claims.user_id,
        &result.model,
        result.prompt_tokens,
        result.completion_tokens,
        Some("correct"),
    )
    .await?;

    let parsed: serde_json::Value =
        serde_json::from_str(&result.content).unwrap_or_else(|_| {
            serde_json::json!({ "corrected": text, "changes": [] })
        });

    Ok(Json(parsed))
}
