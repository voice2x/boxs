# 后端数据同步改造实现计划（方案 A · 后端）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `boxs-server` 增加 `/changes`（增量拉取）和 `/batch`（LWW 批量推送）端点，支撑 iOS 的增量同步 + 持久化发件箱。

**Architecture:** 每个实体（expenses / habits / habit_checkins / todos）新增两个端点：`GET /changes?cursor=` 按 `(updated_at, id)` 复合游标返回增量（含墓碑行）；`POST /batch` 在事务内逐条做 LWW upsert（入参 `updated_at >= 现存` 才应用，否则返回现存版本标记 `conflict`）。新增 `data/sync.rs` 承载游标编解码与通用信封类型。所有写都由 `updated_at` 驱动，墓碑 = `deleted_at` 非空。客户端生成 UUID 作为主键，`/batch` 按 id 幂等 upsert。

**Tech Stack:** Rust · axum 0.8 · sqlx 0.8 (Postgres) · chrono · uuid · base64

**配套 spec：** `docs/superpowers/specs/2026-06-26-ios-backend-sync-design.md`

**测试前提：** `#[sqlx::test]` 需要可用的 Postgres 与 `DATABASE_URL`。用项目自带 docker-compose 起一个 Postgres，然后：
```bash
export DATABASE_URL="postgres://<user>:<pass>@localhost:5432/<db>"
```
`#[sqlx::test(migrations = "migrations")]` 会为每个测试自动建临时库并跑迁移。

**范围说明（刻意排除）：** 现有单条 CRUD 端点（`POST/PUT/DELETE /api/data/{entity}[/id]`）保留不动；同步走 `/batch`+`/changes`。单条 create 不改幂等（YAGNI，SyncEngine 不依赖它）。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `boxs-server/Cargo.toml` | 加 `base64`，sqlx 加 `macros`+`migrate` feature |
| `boxs-server/migrations/005_sync.sql` | habit_records 补 updated_at + 自然键唯一；各表 updated_at 非空回填 + DEFAULT；changes 查询索引 |
| `boxs-server/src/data/sync.rs`（新） | `Cursor` 编解码 + `ChangesResponse`/`BatchRequest`/`BatchResult` 通用信封 |
| `boxs-server/src/data/mod.rs` | 注册 `pub mod sync;` |
| `boxs-server/src/data/expense.rs` | 加 `changes()` + `batch()` 内层函数 |
| `boxs-server/src/data/habit.rs` | `HabitRecord` 结构补 `updated_at` + 改所有 SELECT 列；加 habit / checkin 的 `changes()`+`batch()` |
| `boxs-server/src/data/todo.rs` | 加 `changes()` + `batch()` |
| `boxs-server/src/routes/data.rs` | 8 个薄 handler 包装 |
| `boxs-server/src/main.rs` | 注册 8 条新路由 |

---

## Task 1: 依赖 + 数据库迁移

**Files:**
- Modify: `boxs-server/Cargo.toml`
- Create: `boxs-server/migrations/005_sync.sql`
- Modify: `boxs-server/src/data/mod.rs`

- [ ] **Step 1: 加依赖与 feature**

编辑 `boxs-server/Cargo.toml`，把 sqlx 行改为含 `macros`、`migrate`，并在依赖块加 `base64`：

```toml
sqlx = { version = "0.8", features = ["runtime-tokio", "tls-rustls", "postgres", "chrono", "uuid", "macros", "migrate"] }
base64 = "0.22"
```

- [ ] **Step 2: 注册 sync 模块**

编辑 `boxs-server/src/data/mod.rs`：

```rust
// src/data/mod.rs

pub mod expense;
pub mod habit;
pub mod sync;
pub mod todo;
```

- [ ] **Step 3: 写迁移文件**

创建 `boxs-server/migrations/005_sync.sql`：

```sql
-- migrations/005_sync.sql
-- 同步支持：增量游标 + LWW upsert 所需的列与索引

-- ── habit_records 补 updated_at（增量同步必需）──
ALTER TABLE habit_records ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();

-- 去重：现有代码用 SELECT-then-INSERT 可能产生同 (habit_id, record_date) 重复，先清理
DELETE FROM habit_records a
USING habit_records b
WHERE a.habit_id = b.habit_id
  AND a.record_date = b.record_date
  AND a.id < b.id;

-- 自然键唯一：每习惯每天一条，支持 /batch 幂等 upsert
CREATE UNIQUE INDEX uq_habit_records_habit_date
  ON habit_records(habit_id, record_date);

-- ── updated_at 非空化（增量游标按 updated_at 排序，NULL 行会漏）──
ALTER TABLE expense_records ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE todo_records    ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE habit_records   ALTER COLUMN updated_at SET DEFAULT now();

UPDATE expense_records SET updated_at = created_at WHERE updated_at IS NULL;
UPDATE todo_records    SET updated_at = created_at WHERE updated_at IS NULL;
UPDATE habit_records   SET updated_at = created_at WHERE updated_at IS NULL;

-- ── /changes 查询索引：(user_id, updated_at, id) ──
CREATE INDEX idx_expense_changes   ON expense_records(user_id, updated_at, id);
CREATE INDEX idx_todo_changes      ON todo_records(user_id, updated_at, id);
CREATE INDEX idx_habit_def_changes ON habit_definitions(user_id, updated_at, id);
CREATE INDEX idx_habit_rec_changes ON habit_records(user_id, updated_at, id);
```

