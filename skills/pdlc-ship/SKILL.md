---
name: pdlc-ship
description: 发布工作流（收评审通过的功能 → 跑测试 → bump VERSION → 更 CHANGELOG → tag）
argument-hint: [--version <x.y.z>] [--skip-tests (仅 hotfix)]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
layer: 2
stage: ship
produces:
  - VERSION
  - CHANGELOG.md
  - .git/refs/tags/v<version>
requires:
  - docs/.pdlc-state/
next_step: pdlc-deploy
terminal_state: ship_done
---

# 发布工作流

串联发布一个版本所需的所有步骤：收评审通过的功能 → 跑测试 → 升级 VERSION → 更新 CHANGELOG → 创建 tag。CI 配置默认不动（见 §1.6）。

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
<!-- @include templates/prompts/noninteractive.md（已内联于下方，无需另读） -->
## 非交互模式（`--autonomous`）

若本命令的参数含 `--autonomous`，本命令进入**无人值守**模式，按以下规则处理原本需要人应答的交互点。**参数是唯一真源**：不带 `--autonomous` 即为交互模式，一切照旧正常询问用户；绝不回读状态机 `run_mode` 兜底（「掉出 autonomous」是安全的失败方向）。

1. **流程性确认**（如「测试已绿是否继续」「是否覆盖已有文件」）→ **不询问**，按预设默认前进，并把决策追加到状态机 `history[].auto_decisions[]`：
   ```json
   { "point": "<确认点描述>", "chose": "<所选默认>", "at": "<ISO 8601>" }
   ```
2. **真需人判断**（PRD 关键取舍、评审「需人工确认」项、真实循环依赖等无法安全默认的点）→ **不猜**：
   - `current_stage` 保持不变（不推进）
   - 写 `last_phase_result.ok = false` 且 `blocked_reason = "<原因>"`
   - 末行输出哨兵：`<<<PDLC blocked reason="<原因>">>>`
   - 立即结束命令，交还人类
3. **破坏性操作**（发布 / 部署 / 打 tag / 触发 CI / DROP / force-push 等不可逆·外发操作）→ `--autonomous` **无效**，仍必须人工显式确认。
4. **顺手的 sidecar 产物**（如缺失时创建 `CHANGELOG.md`、补全文档 PDLC-TRACE 的创建时间等本阶段职责内、可安全默认的辅助改动）→ 视为流程性默认，**直接做并记入 `auto_decisions[]`**；这类改动不新增外部副作用，不属破坏性操作。

> 进入 autonomous 模式时，在状态机顶层写 `run_mode: "autonomous"` 仅供留痕（复盘区分人工 vs 循环产出）。
<!-- @include-end templates/prompts/noninteractive.md -->

> ⛔ **发布是破坏性·不可逆操作**：打 tag / bump 版本 / 触发 CI/CD 属破坏性范畴。**`--autonomous` 对本命令无效**——即使带该参数，§1.1（未完成功能）与 §1.2（测试门）的人工确认仍必须真实由人应答。自主循环（`/pdlc-loop-run`）停在「评审通过、`next_step` 为 `pdlc-ship`」（循环文档里称 `review_done`），永不进入本命令。

## 段一：执行

### 1.1 前置检查

1. 确认当前分支不是 `master` / `main`（参考 CLAUDE.md §5）
2. 确认工作区干净（`git status` clean）
3. 盘点 `docs/.pdlc-state/` 下的功能（跳过 `_` 前缀的索引文件与 `statusline.json`），逐个归入四类：
   - **可发布**：`next_step` 为 `pdlc-ship`，且 `last_phase_result.ok` 不是 `false`——评审（或功能编排）已通过、等着发布。这一类**纳入本次发布**
   - **已发布**：`current_stage` 为 `ship_done` 或 `deploy_done`——上一次发布已纳入，本次不再收
   - **旧版终态写法**：`current_stage` 以 `_done` 结尾但不是上面两个（如 `feature_done` / `fix_done` / `review_done`）——旧版本写入，分不清是「已发布」还是「评审通过、待发布」。逐个列出，**请人确认**归入可发布还是已发布；`--autonomous` 也不替人判
   - **进行中**：其余全部（含 `last_phase_result.ok` 为 `false` 的阻塞功能）
   - 有进行中的功能 → 列出来并询问是否继续（用户明确同意才继续；进行中的功能不纳入本次发布）
   - 可发布为空 → 告知「没有评审通过、待发布的功能」，询问是否仍要发布（如只发文档 / 依赖升级）
