---
name: pdlc-db-design
description: 数据库设计
argument-hint: <功能ID | 数据模型描述>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: design
produces:
  - docs/02_design/database/**
requires: []
next_step: null
terminal_state: null
---

# 数据库设计

<!-- @include templates/prompts/iron-law.md -->

根据需求和 API 设计文档，创建数据库设计方案。

## PDLC 前置检查（必须执行，不可跳过）

1. 从用户输入中提取功能名称关键词
2. 在 `docs/01_requirements/prd/` 目录下搜索包含该关键词的 PRD 文档
   - 匹配新格式：`F<日期>-<NN>-*<关键词>*-prd.md`
   - 匹配旧格式：`YYYYMMDD-*<关键词>*-prd.md`
   - 同时检查文件内容中是否包含该关键词
3. **未找到** → 输出以下信息后**立即停止，不继续执行**：
   ```
   ⛔ PDLC 守卫：未找到与「<功能名>」相关的 PRD 文档。
   数据库设计必须基于已有的 PRD。请先运行：
   👉 /pdlc-prd <需求描述>
   ```
4. **找到** → 提取功能ID（如 `F20260326-01`），读取该 PRD 内容，继续执行

## 工作流程

1. **阅读需求**: 阅读找到的 PRD 文档
2. **阅读 API 设计**: 阅读 `docs/02_design/api/` 下同功能ID的 API 设计文档（如有）
3. **梳理数据模型**: 识别实体、属性、关系
4. **ER 图**: 用文本方式描绘实体关系图
5. **表结构定义**: 逐表定义字段、类型、约束
6. **索引设计**: 根据查询场景设计索引
7. **输出设计文档**: 在 `docs/02_design/database/` 下创建数据库设计文档

## 文档内容

- **文件名格式**: `<功能ID>-<功能名>-db.md`（如 `F20260326-01-user-auth-db.md`）
  - 若 PRD 为旧格式无功能ID，则使用旧格式 `YYYYMMDD-<模块名>-db.md`
- **文档顶部必须包含 PDLC 追溯头**：
  ```
  <!-- PDLC-TRACE -->
  <!-- 功能ID: F20260326-01 -->
  <!-- 功能名称: user-auth -->
  <!-- 阶段: 设计 -->
  <!-- 前置文档: docs/01_requirements/prd/F20260326-01-user-auth-prd.md -->
  ```

### ER 图格式
```
[用户] 1──N [订单] N──N [商品]
  │                       │
  └───N [地址]    [库存] 1─┘
```

### 表结构格式
| 字段 | 类型 | 可空 | 默认值 | 索引 | 描述 |
|------|------|------|--------|------|------|

### 必须包含
- 公共字段约定（id、created_at、updated_at、deleted_at 等）
- 主键策略（自增/UUID/雪花ID）
- 软删除策略
- 分表分库策略（如数据量大）
- 数据迁移方案（DDL 变更脚本）

## 要求

<!-- @include templates/prompts/output-language.md -->
- 字段命名使用 snake_case
- 枚举值必须有中文说明
- 考虑数据量增长后的性能影响

设计目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 数据库设计文档 完成
📦 产出：docs/02_design/database/<功能ID>-<功能名>-db.md
👉 下一步：（本次流程结束，无后续）
```