- [ ] **Step 4: 跑迁移验证**

确保 Postgres 已起且 `DATABASE_URL` 已设。运行：

```bash
cargo run -p boxs-server
```

预期：日志输出 `数据库迁移完成`，进程启动（Ctrl+C 停止）。若报 `迁移失败`，检查 `005_sync.sql` 语法与 Postgres 连接。

- [ ] **Step 5: 验证编译**

```bash
cargo check -p boxs-server
```

预期：通过（`data/sync.rs` 尚不存在会报错——先建空文件占位）。

创建空文件 `boxs-server/src/data/sync.rs`（内容下一步填），再次 `cargo check` 通过。

- [ ] **Step 6: 提交**

```bash
git add boxs-server/Cargo.toml boxs-server/migrations/005_sync.sql boxs-server/src/data/mod.rs boxs-server/src/data/sync.rs
git commit -m "feat(server): 同步迁移与依赖（habit_records.updated_at、changes 索引、base64）"
```

---

## Task 2: Cursor 编解码 + 通用信封（纯逻辑，单测）

**Files:**
- Modify: `boxs-server/src/data/sync.rs`
- Test: 同文件 `#[cfg(test)] mod tests`

- [ ] **Step 1: 写失败测试**

把 `boxs-server/src/data/sync.rs` 全文替换为：

```rust
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
pub struct BatchRequest<T: DeserializeOwned> {
    pub changes: Vec<T>,
}

#[derive(Debug, serde::Serialize)]
pub struct BatchResult<T: Serialize> {
    pub status: &'static str, // "applied" | "conflict"
    pub record: T,
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
```

- [ ] **Step 2: 跑测试确认通过**

```bash
cargo test -p boxs-server data::sync::tests
```

预期：3 个测试 PASS。

- [ ] **Step 3: 提交**

```bash
git add boxs-server/src/data/sync.rs
git commit -m "feat(server): Cursor 编解码与同步通用信封类型"
```

---

## Task 3: expense 的 `/changes` 与 `/batch`（内层函数 + DB 测试）

**Files:**
- Modify: `boxs-server/src/data/expense.rs`
- Test: 同文件 `#[cfg(test)] mod tests`

- [ ] **Step 1: 写失败的 DB 测试**

在 `boxs-server/src/data/expense.rs` **顶部** use 区加：

```rust
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
```

在文件**末尾**追加：

