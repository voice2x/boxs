# 快捷记录

> **一句话搞定生活记录 — AI 语音是入口，不是功能。**

用户说一句话 → AI 自动识别意图 → 分类处理 → 完成。

```
"午饭花了 35 块"          → 记账：餐饮 ¥35
"今天跑了 5 公里"          → 习惯打卡：运动 ✓
"周五下午三点跟老王开会"    → 备忘：周五 15:00 会议
"昨天打车花了 28，奶茶 15"  → 批量记账：交通¥28 + 餐饮¥15
```

## 技术栈

| 层 | 技术 |
|---|---|
| **iOS** | Swift + SwiftUI + GRDB.swift + AVFoundation + Starscream |
| **Android (P1)** | Kotlin + Jetpack Compose + Room + OkHttp |
| **后端** | Rust + Axum + sqlx + PostgreSQL |
| **NLU** | 规则引擎（客户端原生，处理 ~70% 请求）+ LLM（后端代理） |
| **STT** | Apple Speech (iOS) / 讯飞 WebSocket (降级) |

## 架构概览

```
iOS App ─────────┐
                  ├── HTTPS / WSS ──→ Rust Backend ──→ PostgreSQL
Android App ─────┘                    ├─ LLM API (OpenAI/智谱)
                                      └─ 讯飞 STT (WebSocket 透传)
```

- **本地优先**：所有数据先写本地 SQLite，网络恢复后同步到 PostgreSQL
- **离线可用**：规则引擎 + 本地存储保证无网络时基本功能正常
- **双层 NLU**：简单输入走规则引擎（<10ms，免费），复杂输入走 LLM（~200ms）

## 文档索引

### 产品设计（`specs/`）

| 文档 | 内容 |
|------|------|
| [01-product-overview.md](specs/01-product-overview.md) | 产品定位、竞品分析、差异化策略 |
| [02-features.md](specs/02-features.md) | 功能模块设计（MVP + 后续迭代） |
| [14-ui-theme.md](specs/14-ui-theme.md) | UI 主题、色彩体系、自定义组件、页面布局 |

### 技术架构（`specs/`）

| 文档 | 内容 |
|------|------|
| [03-architecture.md](specs/03-architecture.md) | 整体架构、数据库 Schema、同步策略 |
| [12-rust-backend.md](specs/12-rust-backend.md) | Rust 后端完整实现（认证、LLM 代理、STT、CRUD） |

### NLU 设计（`specs/`）

| 文档 | 内容 |
|------|------|
| [04-nlu-design.md](specs/04-nlu-design.md) | NLU 处理管线、意图分类体系、降级策略 |
| [05-nlu-prompts.md](specs/05-nlu-prompts.md) | LLM Prompt 工程（分类、查询、纠错） |
| [06-rule-engine.md](specs/06-rule-engine.md) | 规则引擎、分句切割、多意图处理 |
| [07-confidence-and-routing.md](specs/07-confidence-and-routing.md) | 置信度打分模型、路由决策 |

### 开发计划（`specs/`）

| 文档 | 内容 |
|------|------|
| [08-development-plan.md](specs/08-development-plan.md) | 开发阶段、成本估算、变现模式 |

### 实施计划（`docs/superpowers/`）

| 文档 | 内容 |
|------|------|
| [boxs-master-plan.md](docs/superpowers/plans/2026-06-11-boxs-master-plan.md) | 项目总体规划、子系统拆分 |
| [p0-prototype.md](docs/superpowers/plans/2026-06-11-p0-prototype.md) | P0 iOS MVP 逐步实施计划（20 个 Task） |
| [native-architecture-design.md](docs/superpowers/specs/2026-06-11-native-architecture-design.md) | 原生双端架构设计、iOS/Android 技术映射 |

## 快速开始

### 后端

```bash
cd boxs-server
cp .env.example .env          # 填入数据库和 LLM API 配置
docker compose up -d postgres  # 启动 PostgreSQL
cargo run                      # 启动服务（自动运行数据库迁移）
```

### iOS App

```bash
# 在 Xcode 中打开 Boxs/ 项目
# 配置 SPM 依赖：GRDB.swift、Starscream
# 运行到模拟器或真机
```

## 开发阶段

| 阶段 | 周期 | 交付 |
|------|------|------|
| **P0** | 3 周 | Rust 后端 + iOS MVP（语音 → NLU → 记账/打卡/备忘） |
| **P1** | 2 周 | Android 移植 + 统计图表 + 推送通知 |
| **P2** | 1 周 | App Store + Google Play 上架 |
| **P3** | 持续 | AI 查询、微信小程序、Widget、云同步 |
