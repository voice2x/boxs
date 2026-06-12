-- migrations/003_usage.sql
-- 用量统计表

-- ── LLM 调用明细表 ──
-- 明细保留 90 天，超期聚合到 llm_usage_daily 后删除
CREATE TABLE llm_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model TEXT NOT NULL,
  prompt_tokens INT NOT NULL DEFAULT 0,
  completion_tokens INT NOT NULL DEFAULT 0,
  intent TEXT,
  latency_ms INT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_llm_usage_user_date ON llm_usage_logs(user_id, created_at DESC);

-- ── LLM 用量日归档表 ──
CREATE TABLE llm_usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL,
  call_count INT NOT NULL DEFAULT 0,
  total_tokens INT NOT NULL DEFAULT 0,
  models JSONB DEFAULT '{}',
  intents JSONB DEFAULT '{}',
  UNIQUE (user_id, stat_date)
);
CREATE INDEX idx_llm_daily_user_date ON llm_usage_daily(user_id, stat_date DESC);

-- ── STT 调用明细表 ──
CREATE TABLE stt_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  audio_duration_ms INT,
  language TEXT DEFAULT 'zh',
  latency_ms INT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stt_usage_user_date ON stt_usage_logs(user_id, created_at DESC);

-- ── STT 用量日归档表 ──
CREATE TABLE stt_usage_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stat_date DATE NOT NULL,
  call_count INT NOT NULL DEFAULT 0,
  total_duration_ms INT NOT NULL DEFAULT 0,
  providers JSONB DEFAULT '{}',
  UNIQUE (user_id, stat_date)
);
CREATE INDEX idx_stt_daily_user_date ON stt_usage_daily(user_id, stat_date DESC);
