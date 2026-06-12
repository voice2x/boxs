// src/state.rs

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use sqlx::PgPool;

use crate::config::Config;
use crate::llm::client::LlmClient;

#[derive(Debug, Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub pool: PgPool,
    pub llm_client: Arc<LlmClient>,
    pub active_ws_connections: Arc<AtomicU64>,
    pub total_connections: Arc<AtomicU64>,
}

impl AppState {
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let pool = PgPool::connect(&config.database_url).await?;
        let llm_client = LlmClient::new(&config);

        Ok(Self {
            config: Arc::new(config),
            pool,
            llm_client: Arc::new(llm_client),
            active_ws_connections: Arc::new(AtomicU64::new(0)),
            total_connections: Arc::new(AtomicU64::new(0)),
        })
    }

    pub fn inc_ws(&self) -> u64 {
        self.total_connections.fetch_add(1, Ordering::Relaxed);
        self.active_ws_connections.fetch_add(1, Ordering::Relaxed) + 1
    }

    pub fn dec_ws(&self) {
        self.active_ws_connections.fetch_sub(1, Ordering::Relaxed);
    }

    pub fn active_ws(&self) -> u64 {
        self.active_ws_connections.load(Ordering::Relaxed)
    }
}
