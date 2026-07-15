---
name: pdlc-loop-run
description: 收敛循环引擎（自动推进 tdd→implement→review 到 review_done 或 blocked）
argument-hint: <功能ID> [--max-steps N]
allowed-tools: Read, Glob, Bash, Task
layer: 3
stage: ops
produces: []
requires:
  - docs/.pdlc-state/
next_step: null
terminal_state: null
---

# 收敛循环引擎（loop-run）

把机械收敛段 `tdd → implement → review` 烧成一个自主循环：从 `current_stage` 出发逐阶段自动推进，直到 `review_done` 或被 `blocked`。这是 `/pdlc-loop-next` 之上的高层引擎——用户不必自己写 bash 循环。

<!-- @include templates/prompts/noninteractive.md -->

> ⛔ **终态即 `review_done`（设计如此）**：本引擎**只覆盖机械收敛段**。到达 `review_done` 即**成功停机**，交人工决定是否 `/pdlc-ship`。**绝不**自动进入 `pdlc-ship` / `pdlc-deploy`——发布/部署是不可逆·外发操作，永远留人（`--autonomous` 对它们无效）。prd/design 的关键取舍同样不在本引擎范围内。

## 两种运行形态

- **默认推荐 · 外部 Runbook（真进程隔离）**：长跑 / 过夜 / 多 feature 并行时，用独立进程逐轮跑，每轮全新进程 = 真 fresh context 最可信。本命令可打印该 Runbook 脚本（见 usage-guide「自主循环 Runbook」）。
- **便捷 · 插件内 Task 版（本命令默认行为）**：适合短收敛。每个 stage 派发给一个 **fresh Task subagent**（context 相对隔离），返回后读状态机决定推进 / 停 / block。

## 循环算法（Task 版）

1. 从 `$ARGUMENTS` 取功能ID；`--max-steps` 取迭代上限（缺省 **4**）。读 `docs/.pdlc-state/<功能ID>.json`。
2. 循环，每轮：
   1. 按 `/pdlc-loop-next` 的映射判定下一条命令：`pdlc-tdd` / `pdlc-implement` / `pdlc-review` / `done` / `blocked`。
   2. `done` → **成功停机**，输出 `<<<PDLC done stage=review>>>`，提示交人工 `/pdlc-ship`。
   3. `blocked` → 停机交还人类，输出 `<<<PDLC blocked reason="...">>>`。
   4. 否则用 **Task 工具派发**该命令到一个 fresh subagent，**带 `--autonomous`**，模型取目标 skill frontmatter 的 `recommended_model`（无则继承）。
   5. subagent 返回后重新读状态机 `last_phase_result`：
      - `ok=false` → **fail-stop**：停机、不重跑同一 stage，输出 blocked 哨兵。
      - `current_stage` 未推进（违反 IRON LAW 第 6 条）→ **stuck-stop**：停机报错。
      - `ok=true` 且已推进 → 记一步，继续下一轮。
   6. 步数 > `--max-steps` → **上限停机**（防病态空转烧 token）。
3. 输出循环小结（跑了几步、终态、每步 `last_phase_result` 摘要）。

## 护栏（不可协商）

- **迭代上限**：收敛段线性前进 `tdd→implement→review`（3 段），默认上限 **4** = 3 段 + 1 段容错余量（供「首轮 block、人工修好后从原 stage 续跑一次」）。不给更多余量。
- **只前进不回炉**：循环只在**不同 stage 间前进**，永不原地重跑同一 stage（与 IRON LAW「修复单次不递归」一致——单 stage 内的修复仍是单次）。
- **fail-stop / stuck-stop**：任一 stage `ok=false` 或状态未推进即停，绝不空转。
- **预算**：外部 Runbook 形态必须配 `--max-budget-usd`（见 usage-guide）。自主循环持续烧 token，护栏是硬要求。

## 与 IRON LAW 的关系

本引擎不违反「修复单次不递归」：单个 stage 的自检-修复仍单次；引擎做的是**跨 stage 前进 + 失败即停 + 上限**，不是「重试同一步」。

功能ID: $ARGUMENTS
