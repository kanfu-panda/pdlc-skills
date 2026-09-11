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
  "run_mode": "interactive | autonomous",
  "history": [
    {
      "stage": "<阶段名>",
      "done_at": "<ISO 8601>",
      "produced": ["<相对路径 1>", "<相对路径 2>"],
      "self_audit": { "passed": <N>, "failed": <N>, "manual": <N> },
      "auto_decisions": [
        { "point": "<autonomous 下自动前进的确认点>", "chose": "<所选默认>", "at": "<ISO 8601>" }
      ]
    }
  ],
  "last_phase_result": {
    "stage": "<本次阶段名>",
    "ok": true,
    "advanced_to": "<推进到的下一阶段 | null>",
    "checks": {},
    "self_audit": { "failed": 0 },
    "blocked_reason": null,
    "run_mode": "interactive | autonomous",
    "at": "<ISO 8601>"
  },
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

> ⛔ 示例里的 `"checks": {}` 是「本阶段没有命令可跑」的样子，**不是键名示范**——键名与取值见下方 §1。

> **`relations` 块（RFC#6，Phase 1 可选，Phase 2 推荐）**：6 个 key 对应 6 种关系类型，各为 ID 数组，存**出边**。类型语义与方向性见 `relations.md`。旧状态文件无此块时视为全空，向后兼容。入边由 `/pdlc-relate rebuild` 派生到 `_relations.json`，不在此块手维护。

> ⛔ **写状态机的四条硬约束**——读侧（`/pdlc-status`、`/pdlc-retro`、`/pdlc-relate`）会逐条体检，
> 违反的每一处都会出现在它们输出的最前面：
>
> 1. **实例里不写 `terminal_state`**。skill frontmatter 的 `terminal_state:` 是「这个命令走完后应到达的终态名」，
>    不是状态字段。判终态只看 `current_stage` 是否以 `_done` 结尾。
> 2. **`history[].stage` 写本命令的阶段短名**，即 frontmatter 的 `stage:`——`pdlc-implement` 写 `impl`，
>    不写 `implement` / `implementation`；`pdlc-prd` 写 `requirements`，不写 `prd`。
> 3. **时间戳必须带时刻**：`created_at` / `done_at` / `at` 一律写完整 ISO 8601（如 `2026-07-28T10:40:00+08:00`）。
>    只写日期，同一天内的阶段耗时就全部算成 0——读侧只能记「不可测」。
> 4. **`next_step` 只写命令名或 `null`**，不附说明文字（如「pdlc-ship（等评审通过）」）。
>    要说明原因，阻塞时写进 `last_phase_result.blocked_reason`。

### 更新流程

1. **文件不存在** → 创建文件，写入初始结构（`history` 为含当前阶段的数组）
2. **文件存在** → 读取 JSON，追加当前阶段到 `history`，更新 `current_stage` 和 `next_step`
3. **写回文件**：用 `jq` 或等效工具保持格式化

⚠️ 若更新失败（文件损坏/权限问题），必须中止命令并在最终报告中报错。状态机不可跳过。

### `last_phase_result`（机器可读阶段结果，每个 phase 收尾必写）

顶层 `last_phase_result` 是循环判停的**唯一真源**，外层只需 `jq '.last_phase_result.ok'` 即可决定 继续 / 停止 / 交还人类。规则：

1. **`checks` 必须客观、真跑得来**：只放**真跑命令的退出码**结果（命令取自 `docs/00_standards/test-commands.yml`，见 `test-commands-template.yml`），**绝不用模型自评、绝不填占位**。有测试的阶段用 `tests_pass` / `coverage_pass` / `lint_clean`（退出码 0 → `true`，非 0 → `false`）；stage 语义不同用对应键（如 tdd 段 `{ "red_verified": true }` 表示红灯已验证）。
   > ⛔ **键名与类型都是契约的一部分**：键名只能是 `tests_pass` / `coverage_pass` /
   > `lint_clean` / `e2e_pass`（tdd 段 `red_verified`），值只能是**布尔**。
   > 最常见的两种错法：① 照抄 `test-commands.yml` 的 `unit` / `coverage` / `lint` / `e2e`
   > ——那是**命令表**的字段名，不是状态机的（跑 `unit` 得到的结论写进 `tests_pass`）；
   > ② 写成 `"4 passed, 1 failed"` 这类字符串摘要。两种都会让 `jq '.checks.tests_pass'`
   > 读回 `null`，消费方（发布闸门、质量报告、自主循环）只看到「无法判定」——
   > **你诚实跑出来的结果等于没写**。三态怎么分见 `check-commands.md`。
   >
   > ⚠️ **没有检查命令可跑的阶段（如 requirements/design 只产文档，或项目无 `test-commands.yml`）→ `checks: {}` 留空。绝不因为「本阶段成功」就把 `tests_pass`/`lint_clean` 等填 `true`——那是虚报，会污染跨工具共用的状态机、误导自主循环判停。** 上面 schema 示例里 `checks` 之所以是空的，正是这个原因——**空是"没跑"的意思，不是键名的示范**。
2. **`self_audit` 单列**：只放自检未通过数，**仅供参考，不作循环判停依据**。
3. **`ok` 的定义**：本阶段全部 `checks` 通过且未命中 `blocked_reason` → `true`；否则 `false`。
4. **命名空间**：`advanced_to` = **下一阶段的短名**，**不是命令名、也不是本阶段的 `current_stage`**。三者关系：`stage`=本阶段短名、`current_stage`=本阶段完成后的当前短名、`advanced_to`=下一阶段短名、`next_step`=下一跳命令名。

   ⛔ **短名不是「命令名去掉 `pdlc-` 前缀」**——`pdlc-implement` 的短名是 **`impl`**，不是 `implement`。别推导，查下表：

<!-- stage-map:start -->
   | `next_step`（下一跳命令名） | `advanced_to`（下一阶段短名） |
   |---|---|
   | `pdlc-tdd` | `tdd` |
   | `pdlc-implement` | `impl` |
   | `pdlc-review` | `review` |
   | `pdlc-design` | `design` |
   | `pdlc-ship` | `ship` |
   | `pdlc-deploy` | `deploy` |
<!-- stage-map:end -->

   `next_step` 为 `null`（终态或无后续）时 `advanced_to` 也是 `null`。

   > 📌 **本表是唯一真源，且是被断言钉住的**：每行的短名必须等于该 skill 自己 frontmatter
   > 里声明的 `stage:`，且任何 skill 的非 `null` `next_step` 都必须在表里有行——两个方向
   > 都由 `tests/frontmatter-check.sh` 检查，所以表不会和实现各自漂移。
   >
   > 写错短名的后果与键名写错同类：消费方按契约名匹配，认不出就当没这个阶段。
5. **推进一致**：`ok=true` 时本阶段必须真的推进了 `current_stage`（与第 6 条 IRON LAW 呼应）；到达终态或无后续时 `advanced_to=null`。`ok=false`（含 blocked）时 `current_stage` 不变、`advanced_to=null`、`blocked_reason` 写明原因。
6. **`run_mode`**：镜像本次调用是否带 `--autonomous`（见 `noninteractive.md`）。
