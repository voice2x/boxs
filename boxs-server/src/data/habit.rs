// src/data/habit.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct HabitDefinition {
    pub id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub name: String,
    pub emoji: Option<String>,
    pub frequency: String,
    pub target_value: Option<f64>,
    pub unit: Option<String>,
    pub is_active: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct HabitRecord {
    pub id: uuid::Uuid,
    pub habit_id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub value: Option<f64>,
    pub note: Option<String>,
    pub record_date: chrono::NaiveDate,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateHabitRequest {
    pub name: String,
    pub emoji: Option<String>,
    pub frequency: Option<String>,
    pub target_value: Option<f64>,
    pub unit: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateHabitRequest {
    pub name: Option<String>,
    pub emoji: Option<String>,
    pub frequency: Option<String>,
    pub target_value: Option<f64>,
    pub unit: Option<String>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct CheckinRequest {
    pub habit_id: uuid::Uuid,
    pub value: Option<f64>,
    pub note: Option<String>,
    pub record_date: chrono::NaiveDate,
}

#[derive(Debug, Deserialize)]
pub struct CalendarQuery {
    pub habit_id: uuid::Uuid,
    pub month: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CalendarResponse {
    pub habit: HabitDefinition,
    pub records: Vec<HabitRecord>,
}

pub async fn create(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<CreateHabitRequest>,
) -> Result<Json<HabitDefinition>, AppError> {
    let uid = claims.uid()?;

    let habit = sqlx::query_as::<_, HabitDefinition>(
        "INSERT INTO habit_definitions (user_id, name, emoji, frequency, target_value, unit)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id, user_id, name, emoji, frequency, target_value, unit,
                     is_active, created_at, updated_at",
    )
    .bind(uid)
    .bind(&body.name)
    .bind(&body.emoji)
    .bind(body.frequency.as_deref().unwrap_or("daily"))
    .bind(body.target_value)
    .bind(&body.unit)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(habit))
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
) -> Result<Json<Vec<HabitDefinition>>, AppError> {
    let uid = claims.uid()?;

    let habits = sqlx::query_as::<_, HabitDefinition>(
        "SELECT id, user_id, name, emoji, frequency, target_value, unit,
                  is_active, created_at, updated_at
           FROM habit_definitions
           WHERE user_id = $1 AND is_active = true
           ORDER BY created_at ASC",
    )
    .bind(uid)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(habits))
}

pub async fn update(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<UpdateHabitRequest>,
) -> Result<Json<HabitDefinition>, AppError> {
    let uid = claims.uid()?;

    let habit = sqlx::query_as::<_, HabitDefinition>(
        "SELECT id, user_id, name, emoji, frequency, target_value, unit,
                  is_active, created_at, updated_at
           FROM habit_definitions WHERE id = $1 AND user_id = $2",
    )
    .bind(id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("习惯不存在".into()))?;

    let updated = sqlx::query_as::<_, HabitDefinition>(
        "UPDATE habit_definitions
           SET name = COALESCE($1, name),
               emoji = COALESCE($2, emoji),
               frequency = COALESCE($3, frequency),
               target_value = COALESCE($4, target_value),
               unit = COALESCE($5, unit),
               is_active = COALESCE($6, is_active),
               updated_at = now()
           WHERE id = $7
           RETURNING id, user_id, name, emoji, frequency, target_value, unit,
                     is_active, created_at, updated_at",
    )
    .bind(&body.name)
    .bind(&body.emoji)
    .bind(&body.frequency)
    .bind(body.target_value)
    .bind(&body.unit)
    .bind(body.is_active)
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(updated))
}

pub async fn delete(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let uid = claims.uid()?;

    let result = sqlx::query(
        "UPDATE habit_definitions SET is_active = false, updated_at = now() WHERE id = $1 AND user_id = $2",
    )
    .bind(id)
    .bind(uid)
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest("习惯不存在".into()));
    }

    Ok(Json(serde_json::json!({ "success": true })))
}

