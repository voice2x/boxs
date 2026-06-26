# iOS ↔ 后端数据同步改造设计（方案 A）

- 日期：2026-06-26
- 范围：`boxs-server`（Rust / axum / sqlx / Postgres）+ `platform/ios/Boxs`（Swift / GRDB）
- 状态：设计已确认，待写实现计划

## 1. 背景与现状

当前同步方案（`SyncService.swift`）：全量刷新 + 乐观写入 fire-and-forget。

- 拉取：启动时 `syncAll()` 并发拉取当月记账 / 全量习惯 / 待处理待办，upsert 到 GRDB。
- 推送：本地创建后 fire-and-forget `POST`，后端生成新 UUID → **删本地旧行 + 插服务端新行**。

### 1.1 核心问题

| 问题 | 影响 |
|------|------|
| **ID 模型脆弱（根因）** | push 失败后本地残留客户端专属 UUID；下次 pull 服务端版本按不同 ID 被当成新行插入 → **重复数据** |
| 无增量同步 | 每次全量拉取，数据量增大后浪费带宽 |
| 无持久化队列 | push 失败（断网/5xx）数据永久丢失，本地与后端永久不一致 |
| 无冲突解决 | 多设备编辑靠"服务端 ID 覆盖"，会丢更新 |
| 无后台同步 | 必须打开 App 才同步 |

### 1.2 已确认的决策

- 架构方案：**A**（增量游标 + 持久化发件箱 + 服务端 LWW）。
- 后台同步：**本轮包含**（BGTaskScheduler + NWPathMonitor）。
- 冲突策略：**客户端时钟 LWW**（最后编辑胜出，last-edit-wins）。
- 习惯删除语义：**归档**（`is_active=false`，作为普通更新走增量），不引入真墓碑。
- 使用场景：单人多设备（手机 + iPad/网页交替编辑）。

## 2. 目标与非目标

### 目标
1. push **永不丢数据**：本地写入即落盘，断网/崩溃后恢复可继续推送。
2. **增量同步**：仅拉取自上次以来变更的记录。
3. 多设备 **冲突可裁决**：同一记录在多端编辑，按最后编辑时间定胜，不静默丢更新。
4. **联网即同步 + 周期后台同步**。
5. 修复历史 ID 模型导致的重复数据隐患。

### 非目标（本期不做）
- 字段级合并（field-level merge）、CRDT。
- 实时推送（WebSocket 下行推送）——保留升级到方案 B 的路径，但本期不实现。
- 端到端加密。
- 多账号 / 团队协作。

## 3. 架构总览

```
iOS 设备                                 后端 Postgres
┌────────────────────────────┐          ┌──────────────────────┐
│ UI / ViewModel             │          │ expense_records      │
│   ↓ 本地写                 │          │ todo_records         │
│ AppDatabase (GRDB)         │          │ habit_definitions    │
│   • 业务表 + sync_dirty    │  drain   │ habit_records        │
│   • sync_outbox (待发)  ────┼─────────▶│ /batch  (LWW 裁决)   │
│   • sync_cursor (游标)     │          │  ↑ 服务端权威        │
│ SyncEngine (actor)         │  pull    │                      │
│   drain → pull ────────────┼─────────▶│ /changes?cursor=…    │
│                            │◀─────────│ items[] (含墓碑)     │
│ NWPathMonitor / BGTask     │          │ nextCursor           │
└────────────────────────────┘          └──────────────────────┘
```

每个同步周期固定顺序：**先 drain（推送本地变更）后 pull（拉取远端变更）**。先推送使本地编辑在服务端裁决，再拉取带回对所有设备裁决后的最终状态。

## 4. 根因修正：稳定的客户端生成 ID

### 4.1 规则
- 客户端在**创建时**生成 UUID v4，作为该记录的**全局唯一 ID**，本地与服务端共用。
- 后端 create 改为按 `id` 幂等 **upsert**：`INSERT ... ON CONFLICT (id) DO UPDATE`。
- **不再"删旧插新"**：push 响应仅确认 ID，本地行已持有该 ID → push 可安全无限重试。
- 历史孤儿客户端 UUID（曾 push 失败的本地行）在首次 drain 时按 id upsert 即建立服务端行，**顺带修复历史重复**。