4. **质量闸门检查**（若项目有 `docs/00_standards/quality-targets.yml`）：
   读 `docs/07_reviews/quality/` 下**最近一份 `.md` 报告**（同名 `.html` 只是视图，
   闸门一律以 `.md` 为准——两者若不一致，信 `.md`）：
   - 无任何报告 → 提示先跑 `/pdlc-quality`，询问是继续还是先出报告
   - 报告**总判定未达标** → **默认不放行**；要发必须由人**显式 override 并写明理由**，
     该理由需记入本次发布的 CHANGELOG 或发布说明（不允许无声跳过）
   - 报告**过期**——分两档处理，**不是所有过期都等价**（见下）
   - 达标且未过期 → 在发布报告里引用该报告路径、日期与 commit SHA 作为质量证据

   #### 过期判定：按「改动了什么」分两档

   报告头部记着生成时的 `<!-- 仓库版本: <commit SHA> -->`（由 `/pdlc-quality` 落盘时写入）。
   取该 SHA，跑 `git diff --name-only <SHA>..HEAD` 看这期间动了什么：

   | 这期间改动命中 | 判定 | 理由 |
   |---|---|---|
   | `docs/01_requirements/prd/`、`docs/00_standards/quality-targets.yml`、`docs/00_standards/e2e-flow-map.yml`、`docs/00_standards/test-commands.yml` | **硬闸·不放行** | 报告里的 PRD ↔ `core_flows` 对账与 E2E 覆盖矩阵的**输入变了**，结论不再成立。重跑单测补不回对账——必须重跑 `/pdlc-quality` |
   | 只有其它代码 / 文档 | 提示已过期，**建议**重跑 | 对账仍成立，测量数字可能略旧 |
   | 报告里没有 `仓库版本` 字段，或该 SHA 在本仓库解析不了 | **按「不可判」处理**：明确告知无法核对新鲜度，建议重跑 | 与三态语义同一条纪律——「查不了」不等于「没问题」，不得静默当作未过期 |

   > ⛔ 硬闸同样允许人**显式 override 并写明理由**（与「总判定未达标」同一条通道，理由须记入
   > CHANGELOG 或发布说明），但**不得无声跳过**。

   #### `quality-targets.yml` 变动要单独看一眼「闸门是不是被调松了」

   若上表命中的文件里**包含 `quality-targets.yml`**，除了要求重跑，还必须把
   `git diff <SHA>..HEAD -- docs/00_standards/quality-targets.yml` **原样展示给人**，
   并逐条点出下列「变松」信号——**命中任何一条都要人明确确认，不得只当作普通过期**：

   - 覆盖率目标数字**下降**（如 85 → 70）
   - `core_flows` 条目**减少**（核心流被移出闸门视野）
   - lint 策略**放宽**（如 zero-warnings 改为允许若干 warning）
   - 新增了**豁免声明**（把某些 PRD / 流程排除在对账之外）

   > **为什么单列**：报告达标之后把目标调低，重跑一次照样是绿的——日期新、SHA 新、结论"达标"，
   > 但**尺子本身变短了**。这与 `/pdlc-test-setup --refresh` 的「严向自动、松向人确认」是同一条
   > 原则换个位置：**放松闸门永远是人的决定，不能由流程默默吸收。**

### 1.2 发布前测试门（参考 CLAUDE.md §6）

**必须主动询问用户**（不得默认跳过，也不得默认强制跑）：

