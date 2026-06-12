-- migrations/004_housekeeping.sql
-- 清理任务（pg_cron 或外部定时任务调用）

-- 清理过期刷新令牌
-- SELECT cron.schedule('0 3 * * *', $$DELETE FROM refresh_tokens WHERE expires_at < now()$$);

-- 清理过期邮箱验证码
-- SELECT cron.schedule('0 3 * * *', $$DELETE FROM email_verifications WHERE expires_at < now()$$);

-- 清理 90 天前的 LLM 明细
-- SELECT cron.schedule('0 4 * * *', $$DELETE FROM llm_usage_logs WHERE created_at < now() - interval '90 days'$$);

-- 清理 90 天前的 STT 明细
-- SELECT cron.schedule('0 4 * * *', $$DELETE FROM stt_usage_logs WHERE created_at < now() - interval '90 days'$$);

-- 清理 30 天前的操作日志
-- SELECT cron.schedule('0 4 * * *', $$DELETE FROM action_logs WHERE created_at < now() - interval '30 days'$$);

-- 聚合 LLM 日用量
-- SELECT cron.schedule('0 2 * * *', $$
--   INSERT INTO llm_usage_daily (user_id, stat_date, call_count, total_tokens, models, intents)
--   SELECT user_id, created_at::date, count(*), sum(prompt_tokens + completion_tokens),
--          json_object_agg(model, cnt), json_object_agg(intent, icnt)
--   FROM (
--     SELECT user_id, model, intent, created_at::date as d,
--            count(*) as cnt, count(*) as icnt
--     FROM llm_usage_logs
--     WHERE created_at >= date_trunc('day', now() - interval '1 day')
--       AND created_at < date_trunc('day', now())
--     GROUP BY user_id, model, intent, created_at::date
--   ) sub
--   GROUP BY user_id, d
--   ON CONFLICT (user_id, stat_date) DO UPDATE
--     SET call_count = EXCLUDED.call_count, total_tokens = EXCLUDED.total_tokens
-- $$);

SELECT 1; -- placeholder so migration is not empty
