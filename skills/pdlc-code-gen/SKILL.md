---
name: pdlc-code-gen
description: 在已有服务 / 应用里按设计文档生成模块代码骨架（分层、接口、模型）；加新服务用 /pdlc-add-service
argument-hint: <模板类型 | 目标目录>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces: []
requires: []
next_step: null
terminal_state: null
---

# 代码脚手架生成

<!-- @include templates/prompts/iron-law-tool.md（已内联于下方，无需另读） -->
⛔ **IRON LAW · 不可违反的硬门禁（工具型命令）**

本命令不是主链路上的阶段：**不追加 `history`，不改 `current_stage` / `next_step` / `last_phase_result`**，也不为此分配功能ID。以下规则不可协商：

1. **文件必须落盘**：正文要求创建的文件必须作为实际文件写入磁盘，不可仅在对话中输出（只要求在对话里输出的，照正文办）。
2. **自检必须执行**：产出后按本命令的自检项逐项核对，不得以"已经很好了"为由跳过。
3. **防循环**：修复只做一次，不递归。修不了的问题记进报告，继续往下走。

**违反任一条 = 立即中止当前命令，输出违规详情，等待人工介入。**
<!-- @include-end templates/prompts/iron-law-tool.md -->

根据设计文档快速生成模块代码脚手架（骨架代码）。

## 工作流程
1. **阅读设计文档**: 阅读 `docs/02_design/api/` 和 `docs/02_design/database/` 下的设计文档
2. **确定目标服务**: 确认代码生成到哪个服务或应用
3. **生成代码骨架**: 按技术栈生成对应的代码文件

## 后端生成内容（按分层架构）

### Java/Spring Boot
- Controller（控制器层）: 路由、参数校验、响应封装
- Service（服务层）: 业务逻辑接口和实现
- Repository（数据层）: 数据访问接口
- DTO/VO/Entity: 数据传输对象、视图对象、实体类
- 单元测试骨架

### Go
- Handler（处理器层）: HTTP 路由处理
- Service（服务层）: 业务逻辑
- Repository（仓储层）: 数据访问
- Model（模型层）: 数据结构定义
- 单元测试骨架

### Python/FastAPI
- Router（路由层）: API 路由定义
- Service（服务层）: 业务逻辑
- Repository（仓储层）: 数据访问
- Schema/Model: Pydantic 模型、ORM 模型
- 单元测试骨架

### Node.js
- Controller（控制器层）: 路由处理
- Service（服务层）: 业务逻辑
- Model（模型层）: 数据模型
- Middleware（中间件）: 通用中间件
- 单元测试骨架

## 前端生成内容
- 页面组件骨架
- API 请求服务层
- 类型定义（TypeScript）
- 状态管理模块
- 单元测试骨架

## 要求
<!-- @include templates/prompts/output-language.md（已内联于下方，无需另读） -->
🌐 **Output language for generated artifacts**

All generated artifacts (PRDs, design docs, code comments, review reports,
test plans, deployment manuals, changelog entries, etc.) follow this policy:

1. **Default — match the conversation language exactly**:
   - 用户用中文与 Claude 对话 → 产中文文档、中文代码注释、中文报告
   - User talks to Claude in English → produce English artifacts
   - User talks in another language → produce artifacts in that language
   - **Never silently default to a fixed language regardless of the user's input.**

2. **Explicit override always wins**: when the user specifies a language for
   an artifact (e.g. "write the PRD in English", "用英文写 API 设计文档",
   "output the deploy doc in Japanese"), use that language for that artifact,
   regardless of conversation language.

3. **Mixed-language requirements**: if the user wants some artifacts in one
   language and others in a different language (common: Chinese PRD + English
   API docs for partners), honour each per-artifact instruction.

4. **Uncertain**: if you cannot reliably detect the conversation language,
   ask once before producing the first artifact.

This policy applies to **content** (prose, comments, headings). It does
**not** override technical conventions like English variable names, English
git commit subjects, or English error codes when the project's conventions
require them.
<!-- @include-end templates/prompts/output-language.md -->
- 生成的代码要遵循 `docs/00_standards/coding/` 下的规范（未命中 → 提示 `consider /pdlc-standard add coding/<topic>`）
- 方法体用 `// TODO: 待实现` 占位
- 测试用例用 `// TODO: 补充测试逻辑` 占位
- 生成后提示用户先运行 `/pdlc-tdd` 补充测试

生成目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md（已内联于下方，无需另读） -->
## 段四：交接（Handoff）

命令完成后必须输出以下格式的最终消息：

```
✅ <阶段名> 完成：<主要产出物路径>
📊 自检：<通过数>/<总数> 通过（若有未通过，附要点）
📦 状态快照：docs/.pdlc-state/<feature-id>.json
👉 下一步：/pdlc-<next_step>
   （如果有分叉）或 /pdlc-<alt>（条件：<选择依据>）
```

**规则：**
- 主流程命令（写状态机的命令；下一跳见正文里「本命令的状态机取值」）必须显式输出"下一步"，不可省略
- 工具型命令（Layer 3）可以没有 `next_step`，此时输出 `👉 下一步：（本次流程结束，无后续）`
- 分叉场景必须说明**选择条件**，例如"若需补充测试用例 → `/pdlc-tdd`；若测试已齐 → `/pdlc-review`"
<!-- @include-end templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 代码脚手架 完成
📦 产出：（生成到目标服务/应用目录）
👉 下一步：（本次流程结束，无后续）
```
