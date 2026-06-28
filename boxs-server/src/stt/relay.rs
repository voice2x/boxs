// src/stt/relay.rs

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::Response,
    http::HeaderMap,
};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use base64::Engine;
use std::sync::Arc;
use tracing::{info, warn, error, instrument};

use crate::auth::jwt::VerifiedUser;
use crate::stt::xfyun::XfyunUpstream;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    token: Option<String>,
}

/// HTTP 升级到 WebSocket
pub async fn ws_upgrade(
    ws: WebSocketUpgrade,
    Query(query): Query<WsQuery>,
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> Response {
    // 认证
    let token = query.token.or_else(|| {
        headers.get("authorization").and_then(|v| {
            v.to_str()
                .ok()
                .and_then(|s| s.strip_prefix("Bearer ").map(String::from))
        })
    });

    let claims = match token {
        Some(t) => match crate::auth::jwt::verify_access_token(&t, &state.config.jwt_secret) {
            Ok(c) => c,
            Err(e) => {
                warn!(error = %e, "WebSocket JWT 验证失败");
                return Response::builder()
                    .status(401)
                    .body("Unauthorized".into())
                    .unwrap();
            }
        },
        None => {
            return Response::builder()
                .status(401)
                .body("Missing token".into())
                .unwrap();
        }
    };

    // 连接数检查
    if state.active_ws() as usize >= state.config.max_ws_connections {
        return Response::builder()
            .status(429)
            .body("Too many connections".into())
            .unwrap();
    }

    ws.on_upgrade(move |socket| handle_relay(socket, claims, state))
}

/// WebSocket 透传核心
#[instrument(skip(client_ws, state), fields(user_id = %claims.user_id))]
async fn handle_relay(client_ws: WebSocket, claims: VerifiedUser, state: Arc<AppState>) {
    let conn_id = state.inc_ws();
    info!(conn_id, "WebSocket 连接建立");

    let upstream = match XfyunUpstream::connect(
        &state.config.xfyun_app_id,
        &state.config.xfyun_api_key,
        &state.config.xfyun_api_secret,
        "zh_cn",
        "mandarin",
    )
    .await
    {
        Ok(u) => u,
        Err(e) => {
            error!(error = %e, "讯飞上游连接失败");
            let (mut sink, _) = client_ws.split();
            let _ = sink
                .send(Message::Text(
                    r#"{"type":"error","message":"STT服务不可用"}"#.into(),
                ))
                .await;
            state.dec_ws();
            return;
        }
    };

    let (client_sink, client_stream) = client_ws.split();
    let client_sink = Arc::new(tokio::sync::Mutex::new(client_sink));
    let sink_clone = client_sink.clone();
    let app_id = state.config.xfyun_app_id.clone();

    let upstream = Arc::new(tokio::sync::Mutex::new(upstream));
    let up_clone = upstream.clone();

    let pipe_up = async { pipe_up(client_stream, &up_clone, &app_id).await };
    let pipe_down = async { pipe_down(&upstream, &sink_clone).await };

    tokio::select! {
        r = pipe_up => {
            match r {
                Ok(()) => info!(conn_id, "上行管道正常结束"),
                Err(e) => warn!(conn_id, error = %e, "上行管道异常"),
            }
        }
        r = pipe_down => {
            match r {
                Ok(()) => info!(conn_id, "下行管道正常结束"),
                Err(e) => warn!(conn_id, error = %e, "下行管道异常"),
            }
        }
    }

    upstream.lock().await.close().await;
    state.dec_ws();
    info!(conn_id, "WebSocket 连接关闭");
}

/// 上行管道：客户端音频 → 讯飞
async fn pipe_up(
    mut client: futures_util::stream::SplitStream<WebSocket>,
    upstream: &Arc<tokio::sync::Mutex<XfyunUpstream>>,
    app_id: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut first_frame = true;

    while let Some(msg) = client.next().await {
        let msg = msg?;

        match msg {
            Message::Binary(audio) => {
                let status = if first_frame { 0 } else { 1 };
                first_frame = false;
                upstream
                    .lock()
                    .await
                    .send_audio(app_id, &audio, status, "zh_cn", "mandarin")
                    .await?;
            }
            Message::Text(text) => {
                let json: serde_json::Value = serde_json::from_str(&text)?;
                match json["type"].as_str() {
                    Some("audio") => {
                        let audio_b64 = json["data"].as_str().unwrap_or("");
                        let audio = base64::engine::general_purpose::STANDARD
                            .decode(audio_b64)
                            .unwrap_or_default();
                        let status = json["status"].as_i64().unwrap_or(1) as i32;
                        upstream
                            .lock()
                            .await
                            .send_audio(app_id, &audio, status, "zh_cn", "mandarin")
                            .await?;
                    }
                    Some("end") => {
                        upstream
                            .lock()
                            .await
                            .send_audio(app_id, &[], 2, "zh_cn", "mandarin")
                            .await?;
                        break;
                    }
                    _ => {
                        warn!(msg = %text, "未知控制消息");
                    }
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    Ok(())
}

/// 下行管道：讯飞结果 → 客户端
async fn pipe_down(
    upstream: &Arc<tokio::sync::Mutex<XfyunUpstream>>,
    client_sink: &Arc<
        tokio::sync::Mutex<
            futures_util::stream::SplitSink<WebSocket, Message>,
        >,
    >,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    loop {
        match upstream.lock().await.recv_result().await {
            Some(Ok(text)) => {
                let response = serde_json::json!({
                    "type": "result",
                    "text": text,
                    "is_final": false,
                });
                let mut sink = client_sink.lock().await;
                sink.send(Message::Text(response.to_string().into()))
                    .await?;
            }
            Some(Err(e)) => {
                let error_msg = serde_json::json!({
                    "type": "error",
                    "message": e.to_string(),
                });
                let mut sink = client_sink.lock().await;
                let _ = sink
                    .send(Message::Text(error_msg.to_string().into()))
                    .await;
                break;
            }
            None => {
                let final_msg = serde_json::json!({
                    "type": "result",
                    "text": "",
                    "is_final": true,
                });
                let mut sink = client_sink.lock().await;
                let _ = sink
                    .send(Message::Text(final_msg.to_string().into()))
                    .await;
                break;
            }
        }
    }

    Ok(())
}