### 4.2 例外：habit_records（一天一次打卡）
天然唯一键为 `(habit_id, user_id, record_date)`。该实体：
- 服务端按自然键 upsert（保留现有语义），`id` 由服务端分配。
- 客户端按 `(habitId, recordDate)` 对账匹配，outbox key 用复合键 `"habitId|recordDate"`。
- 其余 3 个实体（expense / todo / habit_definition）用客户端 ID 做主键。

## 5. 后端设计（boxs-server）

### 5.1 Schema migration

- `habit_records` 增加 `updated_at TIMESTAMPTZ`（checkin upsert 时按入参写入）。
- `expense_records` / `todo_records` 已有 `deleted_at`（墓碑）。
- `habit_definitions` 的"删除"=`is_active=false`，作为普通更新，无需墓碑。
- 约定：**任何变更（含软删除）都必须 bump `updated_at`**，这样删除/归档也能通过 `/changes` 增量传播。

### 5.2 LWW 写入逻辑（核心）

所有 update / batch 处理统一走 LWW 比较，**不再无脑 `updated_at = now()`**：

```
入参 change: { id, updated_at, deleted, ...字段 }
现存 row（按 id 或自然键查）:
  - 不存在           → INSERT（用入参 updated_at）
  - 入参.updated_at >= 现存.updated_at → 应用变更，updated_at = 入参.updated_at
  - 入参.updated_at <  现存.updated_at → 冲突，跳过，返回现存（胜出）版本
```

软删除 = `{ deleted: true, updated_at }` → 置 `deleted_at = updated_at` 并 bump `updated_at`，同样受 LWW 守卫。

> 客户端时钟 LWW：保留"最后编辑胜出"语义。单用户多设备场景客户端时钟漂移风险低；若后续发现偏移问题，可改服务端单调 `revision` 序列（见 §10 风险）。

### 5.3 新增端点（每实体）

实体集合：`expenses` / `todos` / `habits` / `habit_checkins`。

#### `GET /api/data/{entity}/changes`
查询：`cursor=<opaque>&limit=N`（默认 N=200）。`cursor` 缺省/为空 = 全量引导。

响应：
```json
{
  "items": [ /* 变更记录，含已软删（带 deleted_at）/已归档（is_active=false）的行 */ ],
  "nextCursor": "<opaque> | null"
}
```

- 排序：按 `(updated_at, id)` 复合升序；游标 = 最后消费行的 `(updated_at, id)` 不透明编码（base64url）。
- 查询条件：`(updated_at, id) > (cursor_ts, cursor_id)`，`LIMIT N+1` 判断是否还有更多。
- 复合游标避免同毫秒行被漏；因客户端 upsert 幂等，重复行无害。
- `habit_checkins` 的排序键为 `(updated_at, habit_id, record_date)`，items 含 `habit_id/record_date/value/note/updated_at`。

#### `POST /api/data/{entity}/batch`
请求：
```json
{ "changes": [ { "id": "...", "updated_at": "...", "deleted": false, "...字段": ... } ] }
```
响应：
```json
{
  "results": [
    { "id": "...", "status": "applied" | "conflict", "record": { /* 服务端当前(胜出)版本 */ } }
  ]
}
```

- 服务端对每条 change 执行 §5.2 LWW。
- 返回每条的服务端当前版本与状态：`applied`（我方写入）/ `conflict`（我方更旧，返回的是另一设备的新版本）。
- `habit_checkins` 的 change 用自然键 `{ habit_id, record_date, value, note, updated_at }`，`id` 由服务端返回。

#### 旧端点
现有单条 CRUD（`POST/PUT/DELETE /api/data/{entity}[/id]`）**保留**（过渡期），内部可委托同一 LWW 逻辑。SyncEngine 改用 `/batch` + `/changes`。

### 5.4 认证
不变：JWT access + refresh（`auth/middleware.rs`）。`/batch`、`/changes` 均走 `require_auth`。

## 6. iOS 设计（GRDB + SyncEngine）

### 6.1 本地 schema（migration v2）

