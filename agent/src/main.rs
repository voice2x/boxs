mod server;

use adk_rust::prelude::*;
use adk_rust::model::openai::{OpenAICompatible, OpenAICompatibleConfig};
use adk_rust::tool::FunctionTool;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;
use tracing_subscriber::EnvFilter;

// ============================================================
// 1. 工具参数定义 (JsonSchema 让 LLM 知道传什么参数)
// ============================================================

#[derive(JsonSchema, Serialize, Deserialize, Debug)]
struct RecordExpenseParams {
    /// 金额，例如 35.5
    amount: f64,
    /// 类别：餐饮、交通、购物、娱乐、居住、医疗、教育、其他
    category: String,
    /// 备注说明
    description: Option<String>,
    /// 日期，格式 YYYY-MM-DD，默认今天
    date: Option<String>,
}

#[derive(JsonSchema, Serialize, Deserialize, Debug)]
struct RecordHabitParams {
    /// 习惯名称：运动、阅读、冥想、早起、喝水 等
    habit_name: String,
    /// 完成情况描述，例如 "跑了5公里"
    detail: Option<String>,
    /// 日期，格式 YYYY-MM-DD，默认今天
    date: Option<String>,
}

#[derive(JsonSchema, Serialize, Deserialize, Debug)]
struct AddMemoParams {
    /// 备忘内容
    content: String,
    /// 提醒时间，格式 YYYY-MM-DD HH:MM，可选
    remind_at: Option<String>,
    /// 优先级：高、中、低
    priority: Option<String>,
}

#[derive(JsonSchema, Serialize, Deserialize, Debug)]
struct QueryRecordsParams {
    /// 查询类型：expense（支出）、habit（习惯）、memo（备忘）
    record_type: String,
    /// 查询日期范围起始，格式 YYYY-MM-DD
    from_date: Option<String>,
    /// 查询日期范围结束，格式 YYYY-MM-DD
    to_date: Option<String>,
    /// 类别筛选（仅支出类型有效）
    category: Option<String>,
}

#[derive(JsonSchema, Serialize, Deserialize, Debug)]
struct GetSystemInfoParams {
    /// 要查询的信息类型：disk、memory、cpu、processes
    info_type: String,
}

// ============================================================
// 2. 工具实现 (async handler)
// ============================================================

fn create_expense_tool() -> Arc<dyn Tool> {
    Arc::new(
        FunctionTool::new(
            "record_expense",
            "记录一笔支出。当用户提到花钱、消费、购买等信息时使用此工具。",
            |_ctx, args| async move {
                let amount = args
                    .get("amount")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                let category = args
                    .get("category")
                    .and_then(|v| v.as_str())
                    .unwrap_or("其他")
                    .to_string();
                let description = args
                    .get("description")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let date = args
                    .get("date")
                    .and_then(|v| v.as_str())
                    .unwrap_or("today")
                    .to_string();

                println!("[记账] ¥{amount} | {category} | {description} | {date}");

                Ok(json!({
                    "success": true,
                    "message": format!("已记录：{category} ¥{amount:.2}"),
                    "record": {
                        "id": format!("EXP-{}", chrono::Utc::now().timestamp_millis()),
                        "amount": amount,
                        "category": category,
                        "description": description,
                        "date": date,
                    }
                }))
            },
        )
        .with_parameters_schema::<RecordExpenseParams>(),
    )
}

