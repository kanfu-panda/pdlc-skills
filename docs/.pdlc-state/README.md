# PDLC 状态机目录

此目录由 `pdlc-*` 命令自动维护，请**不要手动修改**。

## 文件格式

每个功能 ID 对应一个 `<feature-id>.json`，记录该功能经历的 PDLC 阶段、每阶段产出物、自检结果、下一跳命令，以及 **`relations` 关系块**（v1.1）。

### 关系链文件（v1.1）

- `_relations.json` — **自动生成**的全量关系反向索引（nodes + 有向 edges + 每节点预计算 inbound/outbound）。由 `/pdlc-relate rebuild` 重建，**不要手动修改**。
- `_graph.md` — **自动生成**的 mermaid 关系图，顶部带 `AUTO-GENERATED` 标记，**不要手动修改**。

## 是否纳入 Git

建议**纳入 git**（不加入 `.gitignore`）。状态机文件 + 关系索引是功能开发过程的审计记录，便于 `/pdlc-retro` 出月度复盘、`/pdlc-relate impact` 做影响分析。

## 使用

- `/pdlc-status` — 读取本目录出项目总览（含关系树视图）
- `/pdlc-relate` — 维护 / 查询关系链（set / query / impact / orphans / rebuild / validate）
- `/pdlc-retro` — 按时间范围读历史出趋势报告
