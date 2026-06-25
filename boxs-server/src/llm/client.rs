// src/llm/client.rs

use crate::config::Config;
use crate::error::AppError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct LlmClient {
    http: reqwest::Client,
    base_url: String,
    api_key: String,
    model: String,
    timeout: std::time::Duration,
}

#[derive(Debug, Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    temperature: f32,
    max_tokens: u32,
    response_format: ResponseFormat,
}

#[derive(Debug, Serialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct ResponseFormat {
    #[serde(rename = "type")]
    type_: String,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
    usage: Option<Usage>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    message: ChoiceMessage,
}

#[derive(Debug, Deserialize)]
struct ChoiceMessage {
    content: String,
}

#[derive(Debug, Deserialize)]
struct Usage {
    prompt_tokens: u32,
    completion_tokens: u32,
}

pub struct LlmResult {
    pub content: String,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub model: String,
}

impl LlmClient {
    pub fn new(config: &Config) -> Self {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(config.llm_timeout_secs))
            .build()
            .expect("构建 HTTP 客户端失败");

        Self {
            http,
            base_url: config.llm_base_url.clone(),
            api_key: config.llm_api_key.clone(),
            model: config.llm_model.clone(),
            timeout: std::time::Duration::from_secs(config.llm_timeout_secs),
        }
    }

    /// 调用 LLM，返回 JSON 文本
    pub async fn chat(
        &self,
        system_prompt: &str,
        user_message: &str,
    ) -> Result<LlmResult, AppError> {
        let url = format!("{}/chat/completions", self.base_url);

        let body = ChatRequest {
            model: self.model.clone(),
            messages: vec![
                Message {
                    role: "system".into(),
                    content: system_prompt.into(),
                },
                Message {
                    role: "user".into(),
                    content: user_message.into(),
                },
            ],
            temperature: 0.1,
            max_tokens: 500,
            response_format: ResponseFormat {
                type_: "json_object".into(),
            },
        };

        // 入参日志
        tracing::info!(
            model = %self.model,
            url = %url,
            temperature = body.temperature as f64,
            max_tokens = body.max_tokens,
            system_prompt_len = system_prompt.len(),
            user_message = %user_message,
            "LLM 调用入参",
        );

        let started = std::time::Instant::now();

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .timeout(self.timeout)
            .send()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, model = %self.model, "LLM 请求发送失败");
                e
            })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::error!(status = %status, model = %self.model, body = %text, "LLM 返回错误状态码");
            return Err(AppError::LlmError(format!("LLM 返回 {}", status)));
        }

        let chat_resp: ChatResponse = resp
            .json()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, model = %self.model, "LLM 响应解析失败");
                e
            })?;

        let ChatResponse { choices, usage } = chat_resp;

        let choice = match choices.into_iter().next() {
            Some(c) => c,
            None => {
                tracing::error!(model = %self.model, "LLM 返回空结果");
                return Err(AppError::LlmError("LLM 返回空结果".into()));
            }
        };

        let prompt_tokens = usage.as_ref().map(|u| u.prompt_tokens).unwrap_or(0);
        let completion_tokens = usage.as_ref().map(|u| u.completion_tokens).unwrap_or(0);
        let content = choice.message.content;
        let elapsed_ms = started.elapsed().as_millis() as u64;

        // 结果日志
        tracing::info!(
            model = %self.model,
            prompt_tokens,
            completion_tokens,
            elapsed_ms,
            content = %content,
            "LLM 调用结果",
        );

        Ok(LlmResult {
            content,
            prompt_tokens,
            completion_tokens,
            model: self.model.clone(),
        })
    }
}
