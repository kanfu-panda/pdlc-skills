# 数据库设计文档：[模块名称]

> 关联需求：REQ-YYYYMM-XXX
> 创建日期：
> 作者：
> 评审人：
> 状态：草稿 | 已评审 | 已批准

---

## 1. 概述

简要说明本模块涉及的数据存储设计，数据量预估，读写比例。

| 项目 | 说明 |
|------|------|
| 数据库类型 | MySQL 8.0 |
| 字符集 | utf8mb4 |
| 排序规则 | utf8mb4_general_ci |
| 存储引擎 | InnoDB |
| 预估数据量 | 100 万行/年 |
| 读写比例 | 读多写少（约 8:2） |

---

## 2. ER 关系图

```
┌──────────┐       1:N       ┌──────────────┐
│  users   │────────────────▶│   orders     │
└──────────┘                 └──────┬───────┘
                                    │ 1:N
                             ┌──────▼───────┐       N:1    ┌──────────┐
                             │ order_items  │─────────────▶│ products │
                             └──────────────┘              └──────────┘
```

---

## 3. 公共字段约定

> 所有表统一包含以下公共字段：

| 字段 | 类型 | 可空 | 默认值 | 说明 |
|------|------|------|--------|------|
| id | bigint | NOT NULL | 自增 | 主键 |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 创建时间 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP ON UPDATE | 更新时间 |
| created_by | varchar(64) | NULL | NULL | 创建人 |
| updated_by | varchar(64) | NULL | NULL | 更新人 |
| is_deleted | tinyint(1) | NOT NULL | 0 | 逻辑删除（0=正常，1=删除） |

---

## 4. 表结构定义

### 4.1 表名：orders（订单主表）

**用途**：存储订单主信息

| 字段 | 类型 | 可空 | 默认值 | 索引 | 说明 |
|------|------|------|--------|------|------|
| id | bigint | NOT NULL | AUTO_INCREMENT | PK | 主键 |
| order_no | varchar(32) | NOT NULL | - | UK | 订单编号 |
| user_id | bigint | NOT NULL | - | IDX | 下单用户 |
| status | tinyint | NOT NULL | 0 | IDX | 订单状态（见枚举） |
| total_amount | int | NOT NULL | 0 | - | 订单金额（分） |
| pay_amount | int | NOT NULL | 0 | - | 实付金额（分） |
| remark | varchar(500) | NULL | NULL | - | 备注 |
| paid_at | datetime | NULL | NULL | - | 支付时间 |
| ... | ... | ... | ... | ... | 公共字段 |

**枚举值说明：**

| 字段 | 值 | 含义 |
|------|-----|------|
| status | 0 | 待支付 |
| status | 1 | 已支付 |
| status | 2 | 已发货 |
| status | 3 | 已完成 |
| status | 9 | 已取消 |

### 4.2 表名：order_items（订单明细表）

**用途**：存储订单商品明细

| 字段 | 类型 | 可空 | 默认值 | 索引 | 说明 |
|------|------|------|--------|------|------|
| id | bigint | NOT NULL | AUTO_INCREMENT | PK | 主键 |
| order_id | bigint | NOT NULL | - | IDX | 所属订单 |
| product_id | bigint | NOT NULL | - | IDX | 商品 ID |
| product_name | varchar(200) | NOT NULL | - | - | 商品名称（冗余） |
| quantity | int | NOT NULL | 1 | - | 数量 |
| unit_price | int | NOT NULL | 0 | - | 单价（分） |
| ... | ... | ... | ... | ... | 公共字段 |

---

## 5. 索引设计

| 表名 | 索引名 | 类型 | 字段 | 用途 |
|------|--------|------|------|------|
| orders | pk_orders | 主键 | id | 主键 |
| orders | uk_orders_order_no | 唯一 | order_no | 订单号唯一 |
| orders | idx_orders_user_id | 普通 | user_id | 按用户查订单 |
| orders | idx_orders_status_created | 联合 | status, created_at | 按状态+时间查询 |
| order_items | idx_order_items_order_id | 普通 | order_id | 按订单查明细 |

---

## 6. 分库分表策略

> 如数据量较小可跳过本节。

| 维度 | 策略 | 说明 |
|------|------|------|
| 分库 | 按 user_id 取模 | 16 库 |
| 分表 | 按 order_id 取模 | 每库 64 表 |
| 路由规则 | user_id % 16 → 库，order_id % 64 → 表 | - |

---

## 7. 数据迁移方案

### 7.1 DDL 变更脚本

```sql
-- V1.0.0 初始化
CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_INCREMENT,
    order_no VARCHAR(32) NOT NULL,
    user_id BIGINT NOT NULL,
    status TINYINT NOT NULL DEFAULT 0,
    total_amount INT NOT NULL DEFAULT 0,
    pay_amount INT NOT NULL DEFAULT 0,
    remark VARCHAR(500) DEFAULT NULL,
    paid_at DATETIME DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by VARCHAR(64) DEFAULT NULL,
    updated_by VARCHAR(64) DEFAULT NULL,
    is_deleted TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uk_orders_order_no (order_no),
    KEY idx_orders_user_id (user_id),
    KEY idx_orders_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单主表';
```

### 7.2 回滚脚本

```sql
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS order_items;
```

---

## 8. 评审记录

| 日期 | 评审人 | 问题 | 处理结果 |
|------|--------|------|----------|

---

**关联文档：**
- 需求文档：`docs/01_requirements/prd/`
- API 设计：`docs/02_design/api/`
- 架构设计：`docs/02_design/architecture/`
