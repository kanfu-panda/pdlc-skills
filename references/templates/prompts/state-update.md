<!-- 状态机更新逻辑 · 被所有 Layer 1/2 命令 @include -->

## 状态机更新（段四必须执行）

本命令完成主产出后，必须推进状态机文件 `docs/.pdlc-state/<feature-id>.json`。

### 用脚本推进，不要手写状态 JSON

```bash
bash scripts/pdlc-advance.sh <功能ID> --stage <本阶段短名> --next <下一跳命令名|null> \
  [--produced <产物路径，逗号分隔>] [--autonomous] [--decision "<确认点>=<所选默认>"]... \
  [--name <kebab-case>（状态文件还不存在时）] <项目根>
```

- 脚本是本 skill 自带的 `scripts/pdlc-advance.sh`。阶段短名与下一跳就是本命令正文里「本命令的状态机取值」那两个值；带了 `--autonomous` 就照传
- **检查由脚本自己跑**：它按阶段调用同目录的 `scripts/pdlc-checks.sh`（tdd 验红灯；impl / fix / refactor 跑 unit、coverage、lint；
  review 再加 e2e；e2e 只跑 e2e；文档类阶段不跑），据此判 `ok`、整段写入 history 与 `last_phase_result`，
  写完调用 `scripts/pdlc-state-lint.sh` 体检。**不要**自己先写 `checks`，也不要挑检查项
- tdd 阶段的 `--produced` 必须列出写的测试文件：脚本记下它们的指纹，之后 impl / refactor / review 推进时比对
- 主动交还人类（命中人工点、评审有阻塞项、测试本身有矛盾等）→ 加 `--blocked "<原因>"`：脚本照跑检查、如实记录，但不推进，原因写进 `blocked_reason`
- `/pdlc-ship` 写 `ship_done`、`/pdlc-deploy` 写 `deploy_done` → 加 `--done`（只有这两个命令能用）

脚本的退出码决定怎么收尾：

| 退出码 | 含义 | 你要做的 |
|---|---|---|
| `0` | 已推进 | 交接里引用 stdout 那行 JSON（`checks`、`current_stage`、`next_step`） |
| `3` | 未推进：检查没过 / 红灯没验证 / 主动 block / tdd 写的测试被改 | 把 stdout 里的 `blocked_reason` 原样写进报告，按阻塞收尾。**不要为了让它推进去改测试或改检查命令** |
| `2` | 脚本跑不了（参数错、缺 jq、状态文件损坏） | 参数错就改正重跑；缺 jq 才按下面的格式手写，并在报告里写明「状态机未经脚本写入」 |

> 退出码 `3` 且原因是「tdd 阶段写的测试被改动」：实现阶段不改测试。确实是测试本身写错了（与设计 / PRD 矛盾），
> 先在报告里讲清楚，再带 `--tests-changed "<理由>"` 重跑——理由会记进 `auto_decisions`，人看得到。
>
> 项目开了 PDLC 护栏（`docs/00_standards/pdlc-hooks.yml`）时，用 Write / Edit 直接写状态文件会被拦下。

### 状态文件格式（读状态时参考；只有脚本跑不了时才照它手写）

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

> **`relations` 块（RFC#6，Phase 1 可选，Phase 2 推荐）**：6 个 key 对应 6 种关系类型，各为 ID 数组，存**出边**。其中 `conflicts_with` / `relates_to` 是对称类型，两端都要写；其余四种有向，只写在源 feature 上。拿不准时用 `/pdlc-relate set` 写入，它会按规则校验。旧状态文件无此块时视为全空，向后兼容。入边由 `/pdlc-relate rebuild` 派生到 `_relations.json`，不在此块手维护。

