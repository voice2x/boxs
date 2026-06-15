//! HTTP serving layer + custom one-shot `POST /api/chat` endpoint.
//!
//! The ADK framework app (built via `Launcher::build_app()`) exposes its full
//! `/api/*` surface plus the web UI, but its "run agent" routes return SSE
//! event streams and require a pre-created session. iOS wants a single
//! request/response POST returning plain JSON. This module layers a custom
//! `POST /api/chat` route on top of the framework app: it creates a fresh
//! session per request, runs the agent one-shot, concatenates all text parts,
//! and replies with `{"reply": "..."}`.

use std::sync::Arc;

use adk_rust::session::{CreateRequest, InMemorySessionService, SessionService};
use adk_rust::{Agent, Content, Launcher, Part, SessionId, UserId};
use adk_rust::runner::Runner;
use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::post,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};

// ============================================================
// Request / response types
// ============================================================

/// Body of `POST /api/chat`: just the user's natural-language message.
#[derive(Debug, Deserialize)]
pub struct ChatRequest {
    pub message: String,
}

/// Reply payload returned to the client.
#[derive(Debug, Serialize)]
pub struct ChatResponse {
    pub reply: String,
}

/// Shared handler state. Cheap to clone behind an `Arc`.
pub struct ChatState {
    pub agent: Arc<dyn Agent>,
    pub session_service: Arc<dyn SessionService>,
    pub app_name: String,
    pub user_id: String,
}

/// Fallback reply when the agent emits no text (after trimming).
const EMPTY_REPLY: &str = "（无回复）";

/// Trim a model reply and substitute a fallback when it ends up empty.
///
/// Some local models surround their output with stray whitespace/newlines;
/// trimmed-empty output would serialize to `{"reply":""}` which is unhelpful
/// for the client, so we substitute a visible placeholder.
fn normalize_reply(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        EMPTY_REPLY.to_string()
    } else {
        trimmed.to_string()
    }
}

// ============================================================
// Handler
// ============================================================

/// One-shot chat handler.
///
/// Creates a fresh session, builds a `Runner`, runs the message to
/// completion, and concatenates every `Part::Text` fragment from the event
/// stream into the reply. Any failure surfaces as HTTP 500.
async fn chat(
    State(state): State<Arc<ChatState>>,
    Json(req): Json<ChatRequest>,
) -> Result<Json<ChatResponse>, (StatusCode, String)> {
    let ChatState {
        ref agent,
        ref session_service,
        ref app_name,
        ref user_id,
    } = *state;

    // 1. Fresh, stateless session per request.
    let session = session_service
        .create(CreateRequest {
            app_name: app_name.clone(),
            user_id: user_id.clone(),
            session_id: None,
            state: std::collections::HashMap::new(),
        })
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("create session: {e}")))?;
    let session_id = session.id().to_string();

    // 2. Build a runner bound to this agent + session service.
    let runner = Runner::builder()
        .app_name(app_name.clone())
        .agent(agent.clone())
        .session_service(session_service.clone())
        .build()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("build runner: {e:?}")))?;

    // 3. Run one turn, draining the event stream.
    let user_content = Content::new("user").with_text(&req.message);
    let user_id = UserId::new(user_id.clone())
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("invalid user id: {e}")))?;
    let session_id = SessionId::new(session_id)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("invalid session id: {e}")))?;
    let mut events = runner
        .run(user_id, session_id, user_content)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("start run: {e:?}")))?;

    let mut raw = String::new();
    while let Some(event) = events.next().await {
        let event = match event {
            Ok(evt) => evt,
            Err(e) => {
                tracing::error!(error = %e, "event stream error while serving /api/chat");
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("event stream: {e}"),
                ));
            }
        };
        if let Some(content) = &event.llm_response.content {
            for part in &content.parts {
                if let Some(text) = part_text(part) {
                    raw.push_str(text);
                }
            }
        }
    }

    Ok(Json(ChatResponse {
        reply: normalize_reply(&raw),
    }))
}

