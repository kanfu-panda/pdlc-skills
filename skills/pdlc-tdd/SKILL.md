---
name: pdlc-tdd
description: TDD 测试先行（按设计文档生成失败的测试用例）
argument-hint: <功能ID | 功能描述>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: tdd
produces:
  - backend/services/*/src/test/**
  - frontend/*/src/__tests__/**
requires:
  - docs/02_design/
next_step: pdlc-implement
terminal_state: tdd_done
---

# TDD 测试先行

<!-- @include templates/prompts/iron-law.md -->

根据设计文档，先编写测试用例，再实现代码。严格遵循 TDD 工作流。

## PDLC 前置检查（必须执行，不可跳过）

1. 从用户输入中提取功能名称关键词
2. 在 `docs/02_design/` 的子目录（api/、architecture/、database/、ui-ux/）下搜索包含该关键词的设计文档
   - 匹配新格式：`F<日期>-<NN>-*<关键词>*-<类型>.md`
   - 匹配旧格式：`YYYYMMDD-*<关键词>*-<类型>.md`
   - 同时检查文件内容中是否包含该关键词
3. **未找到任何设计文档** → 输出以下信息后**立即停止，不继续执行**：
   ```
   ⛔ PDLC 守卫：未找到与「<功能名>」相关的设计文档（API/架构/数据库/UI 任一）。
   测试用例必须基于已有的设计文档。请先运行：
   👉 /pdlc-design <设计目标>
   ```
4. **找到** → 提取功能ID（如 `F20260326-01`），读取设计文档内容，继续执行

## 工作流程

1. **阅读设计文档**: 阅读找到的设计文档，全面理解接口/架构/数据模型
2. **阅读编码规范**: 阅读 `docs/00_standards/coding/` 目录了解编码规范（未命中 → 提示 `consider /pdlc-standard add coding/<topic>`）
3. **编写测试计划**: 在 `docs/04_testing/unit-tests/` 下创建测试计划文档
   - **使用模板**: `templates/test-plan-template.md`
   - **文件名格式**: `<功能ID>-<功能名>-test-plan.md`（如 `F20260326-01-user-auth-test-plan.md`）
   - **文档顶部必须包含 PDLC 追溯头**：
     ```
     <!-- PDLC-TRACE -->
     <!-- 功能ID: F20260326-01 -->
     <!-- 功能名称: user-auth -->
     <!-- 阶段: 测试 -->
     <!-- 前置文档: docs/02_design/api/F20260326-01-user-auth-api.md -->
     ```
4. **编写测试代码**: 在对应服务/应用的测试目录下编写测试用例
   - 后端: `backend/services/<服务名>/src/test/` 或 `backend/services/<服务名>/tests/`
   - 前端: `frontend/<分类>/<应用名>/src/__tests__/`
5. **测试计划自审与自动修复**（编写完成后、运行前执行，不可跳过）：
   - 重新阅读测试计划和测试代码，对照设计文档和 PRD 逐项检查以下质量门禁：

   **验收标准覆盖度**：
   - [ ] PRD 中每条验收标准是否至少有一个对应的测试用例
   - [ ] 设计文档中每个接口是否至少有正常流程 + 异常流程的测试

   **场景完备性**：
   - [ ] 正常流程：核心业务路径是否全部覆盖
   - [ ] 边界条件：空值/null、空字符串、最大值/最小值、零值、超长输入
   - [ ] 异常场景：无权限、资源不存在（404）、重复操作（409）、参数校验失败（400）
   - [ ] 并发场景：是否考虑了同时操作的冲突（如适用）
   - [ ] 幂等性：重复提交同一请求是否有对应测试（如适用）

   **测试质量**：
   - [ ] 测试方法命名是否清晰描述场景（如 `should_return_404_when_user_not_found`）
   - [ ] 每个测试是否只验证一个行为（单一断言原则）
   - [ ] 测试数据是否有意义（非 `test1`、`abc123` 等无意义数据）

   **自动修复**：
   - 缺失的验收标准测试：自动补充对应的测试用例骨架
   - 缺失的边界条件测试：自动添加空值、超长输入、类型错误等测试
   - 缺失的异常场景测试：根据 API 错误码自动补充 401/403/404/409 等场景测试
   - 命名不规范的测试方法：自动重命名为描述性命名
   - 修复后在测试计划文档末尾追加审查记录：
     ```
     ## 自审记录
     - 审查时间：<ISO 8601>
     - 对照 PRD 验收标准：X 条，已覆盖：X 条
     - 对照 API 接口：X 个，已覆盖：X 个
     - 发现问题：X 项
     - 自动修复：X 项
     - 修复明细：
       - [已修复] <问题描述>
     ```

6. **确认测试失败**: 运行测试确认全部失败（红灯）
7. **实现代码**: 编写最少量的代码使测试通过
8. **重构**: 在测试通过的前提下优化代码

## 要求

<!-- @include templates/prompts/output-language.md -->
- 测试用例必须覆盖：正常流程、边界条件、异常场景
- 测试方法命名清晰描述测试场景
- 单元测试覆盖率目标 >= 80%

目标功能: $ARGUMENTS

<!-- @include templates/prompts/state-update.md -->
<!-- @include templates/prompts/handoff.md -->
