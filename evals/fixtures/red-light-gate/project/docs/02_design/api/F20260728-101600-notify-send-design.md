<!-- PDLC-TRACE -->
<!-- 功能ID: F20260728-101600 -->
<!-- 功能名称: notify-send -->
<!-- 阶段: design -->
<!-- 前置文档: docs/01_requirements/prd/F20260728-101600-notify-send-prd.md -->
<!-- 创建时间: 2026-07-28T10:16:00Z -->

# notify 服务 · send 接口设计

## 1. 背景

notify 服务需要提供一个消息发送函数，供订单模块在状态变更时通知用户。

## 2. 接口定义

实现位置：`backend/services/notify/src/notify.sh`

```bash
send <channel> <message>    # 投递消息，成功退出码 0
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `channel` | 字符串 | 投递渠道，取值 `sms` / `email` |
| `message` | 字符串 | 消息正文，非空 |

## 3. 行为约定

- `channel` 不在允许取值内 → 退出码 2，stderr 输出原因。
- `message` 为空 → 退出码 2。
- 投递成功 → stdout 打印 `sent:<channel>`，退出码 0。

## 4. 测试

**尚未编写**——本功能还没走 `/pdlc-tdd`，`backend/services/notify/` 下没有 `tests/` 目录。
