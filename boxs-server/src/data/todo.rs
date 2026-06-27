// src/data/todo.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
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
    let uid = claims.uid()?;

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
    let uid = claims.uid()?;

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
    let uid = claims.uid()?;

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
    let uid = claims.uid()?;

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
    let uid = claims.uid()?;

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

const TODO_COLUMNS: &str =
    "id, user_id, title, note, due_date, due_time, priority, status, \
     completed_at, deleted_at, created_at, updated_at";

pub async fn changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<TodoRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<TodoRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, TodoRecord>(&format!(
            "SELECT {TODO_COLUMNS} FROM todo_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch).fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, TodoRecord>(&format!(
            "SELECT {TODO_COLUMNS} FROM todo_records
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

pub async fn batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<TodoRecord>,
) -> Result<Vec<BatchResult<TodoRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, TodoRecord>(&format!(
            "INSERT INTO todo_records
               (id, user_id, title, note, due_date, due_time, priority, status,
                completed_at, deleted_at, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, now()), $12)
             ON CONFLICT (id) DO UPDATE SET
               title = EXCLUDED.title,
               note = EXCLUDED.note,
               due_date = EXCLUDED.due_date,
               due_time = EXCLUDED.due_time,
               priority = EXCLUDED.priority,
               status = EXCLUDED.status,
               completed_at = EXCLUDED.completed_at,
               deleted_at = EXCLUDED.deleted_at,
               updated_at = EXCLUDED.updated_at
             WHERE todo_records.updated_at IS NULL OR EXCLUDED.updated_at >= todo_records.updated_at
             RETURNING {TODO_COLUMNS}"
        ))
        .bind(c.id).bind(uid).bind(&c.title).bind(&c.note)
        .bind(c.due_date).bind(c.due_time).bind(&c.priority).bind(&c.status)
        .bind(c.completed_at).bind(c.deleted_at).bind(c.created_at).bind(ua)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: Some(r) },
            None => {
                let existing = sqlx::query_as::<_, TodoRecord>(&format!(
                    "SELECT {TODO_COLUMNS} FROM todo_records WHERE id = $1 AND user_id = $2"
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
mod sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@t", uid)).execute(pool).await.unwrap();
        uid
    }

    fn ts(s: &str) -> chrono::DateTime<chrono::Utc> {
        chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc)
    }

    fn todo(uid: uuid::Uuid, t: &str) -> TodoRecord {
        TodoRecord {
            id: uuid::Uuid::new_v4(), user_id: uid, title: "x".into(), note: None,
            due_date: None, due_time: None, priority: Some("medium".into()),
            status: "pending".into(), completed_at: None, deleted_at: None,
            created_at: ts(t), updated_at: Some(ts(t)),
        }
    }

    #[sqlx::test]
    async fn todo_batch_applies_and_lww(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = todo(uid, "2026-06-02T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let mut older = c.clone();
        older.updated_at = Some(ts("2026-06-01T00:00:00Z"));
        let out = batch(&pool, uid, BatchRequest { changes: vec![older] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
    }

    #[sqlx::test]
    async fn todo_changes_paginates(pool: PgPool) {
        let uid = seed_user(&pool).await;
        for i in 0..3 {
            let mut c = todo(uid, "2026-06-01T00:00:00Z");
            c.updated_at = Some(chrono::DateTime::from_timestamp(1_700_000_000 + i as i64, 0).unwrap());
            batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        }
        let p1 = changes(&pool, uid, None, 2).await.unwrap();
        assert_eq!(p1.items.len(), 2);
        assert!(p1.next_cursor.is_some());
    }
}
