---
name: pdlc-e2e
description: 端到端测试（生成或执行 E2E 用例）
argument-hint: <功能ID | 业务流程描述>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: e2e
produces:
  - docs/04_testing/e2e-tests/<feature-id>-<feature-name>-e2e.md
  # E2E 测试代码跟随项目既有的 E2E 目录（正文「测试放哪」）
  - <E2E 测试代码 · 项目既有布局>
requires: []
next_step: pdlc-review
terminal_state: e2e_done
---

# 端到端测试

<!-- @include templates/prompts/iron-law.md（已内联于下方，无需另读） -->
⛔ **IRON LAW · 不可违反的硬门禁**

以下规则为**不可协商**的执行约束：

1. **文件必须落盘**：所有带编号（功能ID / 缺陷ID）的文档，必须作为实际文件写入磁盘，不可仅在对话中输出。
2. **阶段必须落章**：每个阶段完成后必须在状态机 `docs/.pdlc-state/<feature-id>.json` 追加 history，不可跳过。
3. **测试必须存在**：进入 `/pdlc-implement` 前，对应测试必须存在且处于红灯状态。违反则中止。
4. **自检必须执行**：段二自检为强制步骤，不得以"已经很好了"为由跳过。
5. **防循环**：段三修复为单次，不递归。无法自动修复的问题记录到报告，继续往下走。
6. **状态必推进**：成功执行某 phase 后 `current_stage` 必须变更。收尾时若发现 `current_stage` 未推进，视为失败并报错，**不得静默返回**（防止外层循环拿滞后的状态空转烧额度）。唯一例外：命中人工点主动 block 时，`current_stage` 保持不变但必须写 `last_phase_result.ok=false` + `blocked_reason`。

**违反任一条 = 立即中止当前命令，输出违规详情，等待人工介入。**
<!-- @include-end templates/prompts/iron-law.md -->

编写端到端（E2E）测试用例，验证完整的用户操作流程。位置在实现之后、评审之前（下一跳 `/pdlc-review`，评审会把 E2E 结果一并纳入闸门）。

<!-- @include templates/prompts/artifact-lookup.md（已内联于下方，无需另读） -->
## 定位上游产物：先查状态机，再按关键词搜

守卫要找的上游文档（PRD、设计文档、评审记录等），按下面的顺序定位，**命中即停**：

1. **输入是功能ID / 缺陷ID**（`F…` / `B…`）且 `docs/.pdlc-state/<ID>.json` 存在 → 读它 `history[].produced` 里记下的路径，取所需类型的文档。这是上游阶段亲手记的，最可靠
2. **没有状态机、或 `produced` 里没有所需文档** → 在对应目录下搜：文件名含该 ID 或功能名关键词，或文件顶部 PDLC 追溯头的 `功能ID` 等于该 ID
3. **命中多份** → 不要随手挑一份：交互模式下列出来请人选；`--autonomous` 下优先取文件名含该 ID 的，仍不止一份则按「真需人判断」阻塞（写 `blocked_reason`，列出候选）

找到后从文件名或追溯头取功能ID，后续产出一律沿用它，**不另分配新 ID**。
<!-- @include-end templates/prompts/artifact-lookup.md -->

## PDLC 前置检查（必须执行，不可跳过）

1. 按上面的顺序找到本功能的 PRD（必需）与 UI 设计文档（`docs/02_design/ui-ux/`，有则读），确定功能ID
2. **检查实现是否已完成**：状态机 `current_stage` 应为 `impl`（或更后）；没有状态机时，确认实现代码已存在
3. **未找到 PRD** 或 **实现未完成** → 输出以下信息后**立即停止**：
   ```
   ⛔ PDLC 守卫：「<功能名>」缺少 PRD 或实现尚未完成，E2E 测试无从验证。
   👉 /pdlc-prd <需求描述>  或  /pdlc-implement <功能ID>
   ```

## 工作流程
1. **阅读需求文档**: 读 PRD 的用户故事与验收标准——E2E 用例从这里来
2. **阅读 UI 设计**: 读 UI 设计文档（如有）
3. **梳理测试场景**: 按用户旅程梳理核心操作路径（分级见下）
4. **编写测试计划**: 在 `docs/04_testing/e2e-tests/` 下创建 `<功能ID>-<功能名>-e2e.md`，文档顶部带 PDLC 追溯头
5. **编写测试代码**（测试放哪）: 放进项目**既有的** E2E 目录与框架（看 `test-commands.yml` 的 `e2e` 命令、`playwright.config.*` / `cypress.config.*` 的 testDir、已有的 `*.spec.*` / `*.e2e.*` 文件）；项目还没有 E2E 时，把选用的框架和目录写进报告
6. **对齐核心流映射**: 若存在 `docs/00_standards/e2e-flow-map.yml`，本功能涉及的核心流（`quality-targets.yml` 的 `core_flows`）要把新写的测试标识填进对应 flow 的 `tests`——`/pdlc-quality` 靠这份映射机械判定「核心流都有 E2E」
7. **运行验证**: 运行 `bash scripts/pdlc-checks.sh --only e2e <项目根>`，stdout 的 `{"e2e_pass":…}` **原样**写进 `last_phase_result.checks`。`e2e` 命令为空 → `null`（无法判定），在报告里提示补上 `test-commands.yml` 的 `e2e`