```rust
// ── 增量同步 ──

const EXPENSE_COLUMNS: &str =
    "id, user_id, record_type, amount_cents, category, note, record_date, \
     deleted_at, created_at, updated_at";

/// 增量拉取记账（按 (updated_at, id) 复合游标）
pub async fn changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<ExpenseRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<ExpenseRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, ExpenseRecord>(&format!(
            "SELECT {EXPENSE_COLUMNS} FROM expense_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid)
        .bind(c.updated_at)
        .bind(c.id)
        .bind(fetch)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, ExpenseRecord>(&format!(
            "SELECT {EXPENSE_COLUMNS} FROM expense_records
             WHERE user_id = $1
             ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid)
        .bind(fetch)
        .fetch_all(pool)
        .await?
    };

    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(
            Cursor {
                updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now),
                id: last.id,
            }
            .encode(),
        )
    } else {
        None
    };
    Ok(ChangesResponse { items, next_cursor })
}

/// 批量 LWW upsert 记账
pub async fn batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<ExpenseRecord>,
) -> Result<Vec<BatchResult<ExpenseRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());

    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, ExpenseRecord>(&format!(
            "INSERT INTO expense_records
               (id, user_id, record_type, amount_cents, category, note, record_date,
                deleted_at, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, now()), $10)
             ON CONFLICT (id) DO UPDATE SET
               record_type = EXCLUDED.record_type,
               amount_cents = EXCLUDED.amount_cents,
               category = EXCLUDED.category,
               note = EXCLUDED.note,
               record_date = EXCLUDED.record_date,
               deleted_at = EXCLUDED.deleted_at,
               updated_at = EXCLUDED.updated_at
             WHERE expense_records.updated_at IS NULL OR EXCLUDED.updated_at >= expense_records.updated_at
             RETURNING {EXPENSE_COLUMNS}"
        ))
        .bind(c.id)
        .bind(uid)
        .bind(&c.record_type)
        .bind(c.amount_cents)
        .bind(&c.category)
        .bind(&c.note)
        .bind(c.record_date)
        .bind(c.deleted_at)
        .bind(c.created_at)
        .bind(ua)
        .fetch_optional(&mut *tx)
        .await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: r },
            None => {
                let existing = sqlx::query_as::<_, ExpenseRecord>(&format!(
                    "SELECT {EXPENSE_COLUMNS} FROM expense_records WHERE id = $1 AND user_id = $2"
                ))
                .bind(c.id)
                .bind(uid)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: existing }
            }
        };
        out.push(record);
    }

    tx.commit().await?;
    Ok(out)
}

#[cfg(test)]
mod sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid)
            .bind(format!("{}@test", uid))
            .execute(pool)
            .await
            .unwrap();
        uid
    }

    fn expense(uid: uuid::Uuid, ts: &str) -> ExpenseRecord {
        ExpenseRecord {
            id: uuid::Uuid::new_v4(),
            user_id: uid,
            record_type: "expense".into(),
            amount_cents: 100,
            category: "food".into(),
            note: None,
            record_date: chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap(),
            deleted_at: None,
            created_at: chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc),
            updated_at: Some(chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc)),
        }
    }

    #[sqlx::test(migrations = "migrations")]
    async fn batch_applies_new(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = expense(uid, "2026-06-01T00:00:00Z");
        let id = c.id;
        let out = batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.id, id);
    }

    #[sqlx::test(migrations = "migrations")]
    async fn batch_is_idempotent(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = expense(uid, "2026-06-01T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM expense_records WHERE user_id = $1")
            .bind(uid)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(n, 1);
    }

    #[sqlx::test(migrations = "migrations")]
    async fn batch_lww_older_is_conflict(pool: PgPool) {
        let uid = seed_user(&pool).await;
        // 先写入 T2
        let mut newer = expense(uid, "2026-06-02T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![newer.clone()] }).await.unwrap();
        // 同 id 推送更旧的 T1 → conflict
        let mut older = newer.clone();
        older.updated_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-01T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        let out = batch(&pool, uid, BatchRequest { changes: vec![older] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
        // 再推送更新的 T3 → applied
        newer.amount_cents = 999;
        newer.updated_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-03T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        let out = batch(&pool, uid, BatchRequest { changes: vec![newer.clone()] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.amount_cents, 999);
    }

    #[sqlx::test(migrations = "migrations")]
    async fn batch_soft_delete_propagates(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let mut c = expense(uid, "2026-06-01T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        c.deleted_at = Some(chrono::DateTime::parse_from_rfc3339("2026-06-05T00:00:00Z").unwrap().with_timezone(&chrono::Utc));
        c.updated_at = c.deleted_at;
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let resp = changes(&pool, uid, None, 500).await.unwrap();
        assert!(resp.items.iter().any(|r| r.id == c.id && r.deleted_at.is_some()));
    }

    #[sqlx::test(migrations = "migrations")]
    async fn changes_paginates_without_overlap(pool: PgPool) {
        let uid = seed_user(&pool).await;
        for i in 0..5 {
            let mut c = expense(uid, "2026-06-01T00:00:00Z");
            c.amount_cents = i;
            c.updated_at = Some(chrono::DateTime::from_timestamp(1_700_000_000 + i as i64, 0).unwrap());
            batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        }
        let p1 = changes(&pool, uid, None, 2).await.unwrap();
        assert_eq!(p1.items.len(), 2);
        assert!(p1.next_cursor.is_some());
        let p2 = changes(&pool, uid, Cursor::decode(p1.next_cursor.as_deref().unwrap()).ok(), 2).await.unwrap();
        let ids: Vec<_> = p1.items.iter().map(|r| r.id).collect();
        assert!(p2.items.iter().all(|r| !ids.contains(&r.id)), "页间不应重叠");
    }
}
```

- [ ] **Step 2: 跑测试确认失败/通过**

```bash
cargo test -p boxs-server data::expense::sync_tests
```

预期：5 个测试 PASS（函数与测试同批写入，应直接通过；若失败据报错修正）。

- [ ] **Step 3: 提交**

```bash
git add boxs-server/src/data/expense.rs
git commit -m "feat(server): 记账 /changes + /batch（LWW upsert + 增量游标）"
```

---

## Task 4: habit_definitions 的 `/changes` 与 `/batch`

**Files:**
- Modify: `boxs-server/src/data/habit.rs`

`HabitDefinition` 结构已有 `updated_at` 且非空，直接复用。

- [ ] **Step 1: 加 use 与列常量**

在 `boxs-server/src/data/habit.rs` 顶部 use 区加：

```rust
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
```

文件末尾追加 `HABIT_DEF_COLUMNS` 常量与两个函数：

