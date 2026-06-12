// src/data/todo.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct TodoRecord {
    pub id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub title: String,
    pub note: Option<String>,
    pub due_date: Option<chrono::NaiveDate>,
    pub due_time: Option<chrono::NaiveTime>,
    pub priority: Option<String>,
    pub status: String,
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
    pub deleted_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTodoRequest {
    pub title: String,
    pub note: Option<String>,
    pub due_date: Option<chrono::NaiveDate>,
    pub due_time: Option<chrono::NaiveTime>,
    pub priority: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateTodoRequest {
    pub title: Option<String>,
    pub note: Option<String>,
    pub due_date: Option<chrono::NaiveDate>,
    pub due_time: Option<chrono::NaiveTime>,
    pub priority: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ListTodosQuery {
    pub status: Option<String>,
}

pub async fn create(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<CreateTodoRequest>,
) -> Result<Json<TodoRecord>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let record = sqlx::query_as::<_, TodoRecord>(
        "INSERT INTO todo_records (user_id, title, note, due_date, due_time, priority)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id, user_id, title, note, due_date, due_time, priority,
                     status, completed_at, deleted_at, created_at, updated_at",
    )
    .bind(uid)
    .bind(&body.title)
    .bind(&body.note)
    .bind(body.due_date)
    .bind(body.due_time)
    .bind(&body.priority)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(record))
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(query): axum::extract::Query<ListTodosQuery>,
) -> Result<Json<Vec<TodoRecord>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let status_filter = query.status.unwrap_or_else(|| "pending".into());

    let records = sqlx::query_as::<_, TodoRecord>(
        "SELECT id, user_id, title, note, due_date, due_time, priority,
                  status, completed_at, deleted_at, created_at, updated_at
           FROM todo_records
           WHERE user_id = $1 AND deleted_at IS NULL AND status = $2
           ORDER BY
             CASE priority
               WHEN 'high' THEN 1
               WHEN 'medium' THEN 2
               WHEN 'low' THEN 3
               ELSE 4
             END,
             due_date ASC NULLS LAST,
             created_at ASC",
    )
    .bind(uid)
    .bind(&status_filter)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(records))
}

pub async fn update(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Json(body): Json<UpdateTodoRequest>,
) -> Result<Json<TodoRecord>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let record = sqlx::query_as::<_, TodoRecord>(
        "SELECT id, user_id, title, note, due_date, due_time, priority,
                  status, completed_at, deleted_at, created_at, updated_at
           FROM todo_records WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("待办不存在".into()))?;

    let updated = sqlx::query_as::<_, TodoRecord>(
        "UPDATE todo_records
           SET title = COALESCE($1, title),
               note = COALESCE($2, note),
               due_date = COALESCE($3, due_date),
               due_time = COALESCE($4, due_time),
               priority = COALESCE($5, priority),
               updated_at = now()
           WHERE id = $6
           RETURNING id, user_id, title, note, due_date, due_time, priority,
                     status, completed_at, deleted_at, created_at, updated_at",
    )
    .bind(&body.title)
    .bind(&body.note)
    .bind(body.due_date)
    .bind(body.due_time)
    .bind(&body.priority)
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
        "UPDATE todo_records SET deleted_at = now() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(uid)
    .execute(&state.pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest("待办不存在".into()));
    }

    Ok(Json(serde_json::json!({ "success": true })))
}

pub async fn complete(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Result<Json<TodoRecord>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let updated = sqlx::query_as::<_, TodoRecord>(
        "UPDATE todo_records
           SET status = 'completed', completed_at = now(), updated_at = now()
           WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL AND status = 'pending'
           RETURNING id, user_id, title, note, due_date, due_time, priority,
                     status, completed_at, deleted_at, created_at, updated_at",
    )
    .bind(id)
    .bind(uid)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| AppError::BadRequest("待办不存在或已完成".into()))?;

    Ok(Json(updated))
}