新表：

```swift
// 持久化待发变更队列（推送权威源）
sync_outbox:
  id            INTEGER PRIMARY KEY AUTOINCREMENT
  entity        TEXT NOT NULL          // expenses/todos/habits/habit_checkins
  recordKey     TEXT NOT NULL          // id 或 "habitId|recordDate"
  op            TEXT NOT NULL          // upsert | delete
  payload       BLOB NOT NULL          // JSON 快照（含 updated_at）
  attempts      INTEGER NOT NULL DEFAULT 0
  createdAt     DATETIME NOT NULL
  UNIQUE(entity, recordKey)            // 每条记录只保留最新待发操作

// 各实体最后消费的服务端游标
sync_cursor:
  entity        TEXT PRIMARY KEY
  cursor        TEXT                   // 不透明，null=未引导
  lastSyncedAt  DATETIME
```

现有表加列：`sync_dirty BOOLEAN NOT NULL DEFAULT 0`（标记本地有未同步改动；用于 UI"未同步"角标与拉取冲突判断）。

> `habit_record` 本地已有 `updatedAt` 列（v1 schema 已具备）。`expense_record`/`todo_record`/`habit_definition` 已有 `updatedAt`。

### 6.2 本地写入路径

用户增改删（ViewModel 调用）：
1. 在业务表写入/修改记录，置 `sync_dirty = true`。
2. **在本地编辑那一刻打 `updated_at` 时间戳**（`Date()`）。该值写入记录字段、发件箱 JSON 快照，并作为发往服务端 LWW 的比较值（见 §5.2）。它是"最后编辑胜出"语义的时间依据。
3. upsert 对应 `sync_outbox` 行（按 `(entity, recordKey)` 唯一键），写入最新 JSON 快照 + `op`。
   - 同一记录多次离线编辑 → outbox 仅保留最新一次操作（`updated_at` 取最近一次编辑）。
   - 若最新 `op = delete` 且该记录从未成功推送 → 服务端按 id 软删影响 0 行，幂等无害。
4. 写库即落盘，进程被杀也不丢。

### 6.3 SyncEngine（actor，替换 SyncService）

对外：`sync()`（drain + pull）、`drainOutbox()`、`pullAll()`。
内部串行执行，自动同步最小间隔 30s 防抖。

#### Drain（推送）
1. 按 `entity` 分组读取 `sync_outbox`（按 createdAt 排序）。
2. 逐实体 `POST /api/data/{entity}/batch { changes }`。
3. 逐 result：将 `record` upsert 到本地业务表（服务端权威，采纳胜出版本）→ 删除对应 outbox 行 → 清该记录 `sync_dirty`。
4. 失败行 `attempts++` 留待下周期（见 §8）。

#### Pull（拉取）
1. 逐实体：`GET /api/data/{entity}/changes?cursor=<sync_cursor.cursor>&limit=200`，循环直到 `nextCursor == null`。
2. items upsert 到本地（按 id 或自然键匹配）；`deleted_at` 非空 → 本地软删；`is_active=false` → 本地归档。
3. 存 `nextCursor` 到 `sync_cursor`。
4. 首次 `cursor=null` → 全量引导一次，之后纯增量。

### 6.4 冲突对账
- 服务端 LWW 已在 drain 时裁决：我方更新，`status=applied`；我方更旧，`status=conflict`，返回的是另一设备新版本 → 本地 upsert 覆盖采纳。
- 该 outbox 行**仍删除**（已尝试、已裁决），**不会无限重推**。
- pull 阶段同理：远端 `updated_at` 更新的行覆盖本地（但本地若有未推送 outbox 行，下一周期 drain 仍会以我方 updated_at 再次裁决——若我方确实更旧则再次 conflict 被采纳，最终收敛）。

## 7. 后台与联网触发

- **NWPathMonitor**（最可靠）：网络 `.satisfied` 时触发 `drainOutbox()` + 一次 `pullAll()`。
- **BGTaskScheduler**（`BGAppRefreshTask`）：注册周期后台刷新，尽力触发 `sync()`（iOS 调度不确定，属增量保障，不保证及时）。
- **前台**：`AppDelegate` 启动时 `sync()`（沿用现有钩子）。
- 去抖：SyncEngine actor 串行 + 自动同步最小间隔 30s。