```rust
const HABIT_DEF_COLUMNS: &str =
    "id, user_id, name, emoji, frequency, target_value, unit, is_active, created_at, updated_at";

pub async fn definition_changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<HabitDefinition>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<HabitDefinition> = if let Some(c) = &cursor {
        sqlx::query_as::<_, HabitDefinition>(&format!(
            "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch)
        .fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, HabitDefinition>(&format!(
            "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions
             WHERE user_id = $1 ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid).bind(fetch).fetch_all(pool).await?
    };
    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(Cursor { updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now), id: last.id }.encode())
    } else { None };
    Ok(ChangesResponse { items, next_cursor })
}

pub async fn definition_batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<HabitDefinition>,
) -> Result<Vec<BatchResult<HabitDefinition>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, HabitDefinition>(&format!(
            "INSERT INTO habit_definitions
               (id, user_id, name, emoji, frequency, target_value, unit, is_active, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, now()), $10)
             ON CONFLICT (id) DO UPDATE SET
               name = EXCLUDED.name,
               emoji = EXCLUDED.emoji,
               frequency = EXCLUDED.frequency,
               target_value = EXCLUDED.target_value,
               unit = EXCLUDED.unit,
               is_active = EXCLUDED.is_active,
               updated_at = EXCLUDED.updated_at
             WHERE habit_definitions.updated_at IS NULL OR EXCLUDED.updated_at >= habit_definitions.updated_at
             RETURNING {HABIT_DEF_COLUMNS}"
        ))
        .bind(c.id).bind(uid).bind(&c.name).bind(&c.emoji)
        .bind(&c.frequency).bind(c.target_value).bind(&c.unit)
        .bind(c.is_active).bind(c.created_at).bind(ua)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: r },
            None => {
                let existing = sqlx::query_as::<_, HabitDefinition>(&format!(
                    "SELECT {HABIT_DEF_COLUMNS} FROM habit_definitions WHERE id = $1 AND user_id = $2"
                ))
                .bind(c.id).bind(uid).fetch_optional(&mut *tx).await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: existing }
            }
        };
        out.push(record);
    }
    tx.commit().await?;
    Ok(out)
}
```

- [ ] **Step 2: 写 DB 测试**

文件末尾追加：

```rust
#[cfg(test)]
mod def_sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@test", uid)).execute(pool).await.unwrap();
        uid
    }

    fn habit(uid: uuid::Uuid, ts: &str) -> HabitDefinition {
        HabitDefinition {
            id: uuid::Uuid::new_v4(), user_id: uid, name: "run".into(), emoji: None,
            frequency: "daily".into(), target_value: None, unit: None, is_active: true,
            created_at: chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc),
            updated_at: Some(chrono::DateTime::parse_from_rfc3339(ts).unwrap().with_timezone(&chrono::Utc)),
        }
    }

    #[sqlx::test(migrations = "migrations")]
    async fn def_batch_applies_and_idempotent(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = habit(uid, "2026-06-01T00:00:00Z");
        let out = definition_batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        definition_batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM habit_definitions WHERE user_id=$1")
            .bind(uid).fetch_one(&pool).await.unwrap();
        assert_eq!(n, 1);
    }

    #[sqlx::test(migrations = "migrations")]
    async fn def_changes_returns_archived(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let mut c = habit(uid, "2026-06-01T00:00:00Z");
        c.is_active = false;
        definition_batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let resp = definition_changes(&pool, uid, None, 500).await.unwrap();
        assert!(resp.items.iter().any(|r| r.id == c.id && !r.is_active));
    }
}
```

- [ ] **Step 3: 跑测试**

```bash
cargo test -p boxs-server data::habit::def_sync_tests
```

预期：2 个 PASS。

- [ ] **Step 4: 提交**

```bash
git add boxs-server/src/data/habit.rs
git commit -m "feat(server): 习惯定义 /changes + /batch（LWW upsert）"
```

---

## Task 5: habit_records 的 `updated_at` + `/changes` + `/batch`（自然键 upsert）

**Files:**
- Modify: `boxs-server/src/data/habit.rs`

`HabitRecord` 结构当前无 `updated_at`，需补；所有现有 SELECT/RETURNING 列表都要加 `updated_at`。

- [ ] **Step 1: 给 HabitRecord 结构补 updated_at**

在 `boxs-server/src/data/habit.rs` 的 `HabitRecord` 结构加字段：

```rust
#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct HabitRecord {
    pub id: uuid::Uuid,
    pub habit_id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub value: Option<f64>,
    pub note: Option<String>,
    pub record_date: chrono::NaiveDate,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}
```

- [ ] **Step 2: 更新现有 SELECT/RETURNING 列表**

把 `checkin()` 与 `calendar()` 中所有 `SELECT id, habit_id, user_id, value, note, record_date, created_at FROM habit_records` 与对应 `RETURNING` 改为追加 `, updated_at`。即每处列清单变为：

