// src/llm/prompts.rs

/// 意图分类 + 实体提取 Prompt
///
/// 返回结构必须是**扁平 JSON**，且字段名与 iOS 端 `NLUClassifyResponse` 严格对齐
/// （`amount`/`category`/`note`/`merchant`/`habit_name`/`habit_value`/`content`/
/// `remind_at`/`reply`/`items`，均为顶层）。历史上 prompt 把实体嵌套在 `entities`
/// 下，iOS 的 `Decodable` 期望扁平结构，导致实体全部解码为 nil，记账类别被 UI
/// 兜底成 "其他"。见 `tests::classify_prompt_returns_flat_ios_contract`。
pub fn classify_prompt() -> &'static str {
    r#"你是一个生活助手 NLU 引擎。用户输入一句话，你需要识别意图并提取实体。

支持的意图（intent 只能是以下之一）：
- expense: 记账（amount + category + note）
- habit_checkin: 习惯打卡（habit_name + habit_value）
- todo_add: 待办/备忘（content + remind_at）
- query: 数据查询
- edit: 修改记录
- unknown: 无法识别
- multiple: 一句话含多个意图（用 items 数组逐条列出）

记账分类（category 只能是以下之一）：
餐饮、交通、购物、娱乐、居住、医疗、教育、通讯、工资、红包、其他

严格返回如下 JSON（扁平结构，不要嵌套 entities；未涉及的字段一律为 null；不要输出 markdown 代码块，只输出 JSON 本身）：
{
  "intent": "expense|habit_checkin|todo_add|query|edit|unknown|multiple",
  "confidence": 0.0,
  "amount": null,
  "category": null,
  "note": null,
  "merchant": null,
  "habit_name": null,
  "habit_value": null,
  "content": null,
  "remind_at": null,
  "reply": null,
  "items": null
}

字段说明：
- amount: 金额，数字（如 35.5）
- category: 记账分类
- note: 备注
- merchant: 商户
- habit_name: 习惯名称
- habit_value: 习惯数值，字符串（如 "5"、"10分钟"）
- content: 待办/备忘事项文本
- remind_at: 提醒时间；仅当能确定精确时间时返回 ISO 8601 字符串（如 "2026-06-16T09:00:00Z"），否则为 null
- reply: 当意图为 unknown 或需要直接回复时填入自然语言回复，否则为 null
- items: 仅当 intent 为 multiple 时使用；数组中每个对象含 intent、confidence、amount、category、note、merchant、habit_name、habit_value、content
"#
}

/// AI 对话查询 Prompt
pub fn query_prompt() -> &'static str {
    r#"你是一个个人数据助手。用户会询问关于自己的记账、打卡、待办数据的问题。
请根据提供的数据上下文，用简洁自然的中文回答。

如果数据不足以回答，请说"数据不足，无法回答"。
"#
}

/// 纠错 Prompt
pub fn correct_prompt() -> &'static str {
    r#"你是一个文本纠错引擎。用户输入的语音识别结果可能有错误。
请纠正明显的语音识别错误，保留用户原始意图。

返回 JSON：
{
  "original": "原始文本",
  "corrected": "纠正后文本",
  "changes": ["修改说明1", "修改说明2"]
}
如果无需修改，corrected 与 original 相同，changes 为空数组。
"#
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 契约守护：classify_prompt 返回的 JSON 结构必须与 iOS `NLUClassifyResponse`
    /// 严格对齐 —— 扁平字段 + iOS 意图名。防止回归到嵌套 `entities` 的旧结构
    /// （那会让 iOS 把实体解码为 nil，记账类别兜底成 "其他"）。
    #[test]
    fn classify_prompt_returns_flat_ios_contract() {
        let p = classify_prompt();

        // 扁平字段（顶层），与 iOS NLUClassifyResponse 字段一一对应
        for field in [
            "\"intent\"",
            "\"confidence\"",
            "\"amount\"",
            "\"category\"",
            "\"note\"",
            "\"merchant\"",
            "\"habit_name\"",
            "\"habit_value\"",
            "\"content\"",
            "\"remind_at\"",
            "\"reply\"",
            "\"items\"",
        ] {
            assert!(p.contains(field), "classify_prompt 缺少扁平字段 {field}");
        }

        // 不得再用嵌套 entities（旧结构的根因）
        assert!(
            !p.contains("\"entities\""),
            "classify_prompt 不得再用嵌套 entities 结构"
        );

        // 意图名与 iOS 对齐：todo_add（非 todo），且支持 multiple
        assert!(p.contains("todo_add"), "意图名应为 todo_add（对齐 iOS）");
        assert!(p.contains("multiple"), "应支持 multiple 多意图");
    }
}
