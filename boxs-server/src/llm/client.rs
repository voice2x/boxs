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

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .timeout(self.timeout)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::error!(status = %status, body = %text, "LLM API 错误");
            return Err(AppError::LlmError(format!("LLM 返回 {}", status)));
        }

        let chat_resp: ChatResponse = resp.json().await?;

        let choice = chat_resp
            .choices
            .into_iter()
            .next()
            .ok_or_else(|| AppError::LlmError("LLM 返回空结果".into()))?;

        Ok(LlmResult {
            content: choice.message.content,
            prompt_tokens: chat_resp
                .usage
                .as_ref()
                .map(|u| u.prompt_tokens)
                .unwrap_or(0),
            completion_tokens: chat_resp
                .usage
                .as_ref()
                .map(|u| u.completion_tokens)
                .unwrap_or(0),
            model: self.model.clone(),
        })
    }
}
