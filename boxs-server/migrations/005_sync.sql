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
