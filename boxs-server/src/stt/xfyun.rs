// src/stt/xfyun.rs

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use tokio_tungstenite::{connect_async, tungstenite};
use futures_util::{SinkExt, StreamExt};
use tracing::{info, error};
use serde_json::Value;

type HmacSha256 = Hmac<Sha256>;

/// 讯飞 WebSocket 连接
pub struct XfyunUpstream {
    ws: futures_util::stream::SplitStream<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    >,
    sink: futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        tungstenite::Message,
    >,
}

impl XfyunUpstream {
    /// 建立到讯飞的 WebSocket 连接（带签名鉴权）
    pub async fn connect(
        _app_id: &str,
        api_key: &str,
        api_secret: &str,
        _language: &str,
        _accent: &str,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let auth_url = build_auth_url(api_key, api_secret)?;

        info!(url = %auth_url, "连接讯飞上游");

        let (ws_stream, _) = connect_async(&auth_url).await?;
        let (sink, ws) = ws_stream.split();

        Ok(Self { ws, sink })
    }

    /// 发送音频帧
    /// status: 0=首帧(带参数) 1=中间帧 2=末帧
    pub async fn send_audio(
        &mut self,
        app_id: &str,
        audio: &[u8],
        status: i32,
        language: &str,
        accent: &str,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let audio_b64 = BASE64.encode(audio);

        let frame = serde_json::json!({
            "header": {
                "app_id": app_id,
                "status": status,
            },
            "parameter": {
                "iat": {
                    "domain": "iat",
                    "language": language,
                    "accent": accent,
                    "vad_eos": 2000,
                    "dnn_model": "",
                    "pd": "educational",
                }
            },
            "payload": {
                "data": {
                    "status": status,
                    "format": "audio/L16;rate=16000",
                    "encoding": "raw",
                    "audio": audio_b64,
                }
            },
        });

        self.sink
            .send(tungstenite::Message::Text(frame.to_string().into()))
            .await?;

        Ok(())
    }

    /// 接收识别结果
    pub async fn recv_result(
        &mut self,
    ) -> Option<Result<String, Box<dyn std::error::Error + Send + Sync>>> {
        match self.ws.next().await {
            Some(Ok(tungstenite::Message::Text(text))) => {
                Some(extract_text_from_response(&*text))
            }
            Some(Ok(tungstenite::Message::Close(_))) => None,
            Some(Err(e)) => {
                error!(error = %e, "讯飞上游读取错误");
                Some(Err(e.into()))
            }
            None => None,
            _ => None,
        }
    }

    /// 关闭连接
    pub async fn close(&mut self) {
        let _ = self.sink.close().await;
    }
}

/// 生成讯飞 HMAC-SHA256 签名 URL
fn build_auth_url(
    api_key: &str,
    api_secret: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let host = "iat-api.xfyun.cn";
    let path = "/v2/iat";

    let timestamp = chrono::Utc::now()
        .format("%a, %d %b %Y %H:%M:%S GMT")
        .to_string();

    let signature_origin = format!(
        "host: {}\ndate: {}\nGET {} HTTP/1.1",
        host, &timestamp, path
    );

    let mut mac = HmacSha256::new_from_slice(api_secret.as_bytes())?;
    mac.update(signature_origin.as_bytes());
    let signature_bytes = mac.finalize().into_bytes();
    let signature = BASE64.encode(signature_bytes);

    let authorization_origin = format!(
        r#"api_key="{}", algorithm="hmac-sha256", headers="host date request-line", signature="{}""#,
        api_key, signature
    );
    let authorization = BASE64.encode(authorization_origin);
    let date_encoded = BASE64.encode(timestamp.as_bytes());

    Ok(format!(
        "wss://{}{}?authorization={}&date={}&host={}",
        host, path, authorization, date_encoded, host
    ))
}

/// 从讯飞返回中提取文本
fn extract_text_from_response(
    raw: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let json: Value = serde_json::from_str(raw)?;

    let code = json["header"]["code"].as_i64().unwrap_or(0);
    if code != 0 {
        let msg = json["header"]["message"]
            .as_str()
            .unwrap_or("未知错误");
        return Err(format!("讯飞错误 {}: {}", code, msg).into());
    }

    let data_b64 = json["payload"]["result"]["data"]
        .as_str()
        .unwrap_or("");
    if data_b64.is_empty() {
        return Ok(String::new());
    }

    let data_bytes = BASE64.decode(data_b64)?;
    let data_json: Value = serde_json::from_slice(&data_bytes)?;

    let empty: Vec<Value> = vec![];
    let text: String = data_json["ws"]
        .as_array()
        .unwrap_or(&empty)
        .iter()
        .flat_map(|ws| {
            ws["cw"]
                .as_array()
                .unwrap_or(&empty)
                .iter()
                .filter_map(|cw| cw["w"].as_str().map(String::from))
        })
        .collect();

    Ok(text)
}
