// src/routes/data.rs

use axum::{extract::State, Json};
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::data::sync::{BatchRequest, Cursor};
use crate::data::{expense, habit, todo};
use crate::error::AppError;
use crate::state::AppState;

// ── Expenses ──

pub async fn list_expenses(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<expense::ListExpensesQuery>,
) -> Result<Json<expense::ExpenseListResponse>, AppError> {
    expense::list(State(state), claims, axum::extract::Query(query)).await
}

pub async fn create_expense(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<expense::CreateExpenseRequest>,
) -> Result<Json<expense::ExpenseRecord>, AppError> {
    expense::create(State(state), claims, Json(body)).await
}

pub async fn update_expense(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<expense::UpdateExpenseRequest>,
) -> Result<Json<expense::ExpenseRecord>, AppError> {
    expense::update(State(state), claims, axum::extract::Path(id), Json(body)).await
}

pub async fn delete_expense(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    expense::delete(State(state), claims, axum::extract::Path(id)).await
}

pub async fn expense_stats(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<expense::ListExpensesQuery>,
) -> Result<Json<expense::ExpenseStats>, AppError> {
    expense::stats(State(state), claims, axum::extract::Query(query)).await
}

// ── Habits ──

pub async fn list_habits(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
) -> Result<Json<Vec<habit::HabitDefinition>>, AppError> {
    habit::list(State(state), claims).await
}

pub async fn create_habit(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<habit::CreateHabitRequest>,
) -> Result<Json<habit::HabitDefinition>, AppError> {
    habit::create(State(state), claims, Json(body)).await
}

pub async fn update_habit(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<habit::UpdateHabitRequest>,
) -> Result<Json<habit::HabitDefinition>, AppError> {
    habit::update(State(state), claims, axum::extract::Path(id), Json(body)).await
}

pub async fn delete_habit(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    habit::delete(State(state), claims, axum::extract::Path(id)).await
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

// ── Todos ──

pub async fn list_todos(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<todo::ListTodosQuery>,
) -> Result<Json<Vec<todo::TodoRecord>>, AppError> {
    todo::list(State(state), claims, axum::extract::Query(query)).await
}

pub async fn create_todo(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<todo::CreateTodoRequest>,
) -> Result<Json<todo::TodoRecord>, AppError> {
    todo::create(State(state), claims, Json(body)).await
}

pub async fn update_todo(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<todo::UpdateTodoRequest>,
) -> Result<Json<todo::TodoRecord>, AppError> {
    todo::update(State(state), claims, axum::extract::Path(id), Json(body)).await
}

pub async fn delete_todo(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    todo::delete(State(state), claims, axum::extract::Path(id)).await
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
}

fn parse_cursor(q: &ChangesQuery) -> Result<Option<Cursor>, AppError> {
    match q.cursor.as_deref() {
        Some(s) if !s.is_empty() => Ok(Some(Cursor::decode(s).map_err(AppError::BadRequest)?)),
        _ => Ok(None),
    }
}

pub async fn expense_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<expense::ChangesResponseExpense>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = expense::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn expense_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<expense::ExpenseRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<expense::ExpenseRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = expense::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn habit_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitDefinition>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = habit::definition_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn habit_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::HabitDefinition>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitDefinition>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = habit::definition_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn checkin_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitRecord>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = habit::checkin_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn checkin_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::CheckinChange>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = habit::checkin_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn todo_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<todo::TodoRecord>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = todo::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn todo_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<todo::TodoRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<todo::TodoRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = todo::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}
