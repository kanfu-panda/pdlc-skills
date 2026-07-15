---
name: pdlc-implement
description: 按设计文档和已有测试用例实现代码（带前置守卫、自检、handoff）
argument-hint: <功能描述或功能ID>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: impl
produces:
  - backend/services/*/src/
  - frontend/*/src/
requires:
  - docs/02_design/
  - backend/services/*/src/test/
  - frontend/*/src/__tests__/
next_step: pdlc-review
terminal_state: impl_done
recommended_model: sonnet
recommended_effort: medium
---

# 按设计文档实现代码

严格按照设计文档和已有的测试用例实现功能代码。

<!-- @include templates/prompts/iron-law.md -->
<!-- @include templates/prompts/noninteractive.md -->

## PDLC 前置守卫（不可跳过）

1. 从用户输入提取功能名称关键词
2. 在以下位置搜索与该功能相关的**测试代码**：
   - 后端: `backend/services/*/src/test/`、`backend/services/*/tests/`
   - 前端: `frontend/*/src/__tests__/`、`frontend/*/*/src/__tests__/`
3. **未找到测试代码** → 输出以下后立即中止：
   ```
   ⛔ PDLC 守卫：未找到与「<功能名>」相关的测试代码。
   实现代码前必须先编写测试（TDD）。请先运行：
   👉 /pdlc-tdd <功能描述>
   ```
4. **找到测试** → 运行测试，确认**红灯**（失败）。若已全绿：
   - 交互模式：提示"测试已全部通过，可能代码已实现，请确认是否需要继续。"
   - `--autonomous` 模式：视为流程性确认，默认**跳过实现直接收尾**（写 `auto_decisions[]` 留痕），`current_stage` 推进为 `impl`、`next_step=pdlc-review`、`last_phase_result.advanced_to=review`（下一阶段短名，非命令名）
5. 提取功能ID（从设计文档或 PRD），继续
6. **任务状态关联**（如 `docs/06_tasks/` 存在任务文件）：
   - 匹配含功能ID的任务文件
   - ⬜ 未开始 / 🔄 进行中的任务，标为 🔄，追加 `<!-- 开始时间: <今日日期> -->`

## 段一：实现代码

1. **阅读设计文档**：`docs/02_design/` 对应子目录下的文档，逐字理解
2. **阅读测试用例**：对应服务/应用下的测试代码，理解每条意图
3. **阅读编码规范**：`docs/00_standards/coding/`（未命中 → 提示 `consider /pdlc-standard add coding/<topic>`）
4. **最少量实现**：使所有测试通过的最小代码
5. **运行测试**：确认绿灯
6. **重构优化**：测试通过前提下优化代码结构
7. **更新服务 CHANGELOG**
8. **任务完结**：匹配任务由 🔄 改 ✅，追加 `<!-- 完成时间: <今日日期> -->`

## 段二：自检（强制）

<!-- @include templates/prompts/self-audit.md -->

### 实现自检清单（必须全部检查）

1. **设计偏离检查**：重读设计文档，确认没有遗漏接口或功能点
   - 遗漏 → 补充实现并确认测试通过
   - 偏离 → 修正代码或补充设计说明
2. **编码规范快检**：运行项目 lint 工具
   - 可自动修复 → 直接修复
   - 修复后重跑测试确认不破坏功能
   - lint fix 导致失败 → 回滚并记录人工处理
3. **覆盖率验证**：单元测试覆盖率 ≥ 80%
   - 不达标 → 补测试用例并确认通过

## 段三：修复（单次，不递归）

<!-- @include templates/prompts/loop-prevention.md -->

## 段四：更新状态机 + 交接

<!-- @include templates/prompts/state-update.md -->

**本阶段状态机更新**：
- `current_stage`: `impl`
- `next_step`: `pdlc-review`
- **写 `last_phase_result`**：`checks.tests_pass` / `coverage_pass` / `lint_clean` 取自真跑 `docs/00_standards/test-commands.yml` 的 `unit` / `coverage` / `lint` 命令退出码（该文件不存在则回退项目既有约定，并在报告中提示 `consider 建立 docs/00_standards/test-commands.yml`）。**不得用自检结果冒充 checks**。

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 实现完成，自检通过
  - 设计一致性：<✅/部分>
  - lint 检查：<✅/X 项已自动修复/X 项待人工>
  - 测试覆盖率：<XX>%
📦 状态快照：docs/.pdlc-state/<feature-id>.json
👉 下一步：/pdlc-review <feature-id>
```

---

**实现目标**: $ARGUMENTS