/// Extract text from a part, mirroring `Part::text()` but kept local so the
/// handler reads as a plain function (and is robust to the exact enum shape).
fn part_text(part: &Part) -> Option<&str> {
    match part {
        Part::Text { text } => Some(text),
        _ => None,
    }
}

// ============================================================
// Serve entry point
// ============================================================

/// Build the merged router (framework app + custom `/api/chat`) and serve it
/// on `0.0.0.0:{port}`. Real-device reachable on the LAN.
pub async fn serve(agent: Arc<dyn Agent>, port: u16) -> anyhow::Result<()> {
    let session_service: Arc<dyn SessionService> = Arc::new(InMemorySessionService::new());

    let chat_state = Arc::new(ChatState {
        agent: agent.clone(),
        session_service: session_service.clone(),
        app_name: "boxs_agent".to_string(),
        user_id: "user".to_string(),
    });

    let chat_router = Router::new().route("/api/chat", post(chat)).with_state(chat_state);

    // Framework app: all `/api/*` routes + web UI, state fully resolved.
    let app = Launcher::new(agent)
        .build_app()
        .map_err(|e| anyhow::anyhow!("build_app failed: {e:?}"))?;
    let app = app.merge(chat_router);

    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "Boxs Agent HTTP 服务启动（0.0.0.0），POST /api/chat");
    axum::serve(listener, app).await?;
    Ok(())
}

// ============================================================
// Tests (types + helpers only — the handler needs a live agent)
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_request_deserializes_from_json() {
        let json = r#"{"message":"hi"}"#;
        let req: ChatRequest = serde_json::from_str(json).expect("valid ChatRequest");
        assert_eq!(req.message, "hi");
    }

    #[test]
    fn chat_request_round_trips_extra_whitespace() {
        let json = r#"{"message":"  午饭 35 块  "}"#;
        let req: ChatRequest = serde_json::from_str(json).expect("valid ChatRequest");
        assert_eq!(req.message, "  午饭 35 块  ");
    }

    #[test]
    fn chat_request_rejects_missing_message() {
        let json = r#"{}"#;
        let result: Result<ChatRequest, _> = serde_json::from_str(json);
        assert!(result.is_err(), "message field is required");
    }

    #[test]
    fn chat_response_serializes_to_reply_field() {
        let resp = ChatResponse {
            reply: "已记录：餐饮 ¥35.00".to_string(),
        };
        let json = serde_json::to_string(&resp).expect("serializable");
        assert!(json.contains("\"reply\""));
        assert!(json.contains("已记录"));
    }

    #[test]
    fn normalize_reply_trims_surrounding_whitespace() {
        assert_eq!(normalize_reply("  hello\n"), "hello");
        assert_eq!(normalize_reply("\n\n  已记录  \n"), "已记录");
    }

    #[test]
    fn normalize_reply_uses_fallback_when_empty() {
        assert_eq!(normalize_reply(""), EMPTY_REPLY);
        assert_eq!(normalize_reply("   \n\t  "), EMPTY_REPLY);
        assert_eq!(normalize_reply("   "), EMPTY_REPLY);
    }

    #[test]
    fn normalize_reply_preserves_internal_whitespace() {
        assert_eq!(normalize_reply("  午饭 35 块  "), "午饭 35 块");
        // only outer whitespace is trimmed
        assert_eq!(normalize_reply("a  b"), "a  b");
    }

    #[test]
    fn part_text_extracts_from_text_variant() {
        let part = Part::Text {
            text: "hello world".to_string(),
        };
        assert_eq!(part_text(&part), Some("hello world"));
    }

    #[test]
    fn part_text_returns_none_for_non_text_variants() {
        let part = Part::FunctionCall {
            name: "record_expense".to_string(),
            args: serde_json::json!({}),
            id: None,
            thought_signature: None,
        };
        assert_eq!(part_text(&part), None);
    }
}