```
📦 发布前测试门检查：是否先跑全量单测 + E2E 测试？

[选项 A] 跑测试（推荐）
  → 后端：./gradlew test 或 mvn test
  → 前端：pnpm test 或 npm test
  → E2E：pnpm exec playwright test（如有）

[选项 B] 跳过测试 —— 仅适用于生产 hotfix
  → 理由：<请说明>
  → 自动记录到 commit 消息

请选择 A 或 B。
```

若选 B：本命令的参数必须含 `--skip-tests` 且有理由说明，否则中止。

### 1.3 版本号处理

1. 读取当前 `VERSION` 文件
2. 若本命令的参数带 `--version x.y.z`，用指定值；否则按语义化规则建议：
   - 本次发布含 fix 且无 feature → 补丁号 +1
   - 含 feature 且无 breaking → 次版本号 +1
   - 含 breaking → 主版本号 +1
3. 写回 `VERSION`

### 1.4 更新 CHANGELOG.md

1. 取 §1.1 盘点出的**可发布**功能（含人工确认归入可发布的旧版终态写法）
2. 分组：缺陷（`B` 开头的 ID）→ "修复"；history 里有 `refactor` 阶段的功能 → "重构"；其余 → "新增"
3. 每条用"- <简要描述>（<feature-id>）"格式写入 CHANGELOG 的 `[未发布]` 段（`/pdlc-review` 可能已为该功能追加过条目——`[未发布]` 段里已有同一功能 ID 的，不重复写）
4. 把 `[未发布]` 改为 `[<new-version>] - <今日日期>`

### 1.5 创建 Tag 并提交

```bash
git add VERSION CHANGELOG.md
git commit -m "release: v<new-version>"
git tag -a "v<new-version>" -m "Release v<new-version>"
```

若选项 B（跳过测试）：commit 消息末尾追加 `[skip-tests: <理由>]`。

### 1.6 CI/CD 配置（默认不动）

本命令**默认不生成、不修改任何 CI 配置**。日常检查（lint / test / build）在本地跑（§1.2 已跑过），CI 按次计费，
每次 push / PR 都触发会很快烧掉额度。项目已有 CI 配置时只读不改：检查它是否覆盖本次新增的测试路径，没覆盖就在交接里提示，由人决定是否修改。

仅当用户**明确要求**生成或修改 CI 配置时才动手，且先确认再写：

1. 先给出用量估算并请人确认：`月预计用量 = 触发次数/月 × 单次时长（分钟）× runner 倍率`（Linux 1× / Windows 2× / macOS 10×）
2. 触发方式默认只用手动触发 + 发布 tag，**不用** push 到分支、PR、定时触发（用户明确要求才改）

**GitHub Actions**（`.github/workflows/release.yml`）：
- 触发：`workflow_dispatch` + `push: tags: ['v*']`
- runner：默认 `ubuntu-latest`；只有必须在 macOS / Windows 上构建或签名时才用对应 runner
- 步骤：checkout → setup 运行时 → install → test → build → 上传产物
- 按项目技术栈选模板（Node/Python/Java/Go）
- 敏感信息通过 Secrets 注入，不硬编码（never hardcode secrets — use Secrets / env vars）

**GitLab CI**（`.gitlab-ci.yml`）：
- stages: build / test / deploy
- cache: 依赖目录
- jobs: 对应各 stage 的执行命令
- 触发：`rules` 只放行 tag 与手动（`when: manual`）
- 生产环境：手动审批后部署

**Jenkins**（`Jenkinsfile`）/ **云效 / 其他**：按项目已有约定生成，同样只用手动 + tag 触发。

生成后在 `docs/05_deployment/ci-cd/` 下记录流水线使用说明。

## 段二：自检

<!-- @include templates/prompts/self-audit.md（已内联于下方，无需另读） -->
## 段二：自检（强制）

重新阅读本次产出物，按质量关卡清单逐项检查。勾选已通过，标注未通过原因。

> **注意**：自检清单的具体内容由各命令自行定义，本片段只规定结构。

## 段三：修复（单次，不递归）