```
id, habit_id, user_id, value, note, record_date, created_at, updated_at
```

`checkin()` 的两条 SQL（UPDATE existing 的 RETURNING、INSERT 的 RETURNING）都要改。`calendar()` 的两条 SELECT 也要改。

- [ ] **Step 3: 加 changes / batch（自然键 upsert）**

文件末尾追加：

```rust
const HABIT_REC_COLUMNS: &str =
    "id, habit_id, user_id, value, note, record_date, created_at, updated_at";

/// habit_checkin 的批量推送载荷（无客户端 id，按自然键 upsert）
#[derive(Debug, Deserialize, FromRow, Serialize)]
pub struct CheckinChange {
    pub habit_id: uuid::Uuid,
    pub record_date: chrono::NaiveDate,
    pub value: Option<f64>,
    pub note: Option<String>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

pub async fn checkin_changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<HabitRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<HabitRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, HabitRecord>(&format!(
            "SELECT {HABIT_REC_COLUMNS} FROM habit_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch).fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, HabitRecord>(&format!(
            "SELECT {HABIT_REC_COLUMNS} FROM habit_records
             WHERE user_id = $1 ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid).bind(fetch).fetch_all(pool).await?
    };
    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(Cursor { updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now), id: last.id }.encode())
    } else { None };
    Ok(ChangesResponse { items, next_cursor })
}

pub async fn checkin_batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<CheckinChange>,
) -> Result<Vec<BatchResult<HabitRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        // 校验习惯归属
        let belongs: Option<uuid::Uuid> =
            sqlx::query_scalar("SELECT id FROM habit_definitions WHERE id=$1 AND user_id=$2")
                .bind(c.habit_id).bind(uid).fetch_optional(&mut *tx).await?;
        if belongs.is_none() {
            return Err(AppError::BadRequest("习惯不存在或不属于该用户".into()));
        }
        let applied = sqlx::query_as::<_, HabitRecord>(&format!(
            "INSERT INTO habit_records (user_id, habit_id, value, note, record_date, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (habit_id, record_date) DO UPDATE SET
               value = EXCLUDED.value, note = EXCLUDED.note, updated_at = EXCLUDED.updated_at
             WHERE habit_records.updated_at IS NULL OR EXCLUDED.updated_at >= habit_records.updated_at
             RETURNING {HABIT_REC_COLUMNS}"
        ))
        .bind(uid).bind(c.habit_id).bind(c.value).bind(&c.note)
        .bind(c.record_date).bind(c.updated_at)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: r },
            None => {
                let existing = sqlx::query_as::<_, HabitRecord>(&format!(
                    "SELECT {HABIT_REC_COLUMNS} FROM habit_records
                     WHERE habit_id=$1 AND record_date=$2 AND user_id=$3"
                ))
                .bind(c.habit_id).bind(c.record_date).bind(uid)
                .fetch_optional(&mut *tx).await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: existing }
            }
        };
        out.push(record);
    }
    tx.commit().await?;
    Ok(out)
}
```

- [ ] **Step 4: 写 DB 测试**

文件末尾追加：

```rust
#[cfg(test)]
mod checkin_sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user_and_habit(pool: &PgPool) -> (uuid::Uuid, uuid::Uuid) {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@t", uid)).execute(pool).await.unwrap();
        let hid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO habit_definitions (id, user_id, name) VALUES ($1, $2, 'run')")
            .bind(hid).bind(uid).execute(pool).await.unwrap();
        (uid, hid)
    }

    fn ts(s: &str) -> chrono::DateTime<chrono::Utc> {
        chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc)
    }

    #[sqlx::test(migrations = "migrations")]
    async fn checkin_batch_upserts_by_natural_key(pool: PgPool) {
        let (uid, hid) = seed_user_and_habit(&pool).await;
        let rd = chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap();
        let c1 = CheckinChange { habit_id: hid, record_date: rd, value: Some(1.0), note: None, updated_at: ts("2026-06-01T00:00:00Z") };
        let c2 = CheckinChange { habit_id: hid, record_date: rd, value: Some(2.0), note: None, updated_at: ts("2026-06-02T00:00:00Z") };
        checkin_batch(&pool, uid, BatchRequest { changes: vec![c1] }).await.unwrap();
        let out = checkin_batch(&pool, uid, BatchRequest { changes: vec![c2] }).await.unwrap();
        assert_eq!(out[0].status, "applied");
        assert_eq!(out[0].record.value, Some(2.0));
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM habit_records WHERE habit_id=$1")
            .bind(hid).fetch_one(&pool).await.unwrap();
        assert_eq!(n, 1, "自然键应只一行");
    }

    #[sqlx::test(migrations = "migrations")]
    async fn checkin_batch_lww_conflict(pool: PgPool) {
        let (uid, hid) = seed_user_and_habit(&pool).await;
        let rd = chrono::NaiveDate::from_ymd_opt(2026, 6, 1).unwrap();
        let new = CheckinChange { habit_id: hid, record_date: rd, value: Some(5.0), note: None, updated_at: ts("2026-06-05T00:00:00Z") };
        checkin_batch(&pool, uid, BatchRequest { changes: vec![new] }).await.unwrap();
        let old = CheckinChange { habit_id: hid, record_date: rd, value: Some(1.0), note: None, updated_at: ts("2026-06-01T00:00:00Z") };
        let out = checkin_batch(&pool, uid, BatchRequest { changes: vec![old] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
        assert_eq!(out[0].record.value, Some(5.0), "胜出版本不变");
    }
}
```

