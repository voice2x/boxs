// src/data/habit.rs

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::sync::Arc;

use crate::auth::jwt::VerifiedUser;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize, FromRow)]
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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
        "SELECT id, habit_id, user_id, value, note, record_date, created_at
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
            "UPDATE habit_records SET value = $1, note = $2
               WHERE id = $3
               RETURNING id, habit_id, user_id, value, note, record_date, created_at",
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
           RETURNING id, habit_id, user_id, value, note, record_date, created_at",
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
    let uid = uuid::Uuid::parse_str(&claims.user_id)
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

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
            "SELECT id, habit_id, user_id, value, note, record_date, created_at
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
            "SELECT id, habit_id, user_id, value, note, record_date, created_at
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