## 测试场景设计
- **核心路径（P0）**: 必须通过，如登录→主流程→结果验证
- **分支路径（P1）**: 常见的备选操作路径
- **异常路径（P2）**: 网络错误、超时、权限不足等异常场景
- **边界场景（P3）**: 空数据、超长输入、并发操作

## 测试框架（根据前端技术栈）
- React/Vue/Next.js: Playwright 或 Cypress
- 微信小程序: miniprogram-automator
- API 层: 直接用 HTTP 请求库

## 要求
<!-- @include templates/prompts/output-language.md（已内联于下方，无需另读） -->
🌐 **Output language for generated artifacts**

All generated artifacts (PRDs, design docs, code comments, review reports,
test plans, deployment manuals, changelog entries, etc.) follow this policy:

1. **Default — match the conversation language exactly**:
   - 用户用中文与 Claude 对话 → 产中文文档、中文代码注释、中文报告
   - User talks to Claude in English → produce English artifacts
   - User talks in another language → produce artifacts in that language
   - **Never silently default to a fixed language regardless of the user's input.**

2. **Explicit override always wins**: when the user specifies a language for
   an artifact (e.g. "write the PRD in English", "用英文写 API 设计文档",
   "output the deploy doc in Japanese"), use that language for that artifact,
   regardless of conversation language.

3. **Mixed-language requirements**: if the user wants some artifacts in one
   language and others in a different language (common: Chinese PRD + English
   API docs for partners), honour each per-artifact instruction.

4. **Uncertain**: if you cannot reliably detect the conversation language,
   ask once before producing the first artifact.

This policy applies to **content** (prose, comments, headings). It does
**not** override technical conventions like English variable names, English
git commit subjects, or English error codes when the project's conventions
require them.
<!-- @include-end templates/prompts/output-language.md -->
- 测试用例命名格式: `应该_当<条件>时_<预期行为>`
- 测试数据独立，不依赖其他测试的执行结果
- 每个测试结束后清理数据

测试目标: $ARGUMENTS

<!-- @include templates/prompts/check-commands.md（已内联于下方，无需另读） -->
## 跑 check 命令：退出码的三态语义

**用脚本跑，不要手写 `checks`**：

```bash
bash scripts/pdlc-checks.sh --only <本阶段要的项，如 unit,lint> <项目根>
```

脚本是本 skill 自带的 `scripts/pdlc-checks.sh`。它读 `docs/00_standards/test-commands.yml`（唯一真源），逐条真跑，按下表映射，**stdout 只有一行 JSON**——
**原样**写进 `last_phase_result.checks`，不改键名、不改值、不补不删。每条命令的退出码与输出末尾回显在
stderr，报告里引用那几行即可。脚本退出码 `2`（没有 yml 等）= 没有可跑的 check → `checks: {}`。

> 为什么不手写：键名、布尔类型、三态这几件事是确定性的，交给模型写，真机上同一份项目轮与轮之间就换一种错法
> （键名照抄 yml 的 `unit`、值写成 `"4 passed, 1 failed"`、`127` 写成 `false`）。
> 环境里没有 `bash` 时才按下表手工映射。

脚本按退出码分三态——不是两态。这是 IRON LAW「checks 只认客观事实」在执行层的落法：

| 观察到的 | 含义 | 写进 `checks` |
|---|---|---|
| 退出码 `0` | 通过 | 对应键 = `true` |
| 退出码非 0（命令**跑起来了**，只是没过） | 未通过 | 对应键 = `false` |
| 退出码 `127` / `command not found` / 脚本文件不存在 / 该项为空字符串 | **无法判定** | **省略该键，或写 `null`**——**绝不能是 `false`** |

> ⛔ **唯一的红线是不许写 `false`**：那是**会误导人的虚报**——它说的是"检查失败了"，
> 于是有人去查代码，但真正的问题是**配置过期**，代码可能完全没毛病。
>
> **省略键与 `null` 等价，两种都可以**：对消费方而言无法区分（`jq '.checks.lint_clean'`
> 在两种情况下都返回 `null`）。`null` 甚至更明确——省略是歧义的（"没看"还是"看了判不出"），
> `null` 明说"看了，判不出"。**别在这上面纠结，力气花在不写 `false` 上。**
>
> 这与「没有检查命令可跑的阶段 → `checks: {}`」同源。

