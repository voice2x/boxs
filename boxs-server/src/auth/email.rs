// src/auth/email.rs

use sqlx::PgPool;
use rand::Rng;
use tracing::info;

#[derive(Debug, sqlx::FromRow)]
struct VerificationRow {
    id: uuid::Uuid,
    expires_at: chrono::DateTime<chrono::Utc>,
    used_at: Option<chrono::DateTime<chrono::Utc>>,
}

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

    sqlx::query(
        "INSERT INTO email_verifications (user_id, code, expires_at)
         VALUES ($1, $2, $3)",
    )
    .bind(uid)
    .bind(&code)
    .bind(chrono::Utc::now() + chrono::Duration::minutes(10))
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

    let row = sqlx::query_as::<_, VerificationRow>(
        "SELECT id, expires_at, used_at FROM email_verifications
         WHERE user_id = $1 AND code = $2 AND used_at IS NULL
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(uid)
    .bind(code)
    .fetch_optional(pool)
    .await
    .map_err(|e| e.to_string())?;

    match row {
        Some(row) if row.expires_at > chrono::Utc::now() => {
            sqlx::query(
                "UPDATE email_verifications SET used_at = now() WHERE id = $1",
            )
            .bind(row.id)
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;

            sqlx::query(
                "UPDATE users SET email_verified = true WHERE id = $1",
            )
            .bind(uid)
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;

            Ok(true)
        }
        _ => Ok(false),
    }
}
