-- migrations/002_business.sql
-- 业务数据表

-- ── 记账表 ──
-- 金额策略：以「分」为单位存储整数，避免浮点误差
--   ¥35.50 → amount_cents = 3550
CREATE TABLE expense_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  record_type TEXT NOT NULL CHECK (record_type IN ('expense', 'income', 'transfer')),
  amount_cents INT NOT NULL CHECK (amount_cents >= 0),
  category TEXT NOT NULL,
  note TEXT,
  record_date DATE NOT NULL,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ
);
CREATE INDEX idx_expense_user_date ON expense_records(user_id, record_date DESC);
CREATE INDEX idx_expense_user_cat  ON expense_records(user_id, category);

COMMENT ON TABLE expense_records IS '记账表，金额以分为单位存储';

-- ── 习惯定义表 ──
CREATE TABLE habit_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  emoji TEXT,
  frequency TEXT DEFAULT 'daily',
  target_value DOUBLE PRECISION,
  unit TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── 习惯打卡记录表 ──
-- 策略：每天每习惯只打一次
CREATE TABLE habit_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id UUID NOT NULL REFERENCES habit_definitions(id) ON DELETE CASCADE,
  value DOUBLE PRECISION,
  note TEXT,
  record_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_habit_records_user ON habit_records(user_id, record_date DESC);

COMMENT ON TABLE habit_records IS '习惯打卡，每天每习惯一次，值可修改';

-- ── 待办/备忘表 ──
CREATE TABLE todo_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  note TEXT,
  due_date DATE,
  due_time TIME,
  priority TEXT DEFAULT 'medium'
    CHECK (priority IN ('high', 'medium', 'low')),
  status TEXT DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed')),
  completed_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ
);
CREATE INDEX idx_todo_user     ON todo_records(user_id, created_at DESC);

-- ── 操作日志表（撤销功能）──
CREATE TABLE action_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
  target_type TEXT NOT NULL,
  target_id UUID NOT NULL,
  snapshot JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_action_logs_user ON action_logs(user_id, created_at DESC);

COMMENT ON TABLE action_logs IS '操作日志，支持撤销，30 天后清理';
