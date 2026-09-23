# API 设计文档：[模块名称]

> 关联需求：REQ-YYYYMM-XXX
> 创建日期：
> 作者：
> 评审人：
> 状态：草稿 | 已评审 | 已批准
> 版本：v1.0

---

## 1. 概述

简要说明本模块提供的 API 能力、使用场景和接入方。

| 项目 | 说明 |
|------|------|
| 基础路径 | `/api/v1/[模块名]` |
| 生产环境 | `https://api.example.com` |
| 测试环境 | `https://api-staging.example.com` |
| 认证方式 | Bearer Token（JWT） |
| 数据格式 | JSON（`Content-Type: application/json`） |
| 字符编码 | UTF-8 |
| 接口数量 | N 个 |

---

## 2. 接口总览

| 方法 | 路径 | 描述 | 需求编号 | 权限 | 状态 |
|------|------|------|----------|------|------|
| POST | `/api/v1/orders` | 创建订单 | REQ-202603-001 | 已登录用户 | 待开发 |
| GET  | `/api/v1/orders/{orderId}` | 查询订单详情 | REQ-202603-002 | 已登录用户 | 待开发 |
| GET  | `/api/v1/orders` | 查询订单列表 | REQ-202603-003 | 已登录用户 | 待开发 |
| PUT  | `/api/v1/orders/{orderId}/cancel` | 取消订单 | REQ-202603-004 | 已登录用户 | 待开发 |

---

## 3. 通用约定

### 3.1 请求头

| Header | 必填 | 说明 |
|--------|------|------|
| `Authorization` | 是 | `Bearer <token>` |
| `Content-Type` | 是（有 Body 时） | `application/json` |
| `X-Request-Id` | 否 | 调用方传入的请求唯一标识，用于链路追踪 |
| `X-Idempotency-Key` | 是（写接口） | 幂等键，防止重复提交，建议使用 UUID |

### 3.2 统一响应结构

```json
{
  "code": 0,
  "message": "success",
  "data": {},
  "requestId": "abc-123",
  "timestamp": 1711382400000
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | int | 业务状态码，0 表示成功 |
| `message` | string | 提示信息 |
| `data` | object / array / null | 响应数据 |
| `requestId` | string | 请求唯一标识 |
| `timestamp` | long | 服务器时间戳（毫秒） |

### 3.3 分页结构

列表接口统一使用以下分页参数和响应结构：

**请求参数：**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `page` | int | 否 | 1 | 页码，从 1 开始 |
| `pageSize` | int | 否 | 20 | 每页数量，最大 100 |

**响应 `data` 结构：**

```json
{
  "list": [],
  "total": 100,
  "page": 1,
  "pageSize": 20,
  "totalPages": 5
}
```

### 3.4 错误码定义

| code | HTTP 状态码 | 含义 | 说明 |
|------|------------|------|------|
| 0 | 200 | 成功 | - |
| 10001 | 400 | 参数错误 | 请求参数校验失败 |
| 10002 | 401 | 未认证 | Token 缺失或已过期 |
| 10003 | 403 | 无权限 | 无操作权限 |
| 10004 | 404 | 资源不存在 | - |
| 10005 | 409 | 资源冲突 | 如重复提交 |
| 10006 | 429 | 请求过于频繁 | 触发限流 |
| 50000 | 500 | 服务器内部错误 | - |
| 50001 | 503 | 服务不可用 | 依赖服务故障 |

> 业务模块错误码在模块内自定义，格式建议：`模块码（3位）+ 错误序号（3位）`，如订单模块 `201001`。

---

## 4. 接口详情

### 4.1 创建订单

**需求编号**：REQ-202603-001

```
POST /api/v1/orders
```

**描述**：用户提交订单，系统创建订单并返回订单编号。

**权限**：已登录用户

**请求参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `addressId` | long | 是 | 收货地址 ID |
| `items` | array | 是 | 商品列表 |
| `items[].productId` | long | 是 | 商品 ID |
| `items[].quantity` | int | 是 | 购买数量，最小值 1 |
| `remark` | string | 否 | 订单备注，最大 500 字符 |

**请求示例：**

```json
{
  "addressId": 10086,
  "items": [
    { "productId": 1001, "quantity": 2 },
    { "productId": 1002, "quantity": 1 }
  ],
  "remark": "尽快发货"
}
```

**响应参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `orderId` | long | 订单 ID |
| `orderNo` | string | 订单编号 |
| `totalAmount` | int | 订单总金额（分） |
| `status` | int | 订单状态（0=待支付） |
| `createdAt` | string | 创建时间（ISO 8601） |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "orderId": 88888,
    "orderNo": "ORD20260318000001",
    "totalAmount": 19900,
    "status": 0,
    "createdAt": "2026-03-18T10:00:00+08:00"
  },
  "requestId": "abc-123",
  "timestamp": 1742266800000
}
```

**错误码：**

| code | 说明 |
|------|------|
| 10001 | 参数校验失败（如 quantity < 1） |
| 201001 | 商品不存在或已下架 |
| 201002 | 库存不足 |
| 201003 | 收货地址不存在 |

---

### 4.2 查询订单详情

**需求编号**：REQ-202603-002

```
GET /api/v1/orders/{orderId}
```

**描述**：根据订单 ID 查询订单详情，仅允许查询本人订单。

**权限**：已登录用户

