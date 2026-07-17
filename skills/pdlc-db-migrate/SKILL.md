---
name: pdlc-db-migrate
description: 数据库迁移管理
argument-hint: <迁移描述 | 版本号>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces:
  - backend/migrations/**
requires: []
next_step: null
terminal_state: null
---

# 数据库迁移管理

<!-- @include templates/prompts/iron-law.md -->

根据 db-design 文档管理数据库迁移脚本，支持生成、执行、回滚和状态查看。

## 子命令解析

从 `$ARGUMENTS` 中解析子命令和参数：

| 子命令 | 格式 | 说明 |
|--------|------|------|
| `generate <描述>` | 根据 db-design 文档生成版本化迁移脚本（up + down） |
| `status` | 查看迁移状态，列出已执行/待执行的迁移 |
| `up` | 执行所有待执行的迁移 |
| `down [N]` | 回滚最近 N 个迁移（默认 1） |
| `diff <功能名>` | 对比 db-design 文档与现有迁移脚本，生成增量迁移 |

如果未提供子命令或子命令无法识别，输出以上帮助信息后停止。

---

## PDLC 前置检查（仅 generate 和 diff 子命令）

当子命令为 `generate` 或 `diff` 时执行：

1. 从用户输入中提取功能名称关键词
2. 在 `docs/02_design/database/` 目录下搜索包含该关键词的数据库设计文档
   - 匹配新格式：`F<日期>-<编号>-*<关键词>*-db.md`
   - 匹配旧格式：`YYYYMMDD-*<关键词>*-db.md`
   - 同时检查文件内容中是否包含该关键词
3. **未找到** → 输出以下信息后**立即停止，不继续执行**：
   ```
   ⛔ PDLC 守卫：未找到与「<功能名>」相关的数据库设计文档。
   迁移脚本必须基于已有的数据库设计。请先运行：
   👉 /pdlc-db-design <设计目标>
   ```
4. **找到** → 提取功能ID（如 `F20260326-01`），读取该设计文档内容，继续执行

---

## 迁移文件约定

### 目录结构

- 微服务项目：`backend/services/<service>/migrations/`
- 单服务项目：`migrations/`
- 自动检测：如果存在 `backend/services/` 目录，按微服务项目处理；否则按单服务项目处理

### 文件命名

- UP 脚本：`V<版本号>__<描述>.sql`
- DOWN 脚本（回滚）：`R<版本号>__<描述>.sql`
- 版本号格式：`YYYYMMDD_HHMMSS`（如 `20260402_143052`）

### 文件头部注释

每个迁移文件必须包含以下头部注释：

```sql
-- ==============================================
-- 迁移脚本: V20260402_143052__create_users_table.sql
-- 功能ID: F20260402-01
-- 描述: 创建用户表
-- 作者: <从 git config 获取>
-- 日期: 2026-04-02
-- ==============================================
```

---

## 子命令执行流程

### generate <描述>

1. 执行前置检查，读取 db-design 文档
2. 读取 `.claude/templates/pdlc/db-migrate-template.md` 模板
3. 生成版本号：使用当前时间戳 `YYYYMMDD_HHMMSS`
4. 从 db-design 文档中提取 DDL 脚本和回滚脚本
5. 生成 UP 迁移文件：`V<版本号>__<描述>.sql`
   - 包含头部注释
   - 包含 CREATE TABLE / ALTER TABLE / INSERT 等语句
   - 每条语句末尾添加分号
6. 生成 DOWN 迁移文件：`R<版本号>__<描述>.sql`
   - 包含头部注释
   - 包含对应的回滚操作（DROP TABLE / ALTER TABLE DROP COLUMN 等）
   - 操作顺序与 UP 相反
7. 更新迁移历史记录文件 `migrations/migration_history.md`
8. 输出生成结果摘要

### status

1. 查找迁移目录下所有 `V*.sql` 文件
2. 读取 `migrations/migration_history.md`（如不存在则提示无迁移记录）
3. 输出迁移状态表格：

   ```
   📋 迁移状态

   | 版本号 | 描述 | 功能ID | 状态 | 执行时间 |
   |--------|------|--------|------|----------|
   | 20260402_143052 | 创建用户表 | F20260402-01 | ✅ 已执行 | 2026-04-02 14:35 |
   | 20260402_150000 | 添加订单表 | F20260402-02 | ⏳ 待执行 | - |

   已执行: 1 | 待执行: 1 | 总计: 2
   ```

### up

1. 读取 `migrations/migration_history.md` 确定已执行的迁移
2. 扫描迁移目录，找出所有待执行的 `V*.sql` 文件
3. 按版本号升序排列
4. 逐个输出待执行的 SQL 内容，并提示用户确认
5. 用户确认后，更新 `migrations/migration_history.md` 中的状态为「已执行」
6. 输出执行结果摘要

> **注意**：本命令不直接连接数据库执行 SQL。它展示待执行的脚本内容，由用户在数据库客户端中手动执行，然后更新迁移历史记录。

### down [N]

1. 读取 `migrations/migration_history.md` 确定已执行的迁移
2. 取最近 N 个已执行的迁移（默认 N=1）
3. 按版本号降序排列
4. 找到对应的 `R*.sql` 回滚文件
5. 逐个输出回滚 SQL 内容，并提示用户确认
6. 用户确认后，更新 `migrations/migration_history.md` 中的状态为「已回滚」
7. 输出回滚结果摘要

> **注意**：与 `up` 相同，本命令不直接执行 SQL，由用户手动执行后更新记录。

### diff <功能名>

1. 执行前置检查，读取 db-design 文档
2. 扫描迁移目录下已有的 `V*.sql` 文件，提取已定义的表结构
3. 对比 db-design 文档中的表结构与已有迁移脚本
4. 识别差异：
   - 新增的表 → 生成 CREATE TABLE
   - 新增的字段 → 生成 ALTER TABLE ADD COLUMN
   - 修改的字段 → 生成 ALTER TABLE MODIFY COLUMN
   - 新增的索引 → 生成 CREATE INDEX
   - 删除的索引 → 生成 DROP INDEX
5. 生成增量迁移的 UP 和 DOWN 文件
6. 更新迁移历史记录
7. 输出差异摘要

---

## 迁移历史记录

在迁移目录下维护 `migration_history.md` 文件：

```markdown
# 迁移历史

| 版本号 | 描述 | 功能ID | 执行时间 | 状态 |
|--------|------|--------|----------|------|
| 20260402_143052 | 创建用户表 | F20260402-01 | 2026-04-02 14:35 | 已执行 |
| 20260402_150000 | 添加订单表 | F20260402-02 | - | 待执行 |
```

状态值：`待执行` | `已执行` | `已回滚`

---

## 要求

<!-- @include templates/prompts/output-language.md -->
- SQL 关键字使用大写（CREATE TABLE、ALTER TABLE 等）
- 每个迁移文件只包含一个功能的变更，保持原子性
- 回滚脚本必须能完全撤销对应的 UP 脚本
- 生成的 SQL 遵循 db-design 文档中的字段命名和类型约定
- 版本号严格递增，不允许插入历史版本

迁移操作: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 数据库迁移脚本 完成
📦 产出：backend/migrations/V<版本号>__<描述>.sql
👉 下一步：（本次流程结束，无后续）
```
