---
name: pdlc-status
description: 查看项目 PDLC 状态总览（读 docs/.pdlc-state/ 输出进度）
argument-hint: [feature-id | --all]
allowed-tools: Read, Glob, Bash
layer: 1
stage: ops
produces: []
requires: []
next_step: null
terminal_state: null
---

# 项目 PDLC 状态总览

读取 `docs/.pdlc-state/` 目录下所有状态机文件，输出项目当前的 PDLC 进度、阶段分布、待办建议。

## 执行流程

### 1. 扫描状态机

1. 列出 `docs/.pdlc-state/*.json` 所有文件
2. 若无文件 → 输出：`📭 尚无 PDLC 追踪记录。运行 /pdlc-feature 或 /pdlc-fix 开始第一个功能。`
3. 否则进入下一步

### 2. 解析与分类

按 `current_stage` 字段分组：

- 🚧 进行中：`current_stage` 不在 `[feature_done, fix_done, null]`
- ✅ 已完成：`current_stage` 在 `[feature_done, fix_done]`
- ❓ 异常：JSON 无法解析或字段缺失

### 3. 输出概览

```
📊 PDLC 状态总览（共 <N> 个功能）

🚧 进行中（<M> 个）
  - F20260419-090000 user-auth      当前：design       下一步：/pdlc-tdd
  - F20260419-100000 pwd-reset      当前：impl         下一步：/pdlc-review
  - B20260418-090000 login-crash    当前：fix_done     下一步：（完成）

✅ 已完成（<K> 个）
  - F20260415-110000 feature-xyz    完成于 2026-04-16

⚠️ 待办建议
  - F20260419-090000 停留在 design 超过 2 天，建议推进 /pdlc-tdd
```

### 3.5 关系树视图（RFC#6）

若存在 `docs/.pdlc-state/_relations.json`，附加关系视图（读其 index 的 inbound/outbound）：

```
🔗 关系链
  F20260419-090000 user-auth
    ├─ extends → F20260415-110000 feature-xyz
    └─ ← depended_on_by F20260419-100000 pwd-reset

  🧩 孤立 feature（无任何关系）：F20260420-130000
```

- 出边用 `→`，入边用 `← <反向类型>`
- 末尾列 orphans（inbound + outbound 均空的 feature）
- `_relations.json` 不存在时跳过本节（Phase 1 向后兼容）；Phase 2 起关系视图进入默认总览

### 4. 参数处理

- `$ARGUMENTS` 为空或 `--all` → 输出所有功能
- `$ARGUMENTS` 为功能ID → 只输出该功能的详情（含 history 全量 + 该 feature 的关系）
- `--relations` → 只输出关系树视图

## 参数

- `--all`（默认）：全部功能总览
- `<feature-id>`：单个功能的完整 history
- `--relations`：只输出关系树视图（出边 + 入边 + orphans）
- `--stale <days>`：列出停留在同一阶段超过 `<days>` 天的功能（默认 3 天）

---

**参数**：$ARGUMENTS
