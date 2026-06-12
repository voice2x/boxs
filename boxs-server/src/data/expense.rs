// src/data/expense.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize, FromRow)]
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
