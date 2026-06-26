// src/data/expense.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
use crate::error::AppError;
use crate::state::AppState;

pub type ChangesResponseExpense = crate::data::sync::ChangesResponse<ExpenseRecord>;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ExpenseRecord {
    pub id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub record_type: String,
    pub amount_cents: i32,
    pub category: String,
    pub note: Option<String>,
    pub record_date: chrono::NaiveDate,
    pub deleted_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateExpenseRequest {
    pub record_type: String,
    pub amount_cents: i32,
    pub category: String,
    pub note: Option<String>,
    pub record_date: chrono::NaiveDate,
}

#[derive(Debug, Deserialize)]
pub struct UpdateExpenseRequest {
    pub record_type: Option<String>,
    pub amount_cents: Option<i32>,
    pub category: Option<String>,
    pub note: Option<String>,
    pub record_date: Option<chrono::NaiveDate>,
}

#[derive(Debug, Deserialize)]
pub struct ListExpensesQuery {
    pub month: Option<String>,      // "2026-06"
    pub page: Option<i64>,          // default 1
    pub page_size: Option<i64>,     // default 20
}

#[derive(Debug, Serialize)]
pub struct ExpenseListResponse {
    pub items: Vec<ExpenseRecord>,
    pub total: i64,
    pub page: i64,
    pub page_size: i64,
}

#[derive(Debug, Serialize)]
pub struct ExpenseStats {
    pub total_income: i64,
    pub total_expense: i64,
    pub categories: Vec<CategoryStats>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CategoryStats {
    pub category: String,
    pub total_cents: i64,
    pub count: i64,
}

pub async fn create(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<CreateExpenseRequest>,
) -> Result<Json<ExpenseRecord>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let record = sqlx::query_as::<_, ExpenseRecord>(
        "INSERT INTO expense_records (user_id, record_type, amount_cents, category, note, record_date)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id, user_id, record_type, amount_cents, category, note, record_date,
                     deleted_at, created_at, updated_at",
    )
    .bind(uid)
    .bind(&body.record_type)
    .bind(body.amount_cents)
    .bind(&body.category)
    .bind(&body.note)
    .bind(body.record_date)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(record))
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<ListExpensesQuery>,
) -> Result<Json<ExpenseListResponse>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let page = query.page.unwrap_or(1).max(1);
    let page_size = query.page_size.unwrap_or(20).min(100);
    let offset = (page - 1) * page_size;

    // Build date filter
    let (start_date, end_date) = match &query.month {
        Some(m) => {
            let parts: Vec<&str> = m.split('-').collect();
            if parts.len() == 2 {
                let year: i32 = parts[0].parse().unwrap_or(2026);
                let month: u32 = parts[1].parse().unwrap_or(1);
                let start = chrono::NaiveDate::from_ymd_opt(year, month, 1).unwrap_or_default();
                let end = start
                    + chrono::Months::new(1)
                    - chrono::TimeDelta::days(1);
                (Some(start), Some(end))
            } else {
                (None, None)
            }
        }
        None => (None, None),
    };

    let total: i64 = if let (Some(s), Some(e)) = (&start_date, &end_date) {
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_date >= $2 AND record_date <= $3",
        )
        .bind(uid)
        .bind(s)
        .bind(e)
        .fetch_one(&state.pool)
        .await?
    } else {
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL",
        )
        .bind(uid)
        .fetch_one(&state.pool)
        .await?
    };

    let items = if let (Some(s), Some(e)) = (&start_date, &end_date) {
        sqlx::query_as::<_, ExpenseRecord>(
            "SELECT id, user_id, record_type, amount_cents, category, note, record_date,
                      deleted_at, created_at, updated_at
               FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_date >= $2 AND record_date <= $3
               ORDER BY record_date DESC, created_at DESC
               LIMIT $4 OFFSET $5",
        )
        .bind(uid)
        .bind(s)
        .bind(e)
        .bind(page_size)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?
    } else {
        sqlx::query_as::<_, ExpenseRecord>(
            "SELECT id, user_id, record_type, amount_cents, category, note, record_date,
                      deleted_at, created_at, updated_at
               FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL
               ORDER BY record_date DESC, created_at DESC
               LIMIT $2 OFFSET $3",
        )
        .bind(uid)
        .bind(page_size)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?
    };

    Ok(Json(ExpenseListResponse {
        items,
        total,
        page,
        page_size,
    }))
}

