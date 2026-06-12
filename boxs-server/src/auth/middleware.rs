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
