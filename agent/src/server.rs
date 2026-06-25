//! HTTP serving layer + custom one-shot `POST /api/chat` endpoint.
//!
//! The ADK framework app (built via `Launcher::build_app()`) exposes its full
//! `/api/*` surface plus the web UI, but its "run agent" routes return SSE
//! event streams and require a pre-created session. iOS wants a single
//! request/response POST returning plain JSON. This module layers a custom
//! `POST /api/chat` route on top of the framework app: it creates a fresh
//! session per request, runs the agent one-shot, concatenates all text parts,
//! and replies with `{"reply": "..."}`.
//!
//! The session is deleted after every turn (success or error) so the
//! stateless one-shot intent holds and `InMemorySessionService` cannot grow
//! unbounded. The chat route also carries its own request timeout and body
//! limit, since `Launcher::build_app()` applies those layers only to its own
//! routes — a merged-in route would otherwise hang indefinitely on a stuck
//! local LLM.

use std::sync::Arc;
use std::time::Duration;

use adk_rust::session::{CreateRequest, DeleteRequest, InMemorySessionService, SessionService};
use adk_rust::{Agent, Content, Launcher, SessionId, UserId};
use adk_rust::runner::Runner;
use adk_cli::launcher::TelemetryConfig;
use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    routing::post,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use tower::ServiceBuilder;
use tower_http::timeout::TimeoutLayer;

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

/// Per-request timeout for a single `/api/chat` turn. Comfortably exceeds one
/// local-LLM turn while bounding a stuck model so the handler cannot hang
/// forever. Matches the framework's own default.
const CHAT_TIMEOUT: Duration = Duration::from_secs(120);

/// Maximum accepted request body for `/api/chat`. A chat message should never
/// approach this; it exists purely as a guard against pathological inputs.
const CHAT_BODY_LIMIT: usize = 1024 * 1024; // 1 MiB

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
/// stream into the reply. The session is ALWAYS deleted before returning —
/// on both success and error — so no per-request state leaks across turns.
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
    // Capture the raw id before any typed-Id validation can fail, so cleanup
    // below can address the session even if the run errors out early.
    let session_id_raw = session.id().to_string();

    // 2. Run the turn. Every code path that returns from this block is funneled
    //    through a single result so the outer handler can always reach `delete`.
    let result = run_turn(
        agent,
        session_service,
        app_name,
        user_id,
        &session_id_raw,
        &req.message,
    )
    .await;

    // 3. Always delete the per-request session (best-effort): success or error,
    //    the session must not linger in `InMemorySessionService`. A failed
    //    delete is logged but never fails the request — the reply (or error)
    //    already in hand is what we surface to the client.
    if let Err(e) = session_service
        .delete(DeleteRequest {
            app_name: app_name.clone(),
            user_id: user_id.clone(),
            session_id: session_id_raw.clone(),
        })
        .await
    {
        tracing::warn!(error = %e, "failed to delete /api/chat session (leaked until process restart)");
    }

    result
}

/// Run a single agent turn against an already-created session.
///
/// Returns the reply on success or an HTTP error tuple on failure. Split out
/// from [`chat`] so the caller can unconditionally delete the session after
/// this returns, regardless of the outcome — this is what guarantees the
/// "every path reaches delete" invariant.
async fn run_turn(
    agent: &Arc<dyn Agent>,
    session_service: &Arc<dyn SessionService>,
    app_name: &str,
    user_id: &str,
    session_id_raw: &str,
    message: &str,
) -> Result<Json<ChatResponse>, (StatusCode, String)> {
    // Build a runner bound to this agent + session service.
    let runner = Runner::builder()
        .app_name(app_name.to_string())
        .agent(agent.clone())
        .session_service(session_service.clone())
        .build()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("build runner: {e}")))?;

    // Run one turn, draining the event stream.
    let user_content = Content::new("user").with_text(message);
    let user_id = UserId::new(user_id.to_string())
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("invalid user id: {e}")))?;
    let session_id = SessionId::new(session_id_raw.to_string())
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("invalid session id: {e}")))?;
    let mut events = runner
        .run(user_id, session_id, user_content)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("start run: {e}")))?;

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
                if let Some(text) = part.text() {
                    raw.push_str(text);
                }
            }
        }
    }

    Ok(Json(ChatResponse {
        reply: normalize_reply(&raw),
    }))
}

// ============================================================
// Serve entry point
// ============================================================

/// Build the merged router (framework app + custom `/api/chat`) and serve it
/// on `0.0.0.0:{port}`. Real-device reachable on the LAN.
///
/// `Launcher::build_app()` applies CORS + `TimeoutLayer` + `DefaultBodyLimit`
/// only to its OWN routes. A route merged in afterward is not covered, so we
/// attach a timeout + body limit to the chat router ourselves before merging.
/// CORS is intentionally NOT added: the iOS client is native HTTP (no browser
/// preflight) and adding a `CorsLayer` would pull `tower-http` in as a direct
/// dependency for no behavioral benefit here.
pub async fn serve(agent: Arc<dyn Agent>, port: u16) -> anyhow::Result<()> {
    let session_service: Arc<dyn SessionService> = Arc::new(InMemorySessionService::new());

    let chat_state = Arc::new(ChatState {
        agent: agent.clone(),
        session_service: session_service.clone(),
        app_name: "boxs_agent".to_string(),
        user_id: "user".to_string(),
    });

    // Timeout bounds a stuck local LLM; body limit guards against pathological
    // inputs. Both applied per-route so they cover /api/chat even though the
    // framework's own layers don't extend to merged-in routes. We use
    // `tower_http::timeout::TimeoutLayer` (not `tower`'s) because the HTTP
    // variant converts a timeout into a 408 response, keeping the service
    // error `Infallible` as axum's `Router::layer` requires.
    let chat_router = Router::new()
        .route("/api/chat", post(chat))
        .layer(
            ServiceBuilder::new()
                .layer(TimeoutLayer::with_status_code(
                    StatusCode::REQUEST_TIMEOUT,
                    CHAT_TIMEOUT,
                ))
                .layer(DefaultBodyLimit::max(CHAT_BODY_LIMIT)),
        )
        .with_state(chat_state);

    // Framework app: all `/api/*` routes + web UI, state fully resolved.
    //
    // `with_telemetry(TelemetryConfig::None)` suppresses the Launcher's own
    // tracing init. main() already installs the global subscriber, and leaving
    // ADK's default (`AdkExporter`) enabled makes `build_app()` call
    // `set_global_default` a second time, panicking with "a global default
    // trace dispatcher has already been set".
    let app = Launcher::new(agent)
        .with_telemetry(TelemetryConfig::None)
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
}
