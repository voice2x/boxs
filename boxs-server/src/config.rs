// src/config.rs

#[derive(Debug, Clone)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub jwt_secret: String,
    pub llm_api_key: String,
    pub llm_base_url: String,
    pub llm_model: String,
    pub llm_timeout_secs: u64,
    pub xfyun_app_id: String,
    pub xfyun_api_key: String,
    pub xfyun_api_secret: String,
    pub max_ws_connections: usize,
}

impl Config {
    pub fn from_env() -> Self {
        let host = dotenvy::var("POSTGRES_HOST").unwrap_or_else(|_| "localhost".into());
        let port = dotenvy::var("POSTGRES_PORT").unwrap_or_else(|_| "5432".into());
        let user = dotenvy::var("POSTGRES_USER").unwrap_or_else(|_| "boxs".into());
        let password = dotenvy::var("POSTGRES_PASSWORD").expect("POSTGRES_PASSWORD required");
        let database_url = dotenvy::var("DATABASE_URL")
            .unwrap_or_else(|_| format!("postgresql://{}:{}@{}:{}/boxs", user, password, host, port));

        Self {
            host: dotenvy::var("HOST").unwrap_or_else(|_| "0.0.0.0".into()),
            port: dotenvy::var("PORT").unwrap_or_else(|_| "8000".into()).parse().unwrap(),
            database_url,
            jwt_secret: dotenvy::var("JWT_SECRET").expect("JWT_SECRET required"),
            llm_api_key: dotenvy::var("LLM_API_KEY").unwrap_or_default(),
            llm_base_url: dotenvy::var("LLM_BASE_URL")
                .unwrap_or_else(|_| "https://api.openai.com/v1".into()),
            llm_model: dotenvy::var("LLM_MODEL").unwrap_or_else(|_| "gpt-4o-mini".into()),
            llm_timeout_secs: dotenvy::var("LLM_TIMEOUT_SECS")
                .unwrap_or_else(|_| "5".into())
                .parse()
                .unwrap(),
            xfyun_app_id: dotenvy::var("XFYUN_APP_ID").unwrap_or_default(),
            xfyun_api_key: dotenvy::var("XFYUN_API_KEY").unwrap_or_default(),
            xfyun_api_secret: dotenvy::var("XFYUN_API_SECRET").unwrap_or_default(),
            max_ws_connections: dotenvy::var("MAX_WS_CONNECTIONS")
                .unwrap_or_else(|_| "10000".into())
                .parse()
                .unwrap(),
        }
    }
}
