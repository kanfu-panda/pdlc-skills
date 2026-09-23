# 数据库迁移脚本模板

> 本模板供 `/pdlc-db-migrate` 命令生成迁移文件时参考。

---

## 1. UP 迁移脚本模板

文件名格式：`V<YYYYMMDD_HHMMSS>__<描述>.sql`

```sql
-- ==============================================
-- 迁移脚本: V<版本号>__<描述>.sql
-- 功能ID: <功能ID>
-- 描述: <变更描述>
-- 作者: <作者>
-- 日期: <YYYY-MM-DD>
-- ==============================================

-- ---------- 1. 新建表 ----------

CREATE TABLE <table_name> (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
    -- 业务字段
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    created_by VARCHAR(64) DEFAULT NULL COMMENT '创建人',
    updated_by VARCHAR(64) DEFAULT NULL COMMENT '更新人',
    is_deleted TINYINT(1) NOT NULL DEFAULT 0 COMMENT '逻辑删除（0=正常，1=删除）',
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='<表注释>';

-- ---------- 2. 修改表结构 ----------

-- 新增字段
ALTER TABLE <table_name>
    ADD COLUMN <column_name> <type> <nullable> <default> COMMENT '<说明>'
    AFTER <existing_column>;

-- 修改字段
ALTER TABLE <table_name>
    MODIFY COLUMN <column_name> <new_type> <nullable> <default> COMMENT '<说明>';

-- ---------- 3. 索引变更 ----------

-- 新增索引
CREATE INDEX idx_<table>_<column> ON <table_name> (<column_name>);
CREATE UNIQUE INDEX uk_<table>_<column> ON <table_name> (<column_name>);

-- ---------- 4. 数据初始化 ----------

INSERT INTO <table_name> (<columns>) VALUES
    (<values>);
```

---

## 2. DOWN 回滚脚本模板

文件名格式：`R<YYYYMMDD_HHMMSS>__<描述>.sql`

```sql
-- ==============================================
-- 回滚脚本: R<版本号>__<描述>.sql
-- 功能ID: <功能ID>
-- 描述: 回滚 - <变更描述>
-- 作者: <作者>
-- 日期: <YYYY-MM-DD>
-- ==============================================

-- ⚠️ 回滚操作顺序与 UP 脚本相反

-- ---------- 1. 删除初始化数据 ----------

DELETE FROM <table_name> WHERE <condition>;

-- ---------- 2. 删除索引 ----------

DROP INDEX idx_<table>_<column> ON <table_name>;

-- ---------- 3. 撤销表结构变更 ----------

-- 删除新增的字段
ALTER TABLE <table_name>
    DROP COLUMN <column_name>;

-- 恢复修改的字段
ALTER TABLE <table_name>
    MODIFY COLUMN <column_name> <original_type> <original_nullable> <original_default> COMMENT '<原说明>';

-- ---------- 4. 删除新建的表 ----------

DROP TABLE IF EXISTS <table_name>;
```

---

## 3. 迁移历史记录模板

文件名：`migration_history.md`，位于迁移目录下。

```markdown
# 迁移历史

> 本文件由 `/pdlc-db-migrate` 命令自动维护，记录所有迁移脚本的执行状态。

| 版本号 | 描述 | 功能ID | 执行时间 | 状态 |
|--------|------|--------|----------|------|
```

状态值说明：
- `待执行` — 迁移脚本已生成，尚未在数据库中执行
- `已执行` — 迁移脚本已在数据库中执行
- `已回滚` — 迁移已被回滚撤销

---

## 4. 编写规范

### 4.1 命名规范

- 版本号使用时间戳格式：`YYYYMMDD_HHMMSS`
- 描述使用 snake_case 英文：`create_users_table`、`add_email_to_users`
- 一个迁移文件只包含一个原子变更

### 4.2 SQL 规范

- SQL 关键字统一大写：`CREATE TABLE`、`ALTER TABLE`、`DROP TABLE`
- 字段名使用 snake_case 小写
- 每条语句以分号结尾
- 重要操作前添加中文注释说明
- 字段必须添加 COMMENT 注释

### 4.3 回滚规范

- 每个 UP 脚本必须有对应的 DOWN 脚本
- DOWN 脚本的操作顺序与 UP 脚本相反
- DROP TABLE 使用 `IF EXISTS` 防御性写法
- 数据删除操作需要精确的 WHERE 条件，避免误删