pub async fn update(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<UpdateExpenseRequest>,
) -> Result<Json<ExpenseRecord>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let record = sqlx::query_as::<_, ExpenseRecord>(
        "SELECT id, user_id, record_type, amount_cents, category, note, record_date,
                  deleted_at, created_at, updated_at
           FROM expense_records WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("记录不存在".into()))?;

    let new_type = body.record_type.unwrap_or(record.record_type);
    let new_amount = body.amount_cents.unwrap_or(record.amount_cents);
    let new_category = body.category.unwrap_or(record.category);
    let new_note = body.note.or(record.note);
    let new_date = body.record_date.unwrap_or(record.record_date);

    let updated = sqlx::query_as::<_, ExpenseRecord>(
        "UPDATE expense_records
           SET record_type = $1, amount_cents = $2, category = $3, note = $4,
               record_date = $5, updated_at = now()
           WHERE id = $6
           RETURNING id, user_id, record_type, amount_cents, category, note, record_date,
                     deleted_at, created_at, updated_at",
    )
    .bind(&new_type)
    .bind(new_amount)
    .bind(&new_category)
    .bind(&new_note)
    .bind(new_date)
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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let result = sqlx::query(
        "UPDATE expense_records SET deleted_at = now() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(uid)
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest("记录不存在".into()));
    }

    Ok(Json(serde_json::json!({ "success": true })))
}

pub async fn stats(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<ListExpensesQuery>,
) -> Result<Json<ExpenseStats>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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

    let total_income: i64;
    let total_expense: i64;

    if let (Some(s), Some(e)) = (&start_date, &end_date) {
        total_income = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(amount_cents), 0)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_type = 'income'
               AND record_date >= $2 AND record_date <= $3",
        )
        .bind(uid)
        .bind(s)
        .bind(e)
        .fetch_one(&state.pool)
        .await?;

        total_expense = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(amount_cents), 0)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_type = 'expense'
               AND record_date >= $2 AND record_date <= $3",
        )
        .bind(uid)
        .bind(s)
        .bind(e)
        .fetch_one(&state.pool)
        .await?;
    } else {
        total_income = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(amount_cents), 0)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_type = 'income'",
        )
        .bind(uid)
        .fetch_one(&state.pool)
        .await?;

        total_expense = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(amount_cents), 0)::bigint FROM expense_records
               WHERE user_id = $1 AND deleted_at IS NULL AND record_type = 'expense'",
        )
        .bind(uid)
        .fetch_one(&state.pool)
        .await?;
    }

    // Category breakdown
    let categories: Vec<CategoryStats> = sqlx::query_as::<_, CategoryStats>(
        "SELECT category, COALESCE(SUM(amount_cents), 0)::bigint as total_cents,
                  count(*)::bigint as count
           FROM expense_records
           WHERE user_id = $1 AND deleted_at IS NULL AND record_type = 'expense'
           GROUP BY category
           ORDER BY total_cents DESC",
    )
    .bind(uid)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(ExpenseStats {
        total_income,
        total_expense,
        categories,
    }))
}

// ── 增量同步 ──

const EXPENSE_COLUMNS: &str =
    "id, user_id, record_type, amount_cents, category, note, record_date, \
     deleted_at, created_at, updated_at";

/// 增量拉取记账（按 (updated_at, id) 复合游标）
pub async fn changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<ExpenseRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<ExpenseRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, ExpenseRecord>(&format!(
            "SELECT {EXPENSE_COLUMNS} FROM expense_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid)
        .bind(c.updated_at)
        .bind(c.id)
        .bind(fetch)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, ExpenseRecord>(&format!(
            "SELECT {EXPENSE_COLUMNS} FROM expense_records
             WHERE user_id = $1
             ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid)
        .bind(fetch)
        .fetch_all(pool)
        .await?
    };

    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(
            Cursor {
                updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now),
                id: last.id,
            }
            .encode(),
        )
    } else {
        None
    };
    Ok(ChangesResponse { items, next_cursor })
}