fn create_habit_tool() -> Arc<dyn Tool> {
    Arc::new(
        FunctionTool::new(
            "record_habit",
            "记录习惯完成情况。当用户提到运动、阅读、冥想等日常习惯时使用此工具。",
            |_ctx, args| async move {
                let habit_name = args
                    .get("habit_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("未命名")
                    .to_string();
                let detail = args
                    .get("detail")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let date = args
                    .get("date")
                    .and_then(|v| v.as_str())
                    .unwrap_or("today")
                    .to_string();

                println!("[打卡] {habit_name}: {detail} ({date})");

                Ok(json!({
                    "success": true,
                    "message": format!("已打卡：{habit_name} ✓"),
                    "record": {
                        "id": format!("HAB-{}", chrono::Utc::now().timestamp_millis()),
                        "habit_name": habit_name,
                        "detail": detail,
                        "date": date,
                    }
                }))
            },
        )
        .with_parameters_schema::<RecordHabitParams>(),
    )
}

fn create_memo_tool() -> Arc<dyn Tool> {
    Arc::new(
        FunctionTool::new(
            "add_memo",
            "添加一条备忘事项。当用户提到需要记住的事情、会议、待办等时使用此工具。",
            |_ctx, args| async move {
                let content = args
                    .get("content")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let remind_at = args
                    .get("remind_at")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let priority = args
                    .get("priority")
                    .and_then(|v| v.as_str())
                    .unwrap_or("中")
                    .to_string();

                println!("[备忘] {content} | 提醒:{remind_at} | 优先级:{priority}");

                Ok(json!({
                    "success": true,
                    "message": format!("已添加备忘：{content}"),
                    "record": {
                        "id": format!("MEMO-{}", chrono::Utc::now().timestamp_millis()),
                        "content": content,
                        "remind_at": remind_at,
                        "priority": priority,
                    }
                }))
            },
        )
        .with_parameters_schema::<AddMemoParams>(),
    )
}

fn create_query_tool() -> Arc<dyn Tool> {
    Arc::new(
        FunctionTool::new(
            "query_records",
            "查询历史记录。当用户想查看过去的支出、习惯打卡、备忘等信息时使用。",
            |_ctx, args| async move {
                let record_type = args
                    .get("record_type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("expense");
                let from_date = args
                    .get("from_date")
                    .and_then(|v| v.as_str())
                    .unwrap_or("本周");
                let to_date = args
                    .get("to_date")
                    .and_then(|v| v.as_str())
                    .unwrap_or("今天");
                let category = args
                    .get("category")
                    .and_then(|v| v.as_str())
                    .unwrap_or("全部");

                println!("[查询] {record_type} | {from_date}~{to_date} | {category}");

                Ok(json!({
                    "success": true,
                    "records": [
                        {"id": "EXP-001", "amount": 35.0, "category": "餐饮", "date": "2026-06-11", "description": "午饭"},
                        {"id": "EXP-002", "amount": 28.0, "category": "交通", "date": "2026-06-11", "description": "打车"},
                    ],
                    "summary": {
                        "total": 63.0,
                        "count": 2,
                        "period": format!("{from_date} ~ {to_date}")
                    }
                }))
            },
        )
        .with_parameters_schema::<QueryRecordsParams>(),
    )
}

fn create_system_info_tool() -> Arc<dyn Tool> {
    Arc::new(
        FunctionTool::new(
            "get_system_info",
            "获取本机系统信息（磁盘、内存、CPU、进程）。展示 Agent 访问本地系统的能力。",
            |_ctx, args| async move {
                let info_type = args
                    .get("info_type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("disk");

                let result = match info_type {
                    "disk" => {
                        let output = std::process::Command::new("df")
                            .args(["-h", "/"])
                            .output();
                        match output {
                            Ok(out) => String::from_utf8_lossy(&out.stdout).to_string(),
                            Err(e) => format!("获取失败: {e}"),
                        }
                    }
                    "memory" => {
                        let output = std::process::Command::new("vm_stat").output();
                        match output {
                            Ok(out) => String::from_utf8_lossy(&out.stdout).to_string(),
                            Err(e) => format!("获取失败: {e}"),
                        }
                    }
                    "cpu" => {
                        let output = std::process::Command::new("top")
                            .args(["-l", "1", "-n", "0", "-s", "0"])
                            .output();
                        match output {
                            Ok(out) => {
                                let text = String::from_utf8_lossy(&out.stdout);
                                text.lines().take(10).collect::<Vec<_>>().join("\n")
                            }
                            Err(e) => format!("获取失败: {e}"),
                        }
                    }
                    "processes" => {
                        let output = std::process::Command::new("ps").args(["aux"]).output();
                        match output {
                            Ok(out) => {
                                let text = String::from_utf8_lossy(&out.stdout);
                                text.lines().take(15).collect::<Vec<_>>().join("\n")
                            }
                            Err(e) => format!("获取失败: {e}"),
                        }
                    }
                    _ => "未知类型，支持: disk, memory, cpu, processes".to_string(),
                };

                Ok(json!({
                    "info_type": info_type,
                    "data": result
                }))
            },
        )
        .with_parameters_schema::<GetSystemInfoParams>(),
    )
}

// ============================================================
// 3. 模型配置 — 连接本地 llama.cpp (OpenAI 兼容 API)
// ============================================================

fn create_local_model(base_url: &str, model_name: &str) -> anyhow::Result<Arc<dyn Llm>> {
    let config = OpenAICompatibleConfig::new("not-needed", model_name)
        .with_provider_name("llama.cpp")
        .with_base_url(base_url);

    let model = OpenAICompatible::new(config)?;
    Ok(Arc::new(model))
}

// ============================================================
// 4. 主函数
// ============================================================

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    dotenvy::dotenv().ok();

    println!("╔══════════════════════════════════════════╗");
    println!("║   Boxs Agent - 本地 LLM 生活记录助手      ║");
    println!("╚══════════════════════════════════════════╝");
    println!();

    let llm_base_url =
        std::env::var("LLM_BASE_URL").unwrap_or_else(|_| "http://localhost:8080/v1".to_string());
    let llm_model =
        std::env::var("LLM_MODEL").unwrap_or_else(|_| "local".to_string());

    println!("连接模型: {llm_base_url} ({llm_model})");

    let model = create_local_model(&llm_base_url, &llm_model)?;

    let tools: Vec<Arc<dyn Tool>> = vec![
        create_expense_tool(),
        create_habit_tool(),
        create_memo_tool(),
        create_query_tool(),
        create_system_info_tool(),
    ];

    println!("已加载 {} 个工具:", tools.len());
    for tool in &tools {
        println!("  - {}", tool.name());
    }
    println!();

    let mut agent_builder = LlmAgentBuilder::new("boxs_agent")
        .description("Boxs 生活记录助手")
        .instruction(
            r#"你是 Boxs 生活记录助手。用户会说一句自然语言，你需要识别意图并调用工具完成操作。

## 你的能力

1. **记账** - 用户提到花钱、消费、购买
   - "午饭花了 35 块" → 调用 record_expense
   - "打车 28，奶茶 15" → 调用两次 record_expense

2. **习惯打卡** - 用户提到运动、阅读等日常习惯
   - "今天跑了5公里" → 调用 record_habit (habit_name=运动)

3. **备忘** - 用户提到需要记住的事
   - "周五下午三点跟老王开会" → 调用 add_memo

4. **查询** - 用户想查看历史记录
   - "这周花了多少钱" → 调用 query_records

5. **系统信息** - 用户询问电脑状态
   - "磁盘空间还剩多少" → 调用 get_system_info

## 规则

- 自动识别用户意图，不需要用户说特定关键词
- 自动推断类别（餐饮、交通、购物等）
- 如果一句话包含多个意图，分别调用对应工具
- 用简洁自然的中文回复，不要啰嗦
- 日期默认为今天，除非用户明确指定"#,
        )
        .model(model);

    for tool in tools {
        agent_builder = agent_builder.tool(tool);
    }

    let agent = agent_builder.build()?;

    println!("Agent 创建成功");

    let agent: Arc<dyn adk_rust::Agent> = Arc::new(agent);
    let port: u16 = std::env::var("AGENT_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8081);
    println!("启动 HTTP 服务，端口 {port}（POST /api/chat）");
    server::serve(agent, port).await?;

    Ok(())
}
