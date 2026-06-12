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
            AppError::QuotaExceeded {
                daily_used,
                daily_limit,
                tier,
            } => (
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
    fn from(e: sqlx::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}

impl From<reqwest::Error> for AppError {
    fn from(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            AppError::LlmTimeout
        } else {
            AppError::LlmError(e.to_string())
        }
    }
}
