// src/data/sync.rs

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde::{de::DeserializeOwned, Serialize};

/// 增量游标 = 最后消费行的 (updated_at, id)，服务端不透明编码
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cursor {
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub id: uuid::Uuid,
}

impl Cursor {
    pub fn encode(&self) -> String {
        let payload = format!("{}|{}", self.updated_at.timestamp_micros(), self.id);
        URL_SAFE_NO_PAD.encode(payload.as_bytes())
    }

    pub fn decode(s: &str) -> Result<Self, String> {
        let raw = String::from_utf8(URL_SAFE_NO_PAD.decode(s).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        let (ts, id) = raw.split_once('|').ok_or_else(|| "invalid cursor".to_string())?;
        let micros: i64 = ts.parse().map_err(|e: std::num::ParseIntError| e.to_string())?;
        let updated_at = chrono::DateTime::from_timestamp_micros(micros)
            .ok_or_else(|| "invalid timestamp".to_string())?;
        let id = uuid::Uuid::parse_str(id).map_err(|e| e.to_string())?;
        Ok(Cursor { updated_at, id })
    }
}

#[derive(Debug, serde::Serialize)]
pub struct ChangesResponse<T: Serialize> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
#[serde(bound(deserialize = "T: DeserializeOwned"))]
pub struct BatchRequest<T> {
    pub changes: Vec<T>,
}

#[derive(Debug, serde::Serialize)]
pub struct BatchResult<T: Serialize> {
    pub status: &'static str, // "applied" | "conflict" | "error"
    pub record: Option<T>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_roundtrip() {
        let c = Cursor {
            updated_at: chrono::DateTime::from_timestamp_micros(1_700_000_000_000_000).unwrap(),
            id: uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap(),
        };
        let enc = c.encode();
        let dec = Cursor::decode(&enc).unwrap();
        assert_eq!(c, dec);
    }

    #[test]
    fn cursor_rejects_garbage() {
        assert!(Cursor::decode("!!!not-base64!!!").is_err());
        assert!(Cursor::decode("aGVsbG8").is_err()); // 合法 base64 但非 "ts|id"
    }

    #[test]
    fn cursor_ordering_encodes_monotonic_timestamp() {
        let older = Cursor {
            updated_at: chrono::DateTime::from_timestamp_micros(100).unwrap(),
            id: uuid::Uuid::nil(),
        };
        let newer = Cursor {
            updated_at: chrono::DateTime::from_timestamp_micros(200).unwrap(),
            id: uuid::Uuid::nil(),
        };
        // 编码仅用于回传，顺序由 SQL 行比较保证；这里只确认时间戳可还原
        assert!(Cursor::decode(&older.encode()).unwrap().updated_at < Cursor::decode(&newer.encode()).unwrap().updated_at);
    }
}
