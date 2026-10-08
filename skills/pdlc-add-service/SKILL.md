---
name: pdlc-add-service
description: 添加新的微服务
argument-hint: <服务名>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces:
  # 跟随项目既有布局（正文「先探测项目布局」）；空项目才默认 backend/services/<service-name>/
  - <服务目录 · 项目既有布局>/<service-name>/**
requires: []
next_step: null
terminal_state: null
---

# 添加新的微服务

<!-- @include templates/prompts/iron-law.md（已内联于下方，无需另读） -->
⛔ **IRON LAW · 不可违反的硬门禁**

以下规则为**不可协商**的执行约束：

1. **文件必须落盘**：所有带编号（功能ID / 缺陷ID）的文档，必须作为实际文件写入磁盘，不可仅在对话中输出。
2. **阶段必须落章**：每个阶段完成后必须在状态机 `docs/.pdlc-state/<feature-id>.json` 追加 history，不可跳过。
3. **测试必须存在**：进入 `/pdlc-implement` 前，对应测试必须存在且处于红灯状态。违反则中止。
4. **自检必须执行**：段二自检为强制步骤，不得以"已经很好了"为由跳过。
5. **防循环**：段三修复为单次，不递归。无法自动修复的问题记录到报告，继续往下走。
6. **状态必推进**：成功执行某 phase 后 `current_stage` 必须变更。收尾时若发现 `current_stage` 未推进，视为失败并报错，**不得静默返回**（防止外层循环拿滞后的状态空转烧额度）。唯一例外：命中人工点主动 block 时，`current_stage` 保持不变但必须写 `last_phase_result.ok=false` + `blocked_reason`。

**违反任一条 = 立即中止当前命令，输出违规详情，等待人工介入。**
<!-- @include-end templates/prompts/iron-law.md -->

在项目中添加一个新的后端微服务，并生成完整的目录结构和初始文档。

<!-- @include templates/prompts/layout-detect.md（已内联于下方，无需另读） -->
## 先探测项目布局（不要套用写死的目录）

下文出现的 `backend/services/`、`frontend/web/` 等路径只是**空项目时的默认布局**。动手创建或扫描目录之前，先看项目实际长什么样：

1. **monorepo 标志**：`pnpm-workspace.yaml`、`turbo.json`、`nx.json`、`lerna.json`、`package.json` 的 `workspaces`、
   `go.work`、`Cargo.toml` 的 `[workspace]`、`settings.gradle(.kts)` 的 `include` → 按其中声明的目录（如 `apps/`、`packages/`、`services/`、`crates/`）理解布局
2. **已有单元的位置**：在 `backend/services/`、`services/`、`apps/`、`packages/`、`cmd/`、`crates/` 下找已存在的服务 / 应用，新单元放在**同级**，命名与目录结构照着已有的来
3. **单体与全栈框架**：只有一个 `src/`，或是框架默认结构（`manage.py` + 各 app、Rails 的 `app/`、Next.js 的 `app/` / `pages/`、Spring Boot 单模块）→ 按框架约定放，**不要**新建 `services/` 一类平行目录
4. **空项目或判断不了** → 才用下文的默认布局；执行前把将要创建的路径列给用户确认（`--autonomous` 下记入 `auto_decisions[]`）

把探测结论写进本次报告：**布局类型 + 依据的文件 + 新内容的落点**。判断错了的代价是在用户仓库里长出一套平行目录，比多问一句贵得多。
<!-- @include-end templates/prompts/layout-detect.md -->

## 工作流程
1. 项目有 `Makefile` 且含创建服务的 target 时用它；否则直接在 `backend/services/` 下创建服务目录
2. 根据技术栈生成标准目录结构
3. 创建服务的 README.md、CHANGELOG.md
4. 在 `backend/services/<服务名>/docs/` 下创建 api-design.md 初始文档
5. 更新项目 CLAUDE.md 中的服务列表（如需要）

## 支持的技术栈
- java/spring: Maven + Spring Boot 标准结构
- go: Go 标准项目布局（cmd/internal/pkg）
- python: FastAPI/Flask 项目结构
- node: Express/NestJS 项目结构

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
- 服务名使用小写英文 + 连字符（如 user-service）
- 创建完成后提示用户下一步编写 API 设计文档

$ARGUMENTS

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
✅ 新微服务 完成
📦 产出：backend/services/<service-name>/
👉 下一步：（本次流程结束，无后续）
```
