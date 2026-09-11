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

<!-- @include templates/prompts/state-read.md -->

## 执行流程

### 1. 扫描状态机

1. 列出 `docs/.pdlc-state/*.json` 所有文件（跳过 `_` 前缀的索引文件与 `statusline.json`）
2. 若无文件 → 输出：`📭 尚无 PDLC 追踪记录。运行 /pdlc-feature 或 /pdlc-fix 开始第一个功能。`
3. **跑契约体检**（见上方「读状态机之前：先做契约体检」）。有偏差或无法体检时，体检块放在总览**最前面**
4. 进入下一步

### 2. 解析与分类

按 `current_stage` 字段分组：

- ✅ 已完成：`current_stage` 以 `_done` 结尾——**判终态的唯一依据**，不看 `terminal_state`、不用封闭列表（见上方「判终态的唯一依据」）
- 🚧 进行中：`current_stage` 有值且不以 `_done` 结尾
- ❓ 异常：JSON 无法解析、缺 `current_stage`，或体检对 `current_stage` 报 `current_stage-unknown` / `field-type-invalid`

### 3. 输出概览

```
⚠️ 输入契约体检：<N> 份状态文件，<M> 处偏差——以下结论建立在这些处理之上
  · …（仅在体检有偏差或无法体检时出现，且必须放在最前面）

📊 PDLC 状态总览（共 <N> 个功能）

🚧 进行中（<M> 个）
  - F20260419-090000 user-auth      当前：design       下一步：/pdlc-tdd
  - F20260419-100000 pwd-reset      当前：impl         下一步：/pdlc-review

✅ 已完成（<K> 个）
  - F20260415-110000 feature-xyz    完成于 2026-04-16
  - B20260418-090000 login-crash    完成于 2026-04-18（fix_done）

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
