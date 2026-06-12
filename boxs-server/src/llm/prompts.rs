// src/llm/prompts.rs

/// 意图分类 + 实体提取 Prompt
pub fn classify_prompt() -> &'static str {
    r#"你是一个生活助手 NLU 引擎。用户输入一句话，你需要识别意图并提取实体。

支持的意图：
- expense: 记账（金额 + 类别 + 备注）
- habit_checkin: 习惯打卡（动作 + 数值）
- todo: 待办/备忘（事项 + 时间）
- query: 数据查询（时间范围 + 查询类型）
- edit: 修改记录（目标 + 新值）
- unknown: 无法识别

请严格返回 JSON：
{
  "intent": "expense|habit_checkin|todo|query|edit|unknown",
  "confidence": 0.0-1.0,
  "entities": {
    "amount": null 或数字,
    "category": null 或分类,
    "note": null 或备注,
    "action": null 或动作,
    "value": null 或数值,
    "task": null 或事项,
    "time": null 或时间,
    "query_type": null 或查询类型,
    "time_range": null 或时间范围
  }
}

记账分类：餐饮、交通、购物、娱乐、居住、医疗、教育、通讯、工资、红包、其他
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
