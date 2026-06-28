// src/main.rs

mod auth;
mod config;
mod error;
mod llm;
mod routes;
mod state;
mod stt;
mod data;

use axum::routing::{get, post};
use std::sync::Arc;
use state::AppState;

static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let config = config::Config::from_env();
    let addr = format!("{}:{}", config.host, config.port);

    // 输出数据库连接信息
    tracing::info!("数据库连接信息: {}", config.database_url);

    let state = AppState::new(config).await.expect("初始化失败");

    // 自动数据库迁移
    MIGRATOR.run(&state.pool).await.expect("数据库迁移失败");
    tracing::info!("数据库迁移完成");

    // CORS
    let cors = tower_http::cors::CorsLayer::permissive();

    // 公开路由
    let public = axum::Router::new()
        .route("/register", post(auth::handler::register))
        .route("/login", post(auth::handler::login))
        .route("/refresh", post(auth::handler::refresh));

    // 需要认证的路由
    let protected = axum::Router::new()
        // Auth
        .route("/auth/logout", post(auth::handler::logout))
        .route("/auth/me", get(auth::handler::me))
        .route("/auth/change-password", post(auth::handler::change_password))
        .route("/auth/verify-email", post(auth::handler::verify_email))
        // NLU
        .route("/nlu/classify", post(routes::nlu::classify))
        .route("/nlu/query", post(routes::nlu::query))
        .route("/nlu/correct", post(routes::nlu::correct))
        // Expenses
        .route("/data/expenses/stats", get(routes::data::expense_stats))
        .route("/data/expenses/changes", get(routes::data::expense_changes))
        .route("/data/expenses/batch", post(routes::data::expense_batch))
        // Habits
        .route("/data/habits/checkin", post(routes::data::checkin_habit))
        .route("/data/habits/calendar", get(routes::data::habit_calendar))
        .route("/data/habits/changes", get(routes::data::habit_changes))
        .route("/data/habits/batch", post(routes::data::habit_batch))
        .route("/data/habits/checkins/changes", get(routes::data::checkin_changes))
        .route("/data/habits/checkins/batch", post(routes::data::checkin_batch))
        // Todos
        .route("/data/todos/{id}/complete", post(routes::data::complete_todo))
        .route("/data/todos/changes", get(routes::data::todo_changes))
        .route("/data/todos/batch", post(routes::data::todo_batch))
        .layer(axum::middleware::from_fn_with_state(
            Arc::new(state.clone()),
            auth::middleware::require_auth,
        ));

    let ws_routes = axum::Router::new()
        .route("/stt", get(routes::stt::ws_upgrade));

    let app = axum::Router::new()
        .route("/health", get(routes::health::health))
        .nest("/api/auth", public)
        .nest("/api", protected)
        .nest("/ws", ws_routes)
        .layer(cors)
        .with_state(Arc::new(state));

    tracing::info!(%addr, "Boxs Server 启动");

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.expect("监听 Ctrl+C 失败");
    tracing::info!("收到关闭信号");
}
