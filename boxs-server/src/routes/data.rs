// src/routes/data.rs

use axum::{extract::State, Json};
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::data::sync::{BatchRequest, Cursor};
use crate::data::{expense, habit, todo};
use crate::error::AppError;
use crate::state::AppState;

// 单条 CRUD(list/create/update/delete)已由 /changes + /batch 替代并下线;
// 保留下列非 CRUD 端点:stats(聚合)、checkin/calendar(视图)、complete(原子动作)。

pub async fn expense_stats(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<expense::ListExpensesQuery>,
) -> Result<Json<expense::ExpenseStats>, AppError> {
    expense::stats(State(state), claims, axum::extract::Query(query)).await
}

pub async fn checkin_habit(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<habit::CheckinRequest>,
) -> Result<Json<habit::HabitRecord>, AppError> {
    habit::checkin(State(state), claims, Json(body)).await
}

pub async fn habit_calendar(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<habit::CalendarQuery>,
) -> Result<Json<habit::CalendarResponse>, AppError> {
    habit::calendar(State(state), claims, axum::extract::Query(query)).await
}

pub async fn complete_todo(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<todo::TodoRecord>, AppError> {
    todo::complete(State(state), claims, axum::extract::Path(id)).await
}

// ── Sync: /changes + /batch ──

#[derive(serde::Deserialize)]
pub struct ChangesQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
    pub since: Option<String>, // ISO8601;仅引导(cursor 为空)时生效,限定 updated_at >= since
}

fn parse_cursor(q: &ChangesQuery) -> Result<Option<Cursor>, AppError> {
    match q.cursor.as_deref() {
        Some(s) if !s.is_empty() => Ok(Some(Cursor::decode(s).map_err(AppError::BadRequest)?)),
        _ => Ok(None),
    }
}

fn parse_since(q: &ChangesQuery) -> Result<Option<chrono::DateTime<chrono::Utc>>, AppError> {
    q.since
        .as_deref()
        .map(|s| chrono::DateTime::parse_from_rfc3339(s).map(|d| d.with_timezone(&chrono::Utc)).map_err(|e| AppError::BadRequest(e.to_string())))
        .transpose()
}

pub async fn expense_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<expense::ChangesResponseExpense>, AppError> {
    let uid = claims.uid()?;
    let resp = expense::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200), parse_since(&q)?).await?;
    Ok(Json(resp))
}

pub async fn expense_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<expense::ExpenseRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<expense::ExpenseRecord>>>, AppError> {
    let uid = claims.uid()?;
    let out = expense::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn habit_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitDefinition>>, AppError> {
    let uid = claims.uid()?;
    let resp = habit::definition_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200), parse_since(&q)?).await?;
    Ok(Json(resp))
}

pub async fn habit_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::HabitDefinition>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitDefinition>>>, AppError> {
    let uid = claims.uid()?;
    let out = habit::definition_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn checkin_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitRecord>>, AppError> {
    let uid = claims.uid()?;
    let resp = habit::checkin_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200), parse_since(&q)?).await?;
    Ok(Json(resp))
}

pub async fn checkin_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::CheckinChange>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitRecord>>>, AppError> {
    let uid = claims.uid()?;
    let out = habit::checkin_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn todo_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<todo::TodoRecord>>, AppError> {
    let uid = claims.uid()?;
    let resp = todo::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200), parse_since(&q)?).await?;
    Ok(Json(resp))
}

pub async fn todo_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<todo::TodoRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<todo::TodoRecord>>>, AppError> {
    let uid = claims.uid()?;
    let out = todo::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}