pub async fn checkin(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<CheckinRequest>,
) -> Result<Json<HabitRecord>, AppError> {
    let uid = claims.uid()?;

    // Verify habit belongs to user
    let _habit = sqlx::query_as::<_, HabitDefinition>(
        "SELECT id, user_id, name, emoji, frequency, target_value, unit,
                  is_active, created_at, updated_at
           FROM habit_definitions
           WHERE id = $1 AND user_id = $2 AND is_active = true",
    )
    .bind(body.habit_id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("习惯不存在".into()))?;

    // Check if already checked in today
    let existing = sqlx::query_as::<_, HabitRecord>(
        "SELECT id, habit_id, user_id, value, note, record_date, created_at, updated_at
           FROM habit_records
           WHERE habit_id = $1 AND user_id = $2 AND record_date = $3",
    )
    .bind(body.habit_id)
    .bind(uid)
    .bind(body.record_date)
    .fetch_optional(&state.pool)
    .await?;

    if let Some(record) = existing {
        // Update existing record
        let updated = sqlx::query_as::<_, HabitRecord>(
            "UPDATE habit_records SET value = $1, note = $2, updated_at = now()
               WHERE id = $3
               RETURNING id, habit_id, user_id, value, note, record_date, created_at, updated_at",
        )
        .bind(body.value)
        .bind(&body.note)
        .bind(record.id)
        .fetch_one(&state.pool)
        .await?;
        return Ok(Json(updated));
    }

    let record = sqlx::query_as::<_, HabitRecord>(
        "INSERT INTO habit_records (habit_id, user_id, value, note, record_date)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, habit_id, user_id, value, note, record_date, created_at, updated_at",
    )
    .bind(body.habit_id)
    .bind(uid)
    .bind(body.value)
    .bind(&body.note)
    .bind(body.record_date)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(record))
}

pub async fn calendar(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<CalendarQuery>,
) -> Result<Json<CalendarResponse>, AppError> {
    let uid = claims.uid()?;

    let habit = sqlx::query_as::<_, HabitDefinition>(
        "SELECT id, user_id, name, emoji, frequency, target_value, unit,
                  is_active, created_at, updated_at
           FROM habit_definitions
           WHERE id = $1 AND user_id = $2",
    )
    .bind(query.habit_id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("习惯不存在".into()))?;

    let (start_date, end_date) = match &query.month {
        Some(m) => {
            let parts: Vec<&str> = m.split('-').collect();
            if parts.len() == 2 {
                let year: i32 = parts[0].parse().unwrap_or(2026);
                let month: u32 = parts[1].parse().unwrap_or(1);
                let start = chrono::NaiveDate::from_ymd_opt(year, month, 1).unwrap_or_default();
                let end = start + chrono::Months::new(1) - chrono::TimeDelta::days(1);
                (Some(start), Some(end))
            } else {
                (None, None)
            }
        }
        None => (None, None),
    };

    let records = if let (Some(s), Some(e)) = (&start_date, &end_date) {
        sqlx::query_as::<_, HabitRecord>(
            "SELECT id, habit_id, user_id, value, note, record_date, created_at, updated_at
               FROM habit_records
               WHERE habit_id = $1 AND user_id = $2 AND record_date >= $3 AND record_date <= $4
               ORDER BY record_date ASC",
        )
        .bind(query.habit_id)
        .bind(uid)
        .bind(s)
        .bind(e)
        .fetch_all(&state.pool)
        .await?
    } else {
        sqlx::query_as::<_, HabitRecord>(
            "SELECT id, habit_id, user_id, value, note, record_date, created_at, updated_at
               FROM habit_records
               WHERE habit_id = $1 AND user_id = $2
               ORDER BY record_date ASC",
        )
        .bind(query.habit_id)
        .bind(uid)
        .fetch_all(&state.pool)
        .await?
    };

    Ok(Json(CalendarResponse { habit, records }))
}

const HABIT_DEF_COLUMNS: &str =
    "id, user_id, name, emoji, frequency, target_value, unit, is_active, created_at, updated_at";

pub async fn definition_changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
    since: Option<chrono::DateTime<chrono::Utc>>,
) -> Result<ChangesResponse<HabitDefinition>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<HabitDefinition> = if let Some(c) = &cursor {
        sqlx::query_as::<_, HabitDefinition>(&format!(
            "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch)
        .fetch_all(pool).await?
    } else if let Some(s) = &since {
        sqlx::query_as::<_, HabitDefinition>(&format!(
            "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions
             WHERE user_id = $1 AND updated_at >= $2
             ORDER BY updated_at ASC, id ASC LIMIT $3"
        ))
        .bind(uid).bind(s).bind(fetch).fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, HabitDefinition>(&format!(
            "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions
             WHERE user_id = $1 ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid).bind(fetch).fetch_all(pool).await?
    };
    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(Cursor { updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now), id: last.id }.encode())
    } else { None };
    Ok(ChangesResponse { items, next_cursor })
}