## 8. 错误处理与重试

| 场景 | 处理 |
|------|------|
| 网络/超时/5xx | outbox 行保留，指数退避（`attempts` 越多重试越晚），下周期重试 |
| 4xx（校验失败等） | 该行进**死信**（标记不再重试），日志记录，可选 UI 提示，避免毒丸阻塞队列 |
| 401 | 走现有 token 刷新（`APIClient`）；刷新失败则暂停同步、提示重登录 |
| 批量部分失败 | 按 `result.status` 仅清除 `applied`/已裁决的 outbox 行；`conflict` 也清除 |

## 9. 迁移与灰度

1. 后端：migration（`habit_records.updated_at`）+ 新端点上线，旧端点保留。
2. iOS：GRDB migration v2（加表 + `sync_dirty` 列），`SyncService` → `SyncEngine`。
3. 首次同步 `cursor=null` → 全量引导拉取一次，建立游标，之后纯增量。
4. 历史"孤儿客户端 UUID"行在首次 drain 时按 id upsert 建起服务端行，修复历史重复。
5. 灰度：新旧端点共存，App 强制升级后可下线单条 push。

## 10. 风险与取舍

- **客户端时钟漂移**：单用户低风险；若出现"快时钟设备总赢"，后续改服务端单调 `revision BIGINT`（序列 + 触发器），游标改用 revision，对接口无破坏性变更。
- **BGTaskScheduler 不保证及时**：以 NWPathMonitor 联网触发为主，后台任务为辅。
- **/batch 单次体积**：限制单批最大 changes 数（如 100），超出分批。
- **habit_records 无墓碑**：本期不支持"删除打卡"；若需要，后续给该表加 `deleted_at` 并纳入墓碑流（同 expense/todo 机制）。

## 11. 测试策略

### 后端
- `/changes`：游标翻页不漏行；`nextCursor=null` 后二次拉取为空；重复拉取幂等。
- `/batch`：LWW（旧 `updated_at` 被拒并返回 conflict）；幂等 upsert（同 id 两次 → 一行）；墓碑传播；`habit_checkins` 自然键 upsert。
- 用 sqlx 测试 Postgres（`sqlx::test` 或 testcontainers）。

### iOS
- 内存 GRDB + mock `APIClient`（编排脚本化响应）：
  - drain 落服务端版本、清 outbox、推游标。
  - pull 增量推进游标（二次为空）。
  - 冲突：返回 `conflict` 版本被本地采纳，outbox 行清除。
  - **outbox 跨"重启"**：写后重开数据库重读，待发不丢。
  - 4xx → 死信；网络错误 → 留行重试。
  - 幂等：重复推送同 outbox → 服务端一行。

## 12. 涉及文件（预估）

### 后端
- `boxs-server/migrations/`：新增 `habit_records.updated_at`。
- `boxs-server/src/data/{expense,todo,habit}.rs`：抽 LWW 写入逻辑、加 `/changes` + `/batch` handler。
- `boxs-server/src/routes/data.rs` + `main.rs`：注册新路由。
- 新增 `boxs-server/src/data/sync.rs`（可选）：LWW 比较 + 游标编解码公共逻辑。

### iOS
- `platform/ios/Boxs/Core/Database/AppDatabase.swift`：migration v2（`sync_outbox`/`sync_cursor`/`sync_dirty`）。
- 新增 `SyncEngine.swift`（替换 `SyncService.swift` 的职责）。
- 新增 `SyncOutbox.swift` / `SyncCursor.swift`（GRDB 记录）。
- `Endpoints.swift` / `DTOs.swift`：`/changes`、`/batch` 端点与 DTO。
- `APIClient.swift`：错误分类（4xx 死信区分）。
- `AppDelegate.swift`：保留启动同步钩子。
- 新增 `BackgroundSync.swift`：BGTaskScheduler + NWPathMonitor 接线。
- 各 ViewModel：本地写入改为"写表 + upsert outbox"，移除直接 `pushXxx` fire-and-forget。