**路径参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orderId` | long | 是 | 订单 ID |

**响应参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `orderId` | long | 订单 ID |
| `orderNo` | string | 订单编号 |
| `status` | int | 订单状态（见枚举） |
| `totalAmount` | int | 订单总金额（分） |
| `payAmount` | int | 实付金额（分） |
| `items` | array | 商品列表 |
| `items[].productId` | long | 商品 ID |
| `items[].productName` | string | 商品名称 |
| `items[].quantity` | int | 数量 |
| `items[].unitPrice` | int | 单价（分） |
| `createdAt` | string | 创建时间 |
| `paidAt` | string / null | 支付时间 |

**订单状态枚举：**

| 值 | 含义 |
|----|------|
| 0 | 待支付 |
| 1 | 已支付 |
| 2 | 已发货 |
| 3 | 已完成 |
| 9 | 已取消 |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "orderId": 88888,
    "orderNo": "ORD20260318000001",
    "status": 0,
    "totalAmount": 19900,
    "payAmount": 19900,
    "items": [
      {
        "productId": 1001,
        "productName": "示例商品 A",
        "quantity": 2,
        "unitPrice": 9000
      },
      {
        "productId": 1002,
        "productName": "示例商品 B",
        "quantity": 1,
        "unitPrice": 1900
      }
    ],
    "createdAt": "2026-03-18T10:00:00+08:00",
    "paidAt": null
  },
  "requestId": "abc-124",
  "timestamp": 1742266900000
}
```

**错误码：**

| code | 说明 |
|------|------|
| 10003 | 无权限（非本人订单） |
| 10004 | 订单不存在 |

---

### 4.3 查询订单列表

**需求编号**：REQ-202603-003

```
GET /api/v1/orders
```

**描述**：分页查询当前用户的订单列表，支持按状态筛选。

**权限**：已登录用户

**Query 参数：**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `status` | int | 否 | - | 订单状态筛选，不传则查询全部 |
| `page` | int | 否 | 1 | 页码 |
| `pageSize` | int | 否 | 20 | 每页数量 |

**响应参数（`data.list[]` 单条字段）：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `orderId` | long | 订单 ID |
| `orderNo` | string | 订单编号 |
| `status` | int | 订单状态（见枚举） |
| `totalAmount` | int | 订单总金额（分） |
| `createdAt` | string | 创建时间 |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "list": [
      {
        "orderId": 88888,
        "orderNo": "ORD20260318000001",
        "status": 0,
        "totalAmount": 19900,
        "createdAt": "2026-03-18T10:00:00+08:00"
      }
    ],
    "total": 1,
    "page": 1,
    "pageSize": 20,
    "totalPages": 1
  },
  "requestId": "abc-125",
  "timestamp": 1742267000000
}
```

---

### 4.4 取消订单

**需求编号**：REQ-202603-004

```
PUT /api/v1/orders/{orderId}/cancel
```

**描述**：取消待支付状态的订单，其他状态不允许取消。

**权限**：已登录用户

**路径参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orderId` | long | 是 | 订单 ID |

**请求参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reason` | string | 否 | 取消原因，最大 200 字符 |

**请求示例：**

```json
{
  "reason": "不想买了"
}
```

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": null,
  "requestId": "abc-126",
  "timestamp": 1742267100000
}
```

**错误码：**

| code | 说明 |
|------|------|
| 10003 | 无权限（非本人订单） |
| 10004 | 订单不存在 |
| 201004 | 订单状态不允许取消（非待支付状态） |

---

## 5. 数据模型

### 5.1 OrderVO（订单视图对象）

| 字段 | 类型 | 说明 |
|------|------|------|
| `orderId` | long | 订单 ID |
| `orderNo` | string | 订单编号 |
| `status` | int | 订单状态 |
| `totalAmount` | int | 订单总金额（分） |
| `payAmount` | int | 实付金额（分） |
| `remark` | string | 备注 |
| `createdAt` | string | 创建时间（ISO 8601） |
| `paidAt` | string / null | 支付时间 |
| `items` | array\<OrderItemVO\> | 商品明细 |

### 5.2 OrderItemVO（订单明细视图对象）

| 字段 | 类型 | 说明 |
|------|------|------|
| `productId` | long | 商品 ID |
| `productName` | string | 商品名称 |
| `quantity` | int | 数量 |
| `unitPrice` | int | 单价（分） |
| `subtotal` | int | 小计（分） |

---

## 6. 限流与安全

| 接口 | 限流规则 | 说明 |
|------|----------|------|
| POST `/api/v1/orders` | 10次/分钟/用户 | 防止重复提交 |
| GET `/api/v1/orders` | 60次/分钟/用户 | 正常查询 |
| PUT `.../cancel` | 5次/分钟/用户 | 防止频繁操作 |

- 所有写接口需携带幂等键（`X-Idempotency-Key`），服务端保证相同 key 重复请求只处理一次
- 敏感字段（如金额）在日志中脱敏处理

---

## 7. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| v1.0 | | 初始版本 | |

---

## 8. 评审记录

| 日期 | 评审人 | 问题 | 处理结果 |
|------|--------|------|----------|

---

**关联文档：**
- 需求文档：`docs/01_requirements/prd/`
- 数据库设计：`docs/02_design/database/`
- 架构设计：`docs/02_design/architecture/`
