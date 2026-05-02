---
name: pdlc
description: Use when the user wants to build a feature, fix a bug, design a system, write tests, review code, cut a release, deploy, or run a retrospective on a software project. Enforces a Product Development Life Cycle (PRD → design → TDD → implement → review → ship → deploy → retro) via 31 standardized commands with hard contracts — artifacts persisted to docs/, per-feature state machine, tests-before-code, mandatory self-check at each stage, single-shot auto-repair. Activates on phrases like "build login", "fix the pagination crash", "ship the next version", "do a code review", or any mention of PRD / TDD / E2E / lint / security / refactor / changelog.
---

# PDLC Skill — 产品开发生命周期工作流

本 skill 提供一套覆盖产品开发全生命周期的标准化工作流。所有命令体、提示片段、文档模板都放在 `references/` 下；本文件是入口索引——**先读这里决定调用哪个命令规范，再按需打开对应文件**。

## 调用方式

用户请求一个工程动作（如「帮我做用户登录功能」「修一下分页 bug」「准备发版」），按下表查找匹配的命令规范，从 `references/commands/<命令名>.md` 读取完整工作流并按步骤执行。

每个命令文件包含：YAML frontmatter（`layer`、`stage`、`produces`、`requires`、`next_step` 等元数据）+ Markdown 工作流正文 + `<!-- @include templates/prompts/xxx.md -->` 占位符。执行时需把 `@include` 引用的 `references/templates/prompts/<name>.md` 内联展开。

## 命令清单（v2 三层结构）

### Layer 1 · 入口（3 个）
适合从一句话需求/Bug 描述自动跑完全流程。

| 命令 | 文件 | 用途 |
|---|---|---|
| feature | `references/commands/feature.md` | 全自动新功能开发（PRD → 设计 → TDD → 实现 → 评审 → 发布） |
| fix | `references/commands/fix.md` | 全自动 Bug 修复（定位 → 复现 → 修复 → 测试 → 文档） |
| status | `references/commands/status.md` | 项目 PDLC 状态总览 |

### Layer 2 · 阶段（11 个）
单阶段精细控制。

| 命令 | 文件 | 用途 |
|---|---|---|
| prd | `references/commands/prd.md` | 创建 PRD 文档 |
| design | `references/commands/design.md` | 技术设计 |
| tdd | `references/commands/tdd.md` | 测试先行（TDD） |
| implement | `references/commands/implement.md` | 按设计实现代码 |
| review | `references/commands/review.md` | 代码 + 文档评审 |
| e2e | `references/commands/e2e.md` | 端到端测试 |
| refactor | `references/commands/refactor.md` | 代码重构 |
| ship | `references/commands/ship.md` | 发布工作流（测试 → VERSION → CHANGELOG → tag → CI） |
| deploy | `references/commands/deploy.md` | 部署文档 |
| retro | `references/commands/retro.md` | 迭代复盘 |
| task | `references/commands/task.md` | 阶段内任务跟踪 |

### Layer 3 · 工具（17 个）
专项叠加，按需调用。

**🎨 设计（4）**：`ui-design`, `ui-design-pro`, `db-design`, `arch`
**🔍 质量（3）**：`lint`, `perf`, `security`
**🔧 工程（7）**：`code-gen`, `add-service`, `add-app`, `api-mock`, `db-migrate`, `i18n`, `changelog`
**🏗️ 项目生命周期（3）**：`bootstrap`, `adopt`, `onboard`

每个文件路径：`references/commands/<名称>.md`。

## 共享提示片段（@include 目标）

`references/templates/prompts/` 下的片段会被命令体通过 `<!-- @include templates/prompts/<name>.md -->` 引用：

- `iron-law.md` — 铁律：必须落盘、必须更新状态机、必须有测试、必须自检、修复仅一次
- `loop-prevention.md` — 防止评审/修复死循环
- `feature-id.md` / `defect-id.md` — 功能/缺陷 ID 分配规则
- `state-update.md` — 状态机更新规范
- `pdlc-trace.md` — 文档追溯头格式
- `handoff.md` — 阶段交接报告格式
- `self-audit.md` — 自审清单

## 文档模板

`references/templates/*.md` 是用户文档模板（PRD、API 设计、数据库设计、架构设计、迁移脚本、测试计划、部署手册、变更日志、接入报告）。命令体中"使用 templates/xxx-template.md"指的是这些文件。

## 目标项目契约

执行命令时读写以下路径：

- `docs/01_requirements/prd/`
- `docs/02_design/{api,database,architecture}/`
- `docs/04_testing/{unit-tests,e2e-tests}/`
- `docs/05_deployment/`
- `docs/06_tasks/`
- `docs/07_reviews/{doc,code}/`
- `docs/.pdlc-state/<feature-id>.json` — 每个功能一个状态机文件，ID 形如 `F20260419-01`

## 执行铁律（来自 iron-law.md）

1. **必须落盘**：所有产出必须作为真实文件写入磁盘，不可仅在对话中显示
2. **必须更新状态机**：每个阶段完成后写入 `docs/.pdlc-state/<feature-id>.json`
3. **必须有测试**：代码实现前测试必须已存在且失败（TDD 红灯）
4. **必须自检**：每阶段结束前运行 self-check
5. **修复仅一次**：自动修复循环最多一轮，失败则记录为待人工处理

## 详细规范

完整架构、frontmatter schema、目录契约见 `docs/reference.md`；日常用法见 `docs/usage-guide.md`。