/// 批量 LWW upsert 记账
pub async fn batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<ExpenseRecord>,
) -> Result<Vec<BatchResult<ExpenseRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());

    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, ExpenseRecord>(&format!(
            "INSERT INTO expense_records
               (id, user_id, record_type, amount_cents, category, note, record_date,
                deleted_at, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, now()), $10)
             ON CONFLICT (id) DO UPDATE SET
               record_type = EXCLUDED.record_type,
               amount_cents = EXCLUDED.amount_cents,
               category = EXCLUDED.category,
               note = EXCLUDED.note,
               record_date = EXCLUDED.record_date,
               deleted_at = EXCLUDED.deleted_at,
               updated_at = EXCLUDED.updated_at
             WHERE expense_records.updated_at IS NULL OR EXCLUDED.updated_at >= expense_records.updated_at
             RETURNING {EXPENSE_COLUMNS}"
        ))
        .bind(c.id)
        .bind(uid)
        .bind(&c.record_type)
        .bind(c.amount_cents)
        .bind(&c.category)
        .bind(&c.note)
        .bind(c.record_date)
        .bind(c.deleted_at)
        .bind(c.created_at)
        .bind(ua)
        .fetch_optional(&mut *tx)
        .await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: r },
            None => {
                let existing = sqlx::query_as::<_, ExpenseRecord>(&format!(
                    "SELECT {EXPENSE_COLUMNS} FROM expense_records WHERE id = $1 AND user_id = $2"
                ))
                .bind(c.id)
                .bind(uid)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: existing }
            }
        };
        out.push(record);
    }

    tx.commit().await?;
    Ok(out)
}

#[cfg(test)]
mod sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid)
            .bind(format!("{}@test", uid))
            .execute(pool)
            .await
            .unwrap();
        uid
    }

    fn expense(uid: uuid::Uuid, ts: &str) -> ExpenseRecord {
        ExpenseRecord {
            id: uuid::Uuid::new_v4(),
            user_id: uid,
            record_type: "expense".into(),
            amount_cents: 100,
            category: "food".into(),
            note: None,
            record_date: chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap(),
            deleted_at: None,
            created_at: chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc),
            updated_at: Some(chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc)),
        }
    }

    #[sqlx::test]
    async fn batch_applies_new(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = expense(uid, "2026-06-01T00:00:00Z");
        let id = c.id;
        let out = batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.id, id);
    }

    #[sqlx::test]
    async fn batch_is_idempotent(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = expense(uid, "2026-06-01T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM expense_records WHERE user_id = $1")
            .bind(uid)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(n, 1);
    }

    #[sqlx::test]
    async fn batch_lww_older_is_conflict(pool: PgPool) {
        let uid = seed_user(&pool).await;
        // 先写入 T2
        let mut newer = expense(uid, "2026-06-02T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![newer.clone()] }).await.unwrap();
        // 同 id 推送更旧的 T1 → conflict
        let mut older = newer.clone();
        older.updated_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-01T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        let out = batch(&pool, uid, BatchRequest { changes: vec![older] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
        // 再推送更新的 T3 → applied
        newer.amount_cents = 999;
        newer.updated_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-03T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        let out = batch(&pool, uid, BatchRequest { changes: vec![newer.clone()] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.amount_cents, 999);
    }

    #[sqlx::test]
    async fn batch_soft_delete_propagates(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let mut c = expense(uid, "2026-06-01T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        c.deleted_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-05T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        c.updated_at = c.deleted_at;
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let resp = changes(&pool, uid, None, 500).await.unwrap();
        assert!(resp.items.iter().any(|r| r.id == c.id && r.deleted_at.is_some()));
    }

    #[sqlx::test]
    async fn changes_paginates_without_overlap(pool: PgPool) {
        let uid = seed_user(&pool).await;
        for i in 0..5 {
            let mut c = expense(uid, "2026-06-01T00:00:00Z");
            c.amount_cents = i;
            c.updated_at = Some(chrono::DateTime::from_timestamp(1_700_000_000 + i as i64, 0).unwrap());
            batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        }
        let p1 = changes(&pool, uid, None, 2).await.unwrap();
        assert_eq!(p1.items.len(), 2);
        assert!(p1.next_cursor.is_some());
        let p2 = changes(&pool, uid, Cursor::decode(p1.next_cursor.as_deref().unwrap()).ok(), 2).await.unwrap();
        let ids: Vec<_> = p1.items.iter().map(|r| r.id).collect();
        assert!(p2.items.iter().all(|r| !ids.contains(&r.id)), "页间不应重叠");
    }
}