## 「跑不了」＝ `test-commands.yml` 过期信号（顺带检测，零额外成本）

命令跑不起来，几乎总意味着**这份 yml 已经跟不上项目了**——脚本改名、runner 换了、
工具从依赖里移除、子项目路径调整。真实项目里这类漂移是常态（例如某前端框架升级后
移除了内置 lint 子命令，而 yml 里那条命令还在）。

由于**各阶段本来就在跑这些命令**，这个信号是白捡的。检测到时：

1. 在本阶段的报告里单列一条：**「`test-commands.yml` 疑似过期」**，写明是哪一项、
   观察到什么（退出码 / 报错原文）、以及为什么判定为"跑不了"而非"没通过"。
2. 提示补救：`/pdlc-test-setup --refresh`（重新探测并给出 diff）。
3. **不要自作主张改 yml**——本阶段的职责是干活，不是改配置；只报告，不动手。

## 变更方向决定自动化程度（`--refresh` 时适用）

更新这份 yml 等于**改变"通过"的定义**，所以按**方向**区别对待：

| 方向 | 例子 | 处理 |
|---|---|---|
| **让闸门变严** | 空着的 `e2e` 现在能跑了、覆盖率阈值上调 | **可自动应用**，报告留痕 |
| **平移替换** | 命令改名但语义相同，且新命令**已验证能跑** | **可自动应用**，报告留痕 |
| **让闸门变松** | 删掉某条 check、把命令改成空、下调阈值 | **必须人确认**，绝不自动 |

> ⚠️ 这条方向规则是防「自动修复把闸门修没了」：lint 命令坏掉时，**把它留空**是最省事的
> "修法"，结果闸门悄悄松了、报告还是绿的——比不更新更危险。
> **变严可以自动，变松必须由人签字。**
<!-- @include-end templates/prompts/check-commands.md -->

<!-- pdlc:meta 由 frontmatter 生成（adapters/sync_skills.py），勿手改 -->
> **本命令的状态机取值**：阶段短名 `e2e`（写进 `history[].stage` 与 `last_phase_result.stage`）；下一跳 `pdlc-review`（写进 `next_step`，交接时提示）。
<!-- pdlc:meta-end -->
<!-- @include templates/prompts/state-update.md（已内联于下方，无需另读） -->
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

### 更新流程

1. **文件不存在** → 创建文件，写入初始结构（`history` 为含当前阶段的数组）
2. **文件存在** → 读取 JSON，追加当前阶段到 `history`，更新 `current_stage` 和 `next_step`
3. **写回文件**：用 `jq` 或等效工具保持格式化
4. **写完体检**：运行本 skill 自带的 `scripts/pdlc-state-lint.sh`（`bash scripts/pdlc-state-lint.sh <项目根>`）。输出里**属于本功能状态文件**的偏差当场改正（键名、类型、`ok` 与 `checks` 不一致等），改不了的写进本阶段报告；其它功能的偏差不归本命令管。退出码 `2`（缺 jq 等）= 没体检，报告里写明「未体检」，不得当作通过。

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
   > **你诚实跑出来的结果等于没写**。三态怎么分见本命令正文里「跑 check 命令：退出码的三态语义」一节；正文里没有这一节的命令不跑 check 命令，`checks` 写 `{}`。
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
6. **`run_mode`**：镜像本次调用是否带 `--autonomous`（带了写 `autonomous`，没带写 `interactive`）。
<!-- @include-end templates/prompts/state-update.md -->
<!-- @include templates/prompts/handoff.md（已内联于下方，无需另读） -->
## 段四：交接（Handoff）

命令完成后必须输出以下格式的最终消息：

```
✅ <阶段名> 完成：<主要产出物路径>
📊 自检：<通过数>/<总数> 通过（若有未通过，附要点）
📦 状态快照：docs/.pdlc-state/<feature-id>.json
👉 下一步：/pdlc-<next_step>
   （如果有分叉）或 /pdlc-<alt>（条件：<选择依据>）
```

**规则：**
- 主流程命令（写状态机的命令；下一跳见正文里「本命令的状态机取值」）必须显式输出"下一步"，不可省略
- 工具型命令（Layer 3）可以没有 `next_step`，此时输出 `👉 下一步：（本次流程结束，无后续）`
- 分叉场景必须说明**选择条件**，例如"若需补充测试用例 → `/pdlc-tdd`；若测试已齐 → `/pdlc-review`"
<!-- @include-end templates/prompts/handoff.md -->