针对自检段标注为未通过的项：

- **可自动修复**：直接修复（如补缺字段、修正格式、补齐缺失段落）
- **修复后回验**：再次运行自检，确认被修复项现在通过
- **无法自动修复**：记录到自审报告，不再尝试，流程继续

⚠️ 单次修复原则：若一轮修复后仍有项未通过，**不再递归修复**，防止死循环。
<!-- @include-end templates/prompts/self-audit.md -->

**发布自检清单：**
- [ ] VERSION 已更新到新版本号
- [ ] CHANGELOG 有本次发布条目
- [ ] tag 已创建（`git tag -l v<new-version>` 返回非空）
- [ ] 若选 A，测试已全绿
- [ ] 若选 B，commit 消息含 `[skip-tests]` 标记
- [ ] 分支不是 main/master
- [ ] 本次纳入的每个功能状态机已写 `ship_done`；未纳入的功能没被改动
- [ ] 未经用户明确要求，没有新增或修改 CI 配置

<!-- @include templates/prompts/loop-prevention.md（已内联于下方，无需另读） -->
## 防循环规则

本命令所有的自检-修复循环均受以下约束：

1. **单次检查**：同一个自检清单在本次命令执行中只跑一次（起始 + 修复后验证共两次读）
2. **单次修复**：发现的问题只尝试修复一轮
3. **不递归**：修复后不再重新触发自检的全量重跑
4. **失败降级**：无法自动修复的问题 → 记录到自审报告 → 流程继续 → 最终报告标注待人工处理

这是为了防止 agent 在"修完再查、查完再修"的往返中陷入死循环。
<!-- @include-end templates/prompts/loop-prevention.md -->

## 段三：修复（若需）

针对未通过项：
- VERSION 未更新 → 重跑 1.3
- CHANGELOG 缺失 → 重跑 1.4
- tag 未创建 → 重跑 1.5
- 分支错误 → 立即中止（不可自动修复）

## 段四：更新状态机 + 交接

<!-- pdlc:meta 由 frontmatter 生成（adapters/sync_skills.py），勿手改 -->
> **本命令的状态机取值**：阶段短名 `ship`（写进 `history[].stage` 与 `last_phase_result.stage`）；下一跳 `pdlc-deploy`（写进 `next_step`，交接时提示）。
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
> - 「评审通过、等待发布」就是 `current_stage` 为 `review`（或 `e2e` 等）且 `next_step` 为 `pdlc-ship`。
>   循环相关文档里说的 `review_done` 指的就是这个状态，**不是**要写进 `current_stage` 的值。
> - 为什么：读侧判「已抵达终态」只看 `current_stage` 是否以 `_done` 结尾。评审通过就写 `_done`，
>   `/pdlc-ship` 就分不清哪些功能已经发布过，发布说明会重复或漏收。
> - 旧版本写入的 `feature_done` / `fix_done` / `review_done` 分不清是否已发布，`/pdlc-ship` 会列出来请人确认。

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

**本阶段状态机更新**：对本次纳入发布的每个功能（§1.1 的可发布 + 人工确认归入的），追加 `{ "stage": "ship", ... }` 到其 history，`current_stage` 写 `ship_done`，`next_step` 写 `pdlc-deploy`。`_done` 的含义是「已发布」，只由本命令与 `/pdlc-deploy` 写入。
- 人工确认为「已发布」的旧版终态写法：不追加 history、不改动，保持原样
- 进行中的功能：不动

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

**本命令的 handoff 输出：**

```
✅ 发布准备完成：v<new-version>
  - VERSION：已更新
  - CHANGELOG：已追加
  - Tag：v<new-version> 已创建
  - 测试：<通过 / [skip-tests: 理由]>
📦 状态机：<N> 个功能已推进到 ship_done（<ID 列表>）
👉 下一步：/pdlc-deploy v<new-version>（部署本次发布；项目有 tag 触发的 CI 时，也可手动 git push origin v<new-version>）
```

---

**参数**：$ARGUMENTS
