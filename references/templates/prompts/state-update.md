<!-- 状态机更新逻辑 · 被所有 Layer 1/2 命令 @include -->

## 状态机更新（段四必须执行）

本命令完成主产出后，必须更新状态机文件 `docs/.pdlc-state/<feature-id>.json`。

### 文件格式

```json
{
  "feature_id": "<F/B ID>",
  "feature_name": "<kebab-case>",
  "created_at": "<首次创建时间 ISO 8601>",
  "current_stage": "<当前阶段名>",
  "history": [
    {
      "stage": "<阶段名>",
      "done_at": "<ISO 8601>",
      "produced": ["<相对路径 1>", "<相对路径 2>"],
      "self_audit": { "passed": <N>, "failed": <N>, "manual": <N> }
    }
  ],
  "relations": {
    "extends": [],
    "depends_on": [],
    "supersedes": [],
    "resolves": [],
    "conflicts_with": [],
    "relates_to": [],
    "_updated_at": "<ISO 8601 | 省略>"
  },
  "next_step": "<下一跳命令名，如 pdlc-design；若流程结束则为 null>"
}
```

> **`relations` 块（RFC#6，Phase 1 可选，Phase 2 推荐）**：6 个 key 对应 6 种关系类型，各为 ID 数组，存**出边**。类型语义与方向性见 `relations.md`。旧状态文件无此块时视为全空，向后兼容。入边由 `/pdlc-relate rebuild` 派生到 `_relations.json`，不在此块手维护。

### 更新流程

1. **文件不存在** → 创建文件，写入初始结构（`history` 为含当前阶段的数组）
2. **文件存在** → 读取 JSON，追加当前阶段到 `history`，更新 `current_stage` 和 `next_step`
3. **写回文件**：用 `jq` 或等效工具保持格式化

⚠️ 若更新失败（文件损坏/权限问题），必须中止命令并在最终报告中报错。状态机不可跳过。