- [ ] **Step 5: 跑全部 habit 测试（含现有 checkin 改动回归）**

```bash
cargo test -p boxs-server data::habit
```

预期：现有 checkin 测试（若有）与新 checkin_sync_tests、def_sync_tests 全 PASS。

- [ ] **Step 6: 提交**

```bash
git add boxs-server/src/data/habit.rs
git commit -m "feat(server): habit_records.updated_at + 打卡 /changes + /batch（自然键 LWW upsert）"
```

---

## Task 6: todo 的 `/changes` 与 `/batch`

**Files:**
- Modify: `boxs-server/src/data/todo.rs`

`TodoRecord` 已有 `updated_at`、`deleted_at`，与 expense 同构。

- [ ] **Step 1: 加 use、列常量、changes、batch、测试**

在 `boxs-server/src/data/todo.rs` 顶部 use 区加：

```rust
use crate::data::sync::{BatchRequest, BatchResult, ChangesResponse, Cursor};
```

文件末尾追加（与 expense 同构，注意 todo 列含 `title/note/due_date/due_time/priority/status/completed_at`）：

```rust
const TODO_COLUMNS: &str =
    "id, user_id, title, note, due_date, due_time, priority, status, \
     completed_at, deleted_at, created_at, updated_at";

pub async fn changes(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    cursor: Option<Cursor>,
    limit: i64,
) -> Result<ChangesResponse<TodoRecord>, AppError> {
    let limit = limit.clamp(1, 500);
    let fetch = limit + 1;
    let mut items: Vec<TodoRecord> = if let Some(c) = &cursor {
        sqlx::query_as::<_, TodoRecord>(&format!(
            "SELECT {TODO_COLUMNS} FROM todo_records
             WHERE user_id = $1 AND (updated_at, id) > ($2, $3)
             ORDER BY updated_at ASC, id ASC LIMIT $4"
        ))
        .bind(uid).bind(c.updated_at).bind(c.id).bind(fetch).fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, TodoRecord>(&format!(
            "SELECT {TODO_COLUMNS} FROM todo_records
             WHERE user_id = $1 ORDER BY updated_at ASC, id ASC LIMIT $2"
        ))
        .bind(uid).bind(fetch).fetch_all(pool).await?
    };
    let next_cursor = if items.len() as i64 > limit {
        let last = items.pop().expect("len > limit");
        Some(Cursor { updated_at: last.updated_at.unwrap_or_else(chrono::Utc::now), id: last.id }.encode())
    } else { None };
    Ok(ChangesResponse { items, next_cursor })
}

pub async fn batch(
    pool: &sqlx::PgPool,
    uid: uuid::Uuid,
    req: BatchRequest<TodoRecord>,
) -> Result<Vec<BatchResult<TodoRecord>>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(req.changes.len());
    for c in req.changes {
        let ua = c.updated_at.unwrap_or_else(chrono::Utc::now);
        let applied = sqlx::query_as::<_, TodoRecord>(&format!(
            "INSERT INTO todo_records
               (id, user_id, title, note, due_date, due_time, priority, status,
                completed_at, deleted_at, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, now()), $12)
             ON CONFLICT (id) DO UPDATE SET
               title = EXCLUDED.title,
               note = EXCLUDED.note,
               due_date = EXCLUDED.due_date,
               due_time = EXCLUDED.due_time,
               priority = EXCLUDED.priority,
               status = EXCLUDED.status,
               completed_at = EXCLUDED.completed_at,
               deleted_at = EXCLUDED.deleted_at,
               updated_at = EXCLUDED.updated_at
             WHERE todo_records.updated_at IS NULL OR EXCLUDED.updated_at >= todo_records.updated_at
             RETURNING {TODO_COLUMNS}"
        ))
        .bind(c.id).bind(uid).bind(&c.title).bind(&c.note)
        .bind(c.due_date).bind(c.due_time).bind(&c.priority).bind(&c.status)
        .bind(c.completed_at).bind(c.deleted_at).bind(c.created_at).bind(ua)
        .fetch_optional(&mut *tx).await?;

        let record = match applied {
            Some(r) => BatchResult { status: "applied", record: r },
            None => {
                let existing = sqlx::query_as::<_, TodoRecord>(&format!(
                    "SELECT {TODO_COLUMNS} FROM todo_records WHERE id = $1 AND user_id = $2"
                ))
                .bind(c.id).bind(uid).fetch_optional(&mut *tx).await?
                .ok_or_else(|| AppError::Internal("conflict 但行不存在".into()))?;
                BatchResult { status: "conflict", record: existing }
            }
        };
        out.push(record);
    }
    tx.commit().await?;
    Ok(out)
}

#[cfg(test)]
mod sync_tests {
    use super::*;
    use sqlx::PgPool;

    async fn seed_user(pool: &PgPool) -> uuid::Uuid {
        let uid = uuid::Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, email, password_hash) VALUES ($1, $2, 'x')")
            .bind(uid).bind(format!("{}@t", uid)).execute(pool).await.unwrap();
        uid
    }

    fn ts(s: &str) -> chrono::DateTime<chrono::Utc> {
        chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc)
    }

    fn todo(uid: uuid::Uuid, t: &str) -> TodoRecord {
        TodoRecord {
            id: uuid::Uuid::new_v4(), user_id: uid, title: "x".into(), note: None,
            due_date: None, due_time: None, priority: Some("medium".into()),
            status: "pending".into(), completed_at: None, deleted_at: None,
            created_at: ts(t), updated_at: Some(ts(t)),
        }
    }

    #[sqlx::test(migrations = "migrations")]
    async fn todo_batch_applies_and_lww(pool: PgPool) {
        let uid = seed_user(&pool).await;
        let c = todo(uid, "2026-06-02T00:00:00Z");
        batch(&pool, uid, BatchRequest { changes: vec![c.clone()] }).await.unwrap();
        let mut older = c.clone();
        older.updated_at = Some(ts("2026-06-01T00:00:00Z"));
        let out = batch(&pool, uid, BatchRequest { changes: vec![older] }).await.unwrap();
        assert_eq!(out[0].status, "conflict");
    }

    #[sqlx::test(migrations = "migrations")]
    async fn todo_changes_paginates(pool: PgPool) {
        let uid = seed_user(&pool).await;
        for i in 0..3 {
            let mut c = todo(uid, "2026-06-01T00:00:00Z");
            c.updated_at = Some(chrono::DateTime::from_timestamp(1_700_000_000 + i as i64, 0).unwrap());
            batch(&pool, uid, BatchRequest { changes: vec![c] }).await.unwrap();
        }
        let p1 = changes(&pool, uid, None, 2).await.unwrap();
        assert_eq!(p1.items.len(), 2);
        assert!(p1.next_cursor.is_some());
    }
}
```