pub async fn definition_batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<HabitDefinition>,
) -> Result<Vec<BatchResult<HabitDefinition>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, HabitDefinition>(&format!(
            "INSERT INTO habit_definitions
               (id, user_id, name, emoji, frequency, target_value, unit, is_active, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, now()), $10)
             ON CONFLICT (id) DO UPDATE SET
               name = EXCLUDED.name,
               emoji = EXCLUDED.emoji,
               frequency = EXCLUDED.frequency,
               target_value = EXCLUDED.target_value,
               unit = EXCLUDED.unit,
               is_active = EXCLUDED.is_active,
               updated_at = EXCLUDED.updated_at
             WHERE habit_definitions.updated_at IS NULL OR EXCLUDED.updated_at >= habit_definitions.updated_at
             RETURNING {HABIT_DEF_COLUMNS}"
        ))
        .bind(c.id).bind(uid).bind(&c.name).bind(&c.emoji)
        .bind(&c.frequency).bind(c.target_value).bind(&c.unit)
        .bind(c.is_active).bind(c.created_at).bind(ua)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: Some(r) },
            None => {
                let existing = sqlx::query_as::<_, HabitDefinition>(&format!(
                    "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions WHERE id = $1 AND user_id = $2"
                ))
                .bind(c.id).bind(uid).fetch_optional(&mut *tx).await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: Some(existing) }
            }
        };
        out.push(record);
    }
    tx.commit().await?;
    Ok(out)
}

#[cfg(test)]
mod def_sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@test", uid)).execute(pool).await.unwrap();
        uid
    }

    fn habit(uid: uuid::Uuid, ts: &str) -> HabitDefinition {
        HabitDefinition {
            id: uuid::Uuid::new_v4(), user_id: uid, name: "run".into(), emoji: None,
            frequency: "daily".into(), target_value: None, unit: None, is_active: true,
            created_at: chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc),
            updated_at: Some(chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc)),
        }
    }

    #[sqlx::test]
    async fn def_batch_applies_and_idempotent(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = habit(uid, "2026-06-01T00:00:00Z");
        let out = definition_batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        definition_batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM habit_definitions WHERE user_id=$1")
            .bind(uid).fetch_one(&pool).await.unwrap();
        assert_eq!(n, 1);
    }

    #[sqlx::test]
    async fn def_changes_returns_archived(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let mut c = habit(uid, "2026-06-01T00:00:00Z");
        c.is_active = false;
        definition_batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let resp = definition_changes(&pool, uid, None, 500, None).await.unwrap();
        assert!(resp.items.iter().any(|r| r.id == c.id && !r.is_active));
    }
}

const HABIT_REC_COLUMNS: &str =
    "id, habit_id, user_id, value, note, record_date, created_at, updated_at";

/// habit_checkin 的批量推送载荷（无客户端 id，按自然键 upsert）
#[derive(Debug, Deserialize, FromRow, Serialize)]
pub struct CheckinChange {
    pub habit_id: uuid::Uuid,
    pub record_date: chrono::NaiveDate,
    pub value: Option<f64>,
    pub note: Option<String>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

pub async fn checkin_changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
    since: Option<chrono::DateTime<chrono::Utc>>,
) -> Result<ChangesResponse<HabitRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<HabitRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, HabitRecord>(&format!(
            "SELECT {HABIT_REC_COLUMNS} FROM habit_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch).fetch_all(pool).await?
    } else if let Some(s) = &since {
        sqlx::query_as::<_, HabitRecord>(&format!(
            "SELECT {HABIT_REC_COLUMNS} FROM habit_records
             WHERE user_id = $1 AND updated_at >= $2
             ORDER BY updated_at ASC, id ASC LIMIT $3"
        ))
        .bind(uid).bind(s).bind(fetch).fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, HabitRecord>(&format!(
            "SELECT {HABIT_REC_COLUMNS} FROM habit_records
             WHERE user_id = $1 ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid).bind(fetch).fetch_all(pool).await?
    };
    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(Cursor { updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now), id: last.id }.encode())
    } else { None };
    Ok(ChangesResponse { items, next_cursor })
}

