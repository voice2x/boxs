// src/auth/jwt.rs

use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use crate::config::Config;
use crate::error::AppError;

/// Access Token 的 Claims
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AccessTokenClaims {
    pub sub: String,      // 用户 ID
    pub email: String,
    pub tier: String,     // free / pro
    pub exp: usize,       // 过期时间
    pub iat: usize,       // 签发时间
    pub jti: String,      // 唯一 ID（防重放）
}

/// 验证结果
#[derive(Debug, Clone)]
pub struct VerifiedUser {
    pub user_id: String,
    pub email: String,
    pub tier: String,
}

/// 让 VerifiedUser 可以直接作为 handler 参数（从 request extensions 提取）
impl<S: Send + Sync> axum::extract::FromRequestParts<S> for VerifiedUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<VerifiedUser>()
            .cloned()
            .ok_or_else(|| AppError::Unauthorized("未认证".into()))
    }
}

/// 签发 Access Token（15 分钟有效）
pub fn sign_access_token(
    user_id: &str,
    email: &str,
    tier: &str,
    config: &Config,
) -> Result<String, AppError> {
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
    validation.set_audience::<String>(&[]);

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