- [ ] **Step 2: 跑测试**

```bash
cargo test -p boxs-server data::todo::sync_tests
```

预期：2 个 PASS。

- [ ] **Step 3: 提交**

```bash
git add boxs-server/src/data/todo.rs
git commit -m "feat(server): 待办 /changes + /batch（LWW upsert）"
```

---

## Task 7: 薄 handler + 注册路由

**Files:**
- Modify: `boxs-server/src/routes/data.rs`
- Modify: `boxs-server/src/main.rs`

- [ ] **Step 1: 在 routes/data.rs 加 handler**

在 `boxs-server/src/routes/data.rs` 顶部 use 区，把 `use crate::data::{expense, habit, todo};` 改为也引入 sync 类型，并在文件末尾加 8 个包装：

```rust
use crate::data::sync::{BatchRequest, Cursor};
```

文件末尾追加：

```rust
// ── Sync: /changes + /batch ──

#[derive(serde::Deserialize)]
pub struct ChangesQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

fn parse_cursor(q: &ChangesQuery) -> Result<Option<Cursor>, AppError> {
    match q.cursor.as_deref() {
        Some(s) if !s.is_empty() => Ok(Some(Cursor::decode(s).map_err(AppError::BadRequest)?)),
        _ => Ok(None),
    }
}

pub async fn expense_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<expense::ChangesResponseExpense>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = expense::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn expense_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<expense::ExpenseRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<expense::ExpenseRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = expense::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn habit_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitDefinition>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = habit::definition_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn habit_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::HabitDefinition>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitDefinition>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = habit::definition_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn checkin_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<habit::HabitRecord>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = habit::checkin_changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn checkin_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<habit::CheckinChange>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<habit::HabitRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = habit::checkin_batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}

pub async fn todo_changes(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    axum::extract::Query(q): axum::extract::Query<ChangesQuery>,
) -> Result<Json<crate::data::sync::ChangesResponse<todo::TodoRecord>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let resp = todo::changes(&state.pool, uid, parse_cursor(&q)?, q.limit.unwrap_or(200)).await?;
    Ok(Json(resp))
}

pub async fn todo_batch(
    State(state): State<Arc<AppState>>,
    claims: VerifiedUser,
    Json(body): Json<BatchRequest<todo::TodoRecord>>,
) -> Result<Json<Vec<crate::data::sync::BatchResult<todo::TodoRecord>>>, AppError> {
    let uid = uuid::Uuid::parse_str(&claims.user_id).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let out = todo::batch(&state.pool, uid, body).await?;
    Ok(Json(out))
}
```

