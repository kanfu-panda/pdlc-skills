---
name: pdlc-design
description: 创建技术设计文档（自动生成 + 自检 + handoff）
argument-hint: <功能ID | 功能描述>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: design
produces:
  - docs/02_design/<subsystem>/<feature-id>-design.md
requires:
  - docs/01_requirements/prd/
next_step: pdlc-tdd
terminal_state: design_done
---

# 创建设计文档

<!-- @include templates/prompts/iron-law.md -->

根据已有的需求文档，在 `docs/02_design/` 对应子目录下创建技术设计文档。

## 输入解析

从 `$ARGUMENTS` 中判断输入类型：
- **文件路径**（以 `/`、`./` 开头，或以 `.md`、`.txt`、`.pdf` 结尾，或实际存在的文件）：直接读取该文件作为需求来源，跳过 PRD 搜索
- **功能名关键词**（默认）：按下方守卫检查搜索 PRD

## PDLC 前置检查（必须执行，不可跳过）

1. 若输入为文件路径，直接读取文件内容作为需求，提取功能名和功能ID（如有），跳到步骤 4
2. 从用户输入中提取功能名称关键词
3. 在 `docs/01_requirements/prd/` 目录下搜索包含该关键词的 PRD 文档
   - 匹配新格式：`F<日期>-<NN>-*<关键词>*-prd.md`
   - 匹配旧格式：`YYYYMMDD-*<关键词>*-prd.md`
   - 同时检查文件内容中是否包含该关键词
3. **未找到** → 输出以下信息后**立即停止，不继续执行**：
   ```
   ⛔ PDLC 守卫：未找到与「<功能名>」相关的 PRD 文档。
   设计文档必须基于已有的 PRD。请先运行：
   👉 /pdlc-prd <需求描述>
   ```
4. **找到** → 提取功能ID（如 `F20260326-01`），读取该 PRD 内容，继续执行

## 输出位置

- API 设计 → `docs/02_design/api/`
- 架构设计 → `docs/02_design/architecture/`
- 数据库设计 → `docs/02_design/database/`

## 要求

1. 先阅读找到的 PRD 文档，全面理解需求
2. 参考 `templates/api-design-template.md` 获取 API 设计模板格式
3. 参考 `docs/00_standards/` 目录了解项目规范（未命中 → 提示 `consider /pdlc-standard add <category>/<topic>`）
4. **文件名格式**: `<功能ID>-<功能名>-<类型>.md`（如 `F20260326-01-user-auth-api.md`），类型可以是 api / arch / db
   - 若 PRD 为旧格式无功能ID，则使用旧格式 `YYYYMMDD-<功能名>-<类型>.md`
5. **文档顶部必须包含 PDLC 追溯头**：
   ```
   <!-- PDLC-TRACE -->
   <!-- 功能ID: F20260326-01 -->
   <!-- 功能名称: user-auth -->
   <!-- 阶段: 设计 -->
   <!-- 前置文档: docs/01_requirements/prd/F20260326-01-user-auth-prd.md -->
   ```
<!-- @include templates/prompts/output-language.md -->
7. 必须包含：概述、接口/架构/表结构定义、错误码/异常处理、数据模型
8. API 设计需遵循 RESTful 规范，统一响应格式 `{ code, message, data }`
9. **设计文档自审与自动修复**（每份设计文档创建后立即执行，不可跳过）：
   - 重新阅读刚创建的设计文档，对照 PRD 逐项检查以下质量门禁：

   **PRD 一致性检查**：
   - [ ] PRD 中每条 P0/P1 功能是否都有对应的设计覆盖（接口/表结构/架构组件）
   - [ ] 接口的入参/出参是否与 PRD 描述的功能行为一致
   - [ ] 错误码是否覆盖了 PRD 中列出的异常场景

   **API 设计检查**（如有 API 文档）：
   - [ ] 接口 URL 命名是否遵循 RESTful 规范（名词复数、层级清晰）
   - [ ] 请求/响应结构是否完整（无缺失字段）
   - [ ] 统一响应格式 `{ code, message, data }` 是否一致执行
   - [ ] 分页接口是否有 page/pageSize/total 参数
   - [ ] 鉴权方式是否明确说明

   **数据库设计检查**（如有 DB 文档）：
   - [ ] 每张表是否有主键定义
   - [ ] 外键关系是否与 ER 图一致
   - [ ] 常用查询字段是否有索引设计
   - [ ] 是否有 `created_at`、`updated_at` 等审计字段
   - [ ] 迁移 DDL 是否完整可执行

   **跨文档一致性检查**（如同时有 API + DB 文档）：
   - [ ] API 响应字段是否与数据库字段对应（字段名、类型）
   - [ ] API 的查询/筛选参数是否有对应的数据库索引支撑

   **自动修复**：
   - PRD 功能遗漏：自动补充对应的接口/表设计
   - 缺失的错误码：根据接口行为自动补充常见错误码（400/401/403/404/409/500）
   - 缺失的索引：根据查询模式自动补充索引设计
   - 缺失的审计字段：自动添加 `created_at`、`updated_at`
   - 缺失的分页参数：自动补充列表接口的分页设计
   - 修复后在文档末尾追加审查记录：
     ```
     ## 自审记录
     - 审查时间：<ISO 8601>
     - 对照 PRD：<PRD 文件路径>
     - 发现问题：X 项
     - 自动修复：X 项
     - 修复明细：
       - [已修复] <问题描述>
     ```

10. 创建完成后，提示用户下一步是编写测试用例（`/pdlc-tdd <功能名>`）

设计目标: $ARGUMENTS

<!-- @include templates/prompts/state-update.md -->
<!-- @include templates/prompts/handoff.md -->