pub async fn checkin_batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<CheckinChange>,
) -> Result<Vec<BatchResult<HabitRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        // 校验习惯归属
        let belongs: Option<uuid::Uuid> =
            sqlx::query_scalar("SELECT id FROM habit_definitions WHERE id=$1 AND user_id=$2")
                .bind(c.habit_id).bind(uid).fetch_optional(&mut *tx).await?;
        if belongs.is_none() {
            // 逐条独立:归属失败不 abort 整批,标记 error 跳过(客户端留待重试/死信)
            out.push(BatchResult { status: "error", record: None });
            continue;
        }
        let applied = sqlx::query_as::<_, HabitRecord>(&format!(
            "INSERT INTO habit_records (user_id, habit_id, value, note, record_date, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (habit_id, record_date) DO UPDATE SET
               value = EXCLUDED.value, note = EXCLUDED.note, updated_at = EXCLUDED.updated_at
             WHERE habit_records.updated_at IS NULL OR EXCLUDED.updated_at >= habit_records.updated_at
             RETURNING {HABIT_REC_COLUMNS}"
        ))
        .bind(uid).bind(c.habit_id).bind(c.value).bind(&c.note)
        .bind(c.record_date).bind(c.updated_at)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: Some(r) },
            None => {
                let existing = sqlx::query_as::<_, HabitRecord>(&format!(
                    "SELECT {HABIT_REC_COLUMNS} FROM habit_records
                     WHERE habit_id=$1 AND record_date=$2 AND user_id=$3"
                ))
                .bind(c.habit_id).bind(c.record_date).bind(uid)
                .fetch_optional(&mut *tx).await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: Some(existing) }
            }
        };
        out.push(record);
    }
    tx.commit().await?;
    Ok(out)
}

#[cfg(test)]
mod checkin_sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user_and_habit(pool: &PgPool) -> (uuid::Uuid, uuid::Uuid) {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@t", uid)).execute(pool).await.unwrap();
        let hid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO habit_definitions (id, user_id, name) VALUES ($1, $2, 'run')")
            .bind(hid).bind(uid).execute(pool).await.unwrap();
        (uid, hid)
    }

    fn ts(s: &str) -> chrono::DateTime<chrono::Utc> {
        chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc)
    }

    #[sqlx::test]
    async fn checkin_batch_upserts_by_natural_key(pool: PgPool) {
        let (uid, hid) = seed_user_and_habit(&pool).await;
        let rd = chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap();
        let c1 = CheckinChange { habit_id: hid, record_date: rd, value: Some(1.0), note: None, updated_at: ts("2026-06-01T00:00:00Z") };
        let c2 = CheckinChange { habit_id: hid, record_date: rd, value: Some(2.0), note: None, updated_at: ts("2026-06-02T00:00:00Z") };
        checkin_batch(&pool, uid, BatchRequest { changes: vec![c1] }).await.unwrap();
        let out = checkin_batch(&pool, uid, BatchRequest { changes: vec![c2] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.as_ref().unwrap().value, Some(2.0));
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM habit_records WHERE habit_id=$1")
            .bind(hid).fetch_one(&pool).await.unwrap();
        assert_eq!(n, 1, "自然键应只一行");
    }

    #[sqlx::test]
    async fn checkin_batch_lww_conflict(pool: PgPool) {
        let (uid, hid) = seed_user_and_habit(&pool).await;
        let rd = chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap();
        let new = CheckinChange { habit_id: hid, record_date: rd, value: Some(5.0), note: None, updated_at: ts("2026-06-05T00:00:00Z") };
        checkin_batch(&pool, uid, BatchRequest { changes: vec![new] }).await.unwrap();
        let old = CheckinChange { habit_id: hid, record_date: rd, value: Some(1.0), note: None, updated_at: ts("2026-06-01T00:00:00Z") };
        let out = checkin_batch(&pool, uid, BatchRequest { changes: vec![old] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
        assert_eq!(out[0].record.as_ref().unwrap().value, Some(5.0), "胜出版本不变");
    }
}