> 注意：上面 `expense_changes` 的返回类型用了 `expense::ChangesResponseExpense`——需要在 `data/expense.rs` 起一个易引用的别名。在 `data/expense.rs` 的 use 下方加：
> ```rust
> pub type ChangesResponseExpense = crate::data::sync::ChangesResponse<ExpenseRecord>;
> ```
> （其余三个 handler 直接用全路径 `crate::data::sync::ChangesResponse<...>`，无需别名。）

- [ ] **Step 2: 注册路由**

编辑 `boxs-server/src/main.rs`，在 protected 路由的 Expenses/Habits/Todos 段各追加两条路由：

Expenses 段（`/data/expenses/{id}` 行之后）加：
```rust
        .route("/data/expenses/changes", get(routes::data::expense_changes))
        .route("/data/expenses/batch", post(routes::data::expense_batch))
```

Habits 段（`/data/habits/calendar` 行之后）加：
```rust
        .route("/data/habits/changes", get(routes::data::habit_changes))
        .route("/data/habits/batch", post(routes::data::habit_batch))
        .route("/data/habits/checkins/changes", get(routes::data::checkin_changes))
        .route("/data/habits/checkins/batch", post(routes::data::checkin_batch))
```

Todos 段（`/data/todos/{id}/complete` 行之后）加：
```rust
        .route("/data/todos/changes", get(routes::data::todo_changes))
        .route("/data/todos/batch", post(routes::data::todo_batch))
```

- [ ] **Step 3: 编译 + 全量测试**

```bash
cargo build -p boxs-server && cargo test -p boxs-server
```

预期：编译通过，所有测试 PASS。

- [ ] **Step 4: 提交**

```bash
git add boxs-server/src/routes/data.rs boxs-server/src/main.rs boxs-server/src/data/expense.rs
git commit -m "feat(server): 注册 /changes + /batch 路由与薄 handler"
```

---

## Task 8: 端到端冒烟（手动 curl）

**Files:** 无（仅验证）

- [ ] **Step 1: 起服务并登录拿 token**

```bash
cargo run -p boxs-server &
# 注册/登录获取 access token（按现有 /api/auth 流程），存到 $TOKEN
```

- [ ] **Step 2: 推一条记账并拉增量**

```bash
curl -s -X POST http://localhost:8080/api/data/expenses/batch \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"changes":[{"id":"550e8400-e29b-41d4-a716-446655440000","user_id":"00000000-0000-0000-0000-000000000000","record_type":"expense","amount_cents":1234,"category":"food","note":null,"record_date":"2026-06-01","deleted_at":null,"created_at":"2026-06-01T00:00:00Z","updated_at":"2026-06-01T00:00:00Z"}]}'
```
预期：`results[0].status == "applied"`。

```bash
curl -s "http://localhost:8080/api/data/expenses/changes?limit=10" -H "Authorization: Bearer $TOKEN"
```
预期：`items` 含上面那条；`next_cursor` 为 null（仅一条）。

- [ ] **Step 3: 验证 LWW（用更旧 updated_at 再推同 id）**

```bash
curl -s -X POST http://localhost:8080/api/data/expenses/batch \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"changes":[{"id":"550e8400-e29b-41d4-a716-446655440000","user_id":"00000000-0000-0000-0000-000000000000","record_type":"expense","amount_cents":1,"category":"food","note":null,"record_date":"2026-06-01","deleted_at":null,"created_at":"2026-06-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z"}]}'
```
预期：`results[0].status == "conflict"`，`record.amount_cents == 1234`（未覆盖）。

- [ ] **Step 4: 停服**

```bash
kill %1
```

---

## 自检清单（执行前确认）

- 4 个实体 × 2 端点 = 8 条新路由，全部经 `require_auth`（在 protected 路由组内）。
- `habit_records` 的 `updated_at` 已加且非空回填；现有 `checkin`/`calendar` 列清单已同步。
- LWW 由 SQL `ON CONFLICT ... WHERE EXCLUDED.updated_at >= ...` 实现；冲突时回 SELECT 现存行。
- 墓碑 = `deleted_at` 非空（expense/todo）；habit 归档 = `is_active=false`（普通字段）；habit_records 无删除。
- 游标 `(updated_at, id)` 复合，服务端不透明 base64url；`null` = 全量引导。
- 测试需 `DATABASE_URL` + 可用 Postgres。
