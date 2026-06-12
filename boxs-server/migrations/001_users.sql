-- migrations/001_users.sql
-- 认证相关表

-- ── 用户表 ──
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,          -- Argon2id 哈希
  display_name TEXT,
  avatar_url TEXT,
  subscription_tier TEXT DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'pro')),
  stripe_customer_id TEXT,
  email_verified BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE users IS '用户主表';
COMMENT ON COLUMN users.password_hash IS 'Argon2id 哈希，不可逆';

-- ── 刷新令牌表 ──
-- 策略：一次性使用，刷新后旧令牌立即删除
-- 每用户最多保留 5 个活跃令牌（5 台设备）
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,             -- SHA-256 哈希，不存原文
  device_info TEXT,                     -- 设备描述（iOS Safari / Android App...）
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

COMMENT ON TABLE refresh_tokens IS '刷新令牌，一次性使用，哈希存储';

-- ── 邮箱验证码表 ──
-- 策略：6 位数字，10 分钟有效，验证后标记 used_at
CREATE TABLE email_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,                   -- 6 位数字
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_email_verif_user ON email_verifications(user_id, created_at DESC);

COMMENT ON TABLE email_verifications IS '邮箱验证码，10 分钟有效';