> ⛔ **写状态机的四条硬约束**——读侧（`/pdlc-status`、`/pdlc-retro`、`/pdlc-relate`）会逐条体检，
> 违反的每一处都会出现在它们输出的最前面：
>
> 1. **实例里不写 `terminal_state`**。skill frontmatter 的 `terminal_state:` 是「这个命令走完后应到达的终态名」，
>    不是状态字段。判终态只看 `current_stage` 是否以 `_done` 结尾。
> 2. **`history[].stage` 写本命令的阶段短名**（见本命令正文里「本命令的状态机取值」）——`pdlc-implement` 写 `impl`，
>    不写 `implement` / `implementation`；`pdlc-prd` 写 `requirements`，不写 `prd`。
> 3. **时间戳必须带时刻**：`created_at` / `done_at` / `at` 一律写完整 ISO 8601（如 `2026-07-28T10:40:00+08:00`）。
>    只写日期，同一天内的阶段耗时就全部算成 0——读侧只能记「不可测」。
> 4. **`next_step` 只写命令名或 `null`**，不附说明文字（如「pdlc-ship（等评审通过）」）。
>    要说明原因，阻塞时写进 `last_phase_result.blocked_reason`。

> ⛔ **`_done` 的含义是「已发布」，只由 `/pdlc-ship`（写 `ship_done`）与 `/pdlc-deploy`（写 `deploy_done`）写入。**
> 其它命令的 `current_stage` 一律写本命令的阶段短名，走完整条链路的编排命令（`/pdlc-feature`）也一样——
> 它收尾时 `current_stage` 是最后一个阶段的短名，`next_step` 是 `pdlc-ship`。
>
> - 「评审通过、等待发布」就是 `current_stage` 为 `review` 且 `next_step` 为 `pdlc-ship`（`/pdlc-e2e` 在评审之前，它的下一跳是 `pdlc-review`）。
>   循环相关文档里说的 `review_done` 指的就是这个状态，**不是**要写进 `current_stage` 的值。
> - 为什么：读侧判「已抵达终态」只看 `current_stage` 是否以 `_done` 结尾。评审通过就写 `_done`，
>   `/pdlc-ship` 就分不清哪些功能已经发布过，发布说明会重复或漏收。
> - 旧版本写入的 `feature_done` / `fix_done` / `review_done` 分不清是否已发布，`/pdlc-ship` 会列出来请人确认。

### 手写回退（仅脚本退出码 2 且无法修正时）

1. **文件不存在** → 创建文件，写入初始结构（`history` 为含当前阶段的数组）
2. **文件存在** → 读取 JSON，追加当前阶段到 `history`，更新 `current_stage` 和 `next_step`
3. **写回文件**：用 `jq` 或等效工具保持格式化
4. **写完体检**：运行 `bash scripts/pdlc-state-lint.sh <项目根>`，属于本功能状态文件的偏差当场改正。退出码 `2`（缺 jq 等）= 没体检，报告里写明「未体检」，不得当作通过。

⚠️ 若更新失败（文件损坏/权限问题），必须中止命令并在最终报告中报错。状态机不可跳过。

### `last_phase_result`（机器可读阶段结果；脚本按下面的规则写，手写回退时照做）

顶层 `last_phase_result` 是循环判停的**唯一真源**，外层只需 `jq '.last_phase_result.ok'` 即可决定 继续 / 停止 / 交还人类。规则：

1. **`checks` 只放真跑命令的退出码结果**（`scripts/pdlc-checks.sh` 的 stdout 原样），键名只能是 `tests_pass` / `coverage_pass` /
   `lint_clean` / `e2e_pass`（tdd 段 `red_verified`），值只能是布尔或 `null`（无法判定）。不照抄 `test-commands.yml` 的 `unit` / `lint`，
   不写 `"4 passed, 1 failed"` 这类摘要。没有检查可跑的阶段（文档类阶段、项目无 `test-commands.yml`）→ `checks: {}`，
   绝不因为「本阶段成功」就填 `true`——schema 示例里 `checks` 是空的，正是这个意思。
2. **`self_audit` 单列**：只放自检未通过数，**仅供参考，不作循环判停依据**。
3. **`ok` 的定义**：没有命中 `blocked_reason`，且 tdd 段 `red_verified` 为 `true`、其它阶段没有任何检查为 `false`（`null` 不拦）→ `true`；否则 `false`。
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
6. **`run_mode`**：镜像本次调用是否带 `--autonomous`（带了写 `autonomous`，没带写 `interactive`）。
