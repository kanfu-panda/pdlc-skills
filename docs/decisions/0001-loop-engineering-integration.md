# 0001 · PDLC-skills 面向 Loop 工程的可循环化改造方案

- **状态**：Proposed
- **日期**：2026-07-14
- **作者**：kanfu-panda

---

## 1. 背景与目标

「Loop 工程」是社区正在成形的一种范式（Boris Cherny、Addy Osmani 等的公开讨论，以及 Ralph Wiggum 技术）：价值从「写一条好 prompt」转移到「设计一个能自主迭代、自带校验、会主动停下的循环系统」。核心公理：

> **A loop is a task with a check. A task without a check is just hope.**

PDLC 天生具备 Loop 工程最稀缺的三样东西：**精准 spec**（PRD / design）、**真实 check**（TDD 测试）、**机器可读状态机**（`docs/.pdlc-state/<ID>.json`）。只差「最后一公里」——让循环能**无歧义驱动**它、**无人值守**跑它、且**不烧爆额度**。

**目标**：让 pdlc-skills 从「人驱动的分阶段工作流」升级为「既能人驱动、也能被自主循环驱动」的执行引擎。

**非目标（明确不做）**：
- 不改变 PDLC 方法论内核（阶段划分、文档产物、IRON LAW）。
- 不把 PDLC 变成「整夜无人 Ralph」。PDLC 的价值恰恰是**可审计 + 有人工边界**；破坏性/终审环节永远留人。
- 不为「未来可能用到」的循环形态提前抽象（YAGNI）。

---

## 2. 设计原则

1. **check 必须客观**：循环的「过没过」只能由**真跑命令的退出码**决定，绝不用模型自评（`self_audit`）。这是 Loop 工程反复警告的反模式——写代码的模型给自己打分会系统性虚报成功。
2. **状态机是唯一真源**：循环读 `docs/.pdlc-state/<ID>.json`，不解析散文。
3. **只前进不回炉**：循环在**不同 stage 间前进**；同一 stage 失败即停，绝不原地重跑（与 IRON LAW「修复单次不递归」一致）。
4. **人工边界机器可判定**：哪些能无人循环、哪些必须交还人类，由代码显式判定并留痕。
5. **参数化控制，逐命令显式**：所有循环控制走命令行参数，不用环境变量（env 会泄漏到整个 shell；参数是逐命令、可留痕的，也贴合本仓库既有 `--range`/`--version`/`--stale` 约定）。

---

## 3. 已定决策

| 决策 | 结论 |
|---|---|
| **Q1 非交互参数名** | `--autonomous`（与状态机 `run_mode: "autonomous"` 同名，留痕一致）。不做多别名。 |
| **Q2 循环「停」的信号** | slash command **无法设进程退出码**。改为：命中人工点时写 `last_phase_result.ok=false` + `blocked_reason` 到状态机；外层循环用 `jq` 读状态机判停。stdout 哨兵仅作崩溃兜底（见 §4.2）。 |
| **Q3 破坏性操作** | `--autonomous` **不绕过** ship / deploy 的破坏性确认。发布/部署/打 tag/触发 CI 永远留人（见 §7）。 |
| **Q4 参数跨迭代** | **严格以本次调用参数为真源**；外层每轮重传参数。skill 顺手镜像进 state 的 `run_mode` 仅供留痕，**不回读 state 兜底**——漏传参数就退回交互模式，「掉出 autonomous」是安全的失败方向。 |
| **命名前缀** | 纯循环专用的**新命令**统一 `pdlc-loop-` 前缀（`/pdlc-loop-next`、`/pdlc-loop-run`）。既有命令加 `--autonomous` 参数，不改名。 |

---

## 4. 核心概念

### 4.1 Loop 契约（什么叫 done）

每个 phase 的 done 由**该项目的客观 check 命令**定义，命令来源统一到 `docs/00_standards/test-commands.yml`（§5.C）。契约不是模型的主观判断，而是「`unit` 命令退出码为 0，且 `coverage` 命令退出码为 0（达标线写死在该命令自身的 `--fail-under` 里，不做二次解释），且 `lint` 干净」。

### 4.2 阶段结果协议（替代「非零退出码」）

**主真源：状态机文件**。每个 phase 收尾在 `<ID>.json` 顶层写 `last_phase_result`：

```json
"last_phase_result": {
  "stage": "impl",
  "ok": true,
  "advanced_to": "review",
  "checks": { "tests_pass": true, "coverage_pass": true, "lint_clean": true },
  "self_audit": { "failed": 0 },
  "blocked_reason": null,
  "run_mode": "autonomous",
  "at": "2026-07-14T16:15:00+08:00"
}
```

- **`checks` 保持纯客观**：三个字段全部来自真跑命令的退出码，不含任何模型自评。
- **`self_audit` 单列一层**：仅作参考，**不作循环判停依据**（呼应 §2.1）。
- 外层循环只需 `jq '.last_phase_result.ok' <ID>.json` → 决定 继续 / 停止 / 交还人类。

**崩溃兜底：stdout 哨兵**。为防「skill 崩溃在写状态机之前」，命令末尾可打印一行哨兵。它**不是第二真源**，仅当状态机的 `last_phase_result.at` 未推进时供外层判「skill 异常退出」：
- `<<<PDLC ok=true advanced_to=review>>>`
- `<<<PDLC blocked reason="PRD 关键取舍需人工">>>`
- `<<<PDLC done stage=review>>>`

二者不一致时以状态机为准，并记录为异常。

### 4.3 人工 / 自动边界（机器可判定）

| 情形 | autonomous 下的行为 |
|---|---|
| 「请确认是否继续」类**流程性确认**（如 `pdlc-implement:37` 测试已绿） | 按预设默认前进，决策写入 `history[].auto_decisions[]` 留痕 |
| **真需人判断**（PRD 关键取舍、review 标「需人工确认」项、真实循环依赖） | **不猜**：`current_stage` 停在原地，写 `blocked_reason`，`ok=false`，输出 blocked 哨兵 |
| **破坏性操作**（ship/deploy/tag/CI/DROP/force-push） | 永远留人；`--autonomous` 无效，仍需显式人工授权（Q3） |

---

## 5. 详细设计

> ★ = P0 首批必做；○ = 建议同批；△ = 可延后

### A. 非交互契约 `--autonomous`（★）

- **新增共享片段** `references/templates/prompts/noninteractive.md`，规定：
  - 从 `$ARGUMENTS` 解析 `--autonomous`；
  - 流程性确认 → 按默认前进 + 写 `auto_decisions[]`；
  - 人工点 → 写 `blocked_reason` + `ok=false` + blocked 哨兵；
  - 破坏性点 → 忽略 `--autonomous`，仍要人工授权。
- 受影响既有 skill `@include` 该片段并改造各自的确认点（见 §8 清单）。

### B. 结构化阶段结果 `last_phase_result`（★）

- 改 `references/templates/prompts/state-update.md` schema：增加顶层 `last_phase_result`、`run_mode`、`history[].auto_decisions[]`。
- **关键铁律**：`checks.*` 全部来自真跑命令的退出码，不是 `self_audit` 自评。`self_audit` 在 `last_phase_result` 里单列一层，仅供参考，不作判停依据。

### C. test-commands 唯一真源（★，从建议稿的 P1 提到 P0）

- **新增模板** `references/templates/test-commands-template.yml`；目标项目落地为 `docs/00_standards/test-commands.yml`：
  ```yaml
  unit:     "cargo test"                              # 或 ./gradlew test / pnpm test
  coverage: "cargo llvm-cov --fail-under-lines 85"    # 达标线写死在命令里
  lint:     "cargo clippy -- -D warnings"
  e2e:      "cargo test --test e2e"
  ```
- `pdlc-tdd` / `pdlc-implement` / `pdlc-review` 从此取 check 命令；`pdlc-bootstrap` / `pdlc-adopt` 生成它；`pdlc-standard` 认它。
- **理由**：没有唯一真源的 check 命令，`last_phase_result.ok` 就只是模型一面之词——C 是 B 可信的前提，故与 B 同批。

### D. 推进不变式（★）

- 改 `references/templates/prompts/iron-law.md`，加**第 6 条硬门禁**：
  > **状态必推进**：phase 收尾若 `current_stage` 未变更，视为失败并报错，不得静默返回。
- 现有 git commit-msg hook `check-pdlc-state-sync.sh` 保持不动，作 git 层兜底。
- 供 stuck 检测：外层循环比对前后两次 `last_phase_result.at` 与 `current_stage`，未推进即判 stuck 停机。

### E. `/pdlc-loop-next`（★，新命令 Layer 3）

- **新增** `skills/pdlc-loop-next/SKILL.md`：只读 `<ID>.json` 的 `current_stage` / `next_step`，**仅打印下一条应执行的命令名**，机器可消费。
- **输出契约（安全关键）**：输出**必须**是以下固定白名单中的**单个 token**，不含任何散文：
  ```
  pdlc-tdd | pdlc-implement | pdlc-review | done | blocked
  ```
  只覆盖机械收敛段；到达 `review_done` 或更后 → 输出 `done`，**绝不**输出 `pdlc-ship` / `pdlc-deploy`（发布永远留人）。下游 helper **必须校验** `$CMD` 属于该白名单再执行，否则中止——避免模型多打散文把脏东西拼进命令行。
- 参考 helper（写进 §5.F Runbook 与 usage-guide，含校验）。**注**：v1.2.1 起净化步骤已加固（去反引号 + 抽取白名单 token，容忍空白/标点/包裹），以最新实现 `skills/pdlc-loop-next/SKILL.md` 为准：
  ```bash
  RAW=$(claude -p "/pdlc-loop-next $ID")
  CMD=$(printf '%s' "$RAW" | tr '`' ' ' | tr -s ' \t' '\n' | grep -xE '(pdlc-tdd|pdlc-implement|pdlc-review|done|blocked)' | head -1)
  case "$CMD" in
    pdlc-tdd|pdlc-implement|pdlc-review)
      claude -p "/$CMD $ID --autonomous" ;;
    done)    echo "✅ 已到 review_done，交人工决定是否 /pdlc-ship"; break ;;
    blocked) echo "⛔ 需人工介入"; break ;;
    *)       echo "❌ 非法命令（原始输出：$RAW）"; exit 1 ;;
  esac
  ```
- `produces: []`（只读）；自身不改状态，不含 `--autonomous` 语义。

### F. `/pdlc-loop-run`（○，新命令，收敛引擎）

把收敛循环烧进插件，**只覆盖机械收敛段 `tdd→implement→review`**，自动推进到 `review_done` 或 blocked。prd/design 与终审 ship 仍显式留人（呼应 §4.3）。

> **终态即 `review_done`（设计如此，非缺陷）**：循环把「代码就绪、可发布」这一段全自动跑完就停，剩下的 ship/deploy 是一道**刻意的人工闸门**——发布属打 tag / bump 版本 / 触发 CI / 上生产的不可逆·外发操作，是 loop 工程五层模型里「不可逆动作前的 human checkpoint」。停在 review_done 是循环**成功到达终点**，不是「循环跑不起来」。价值分配：PRD→设计→TDD→实现→评审的机械劳动全自动化，人只做最后一次 go/no-go。`--autonomous` 永不触发发布。

**默认推荐：外部 bash Runbook（真进程隔离）**。在 `docs/usage-guide.md` 附一段 bash 驱动模板，用独立进程 `claude -p "/pdlc-<stage> $ID --autonomous"` 逐轮跑——每轮全新进程 = 真 fresh context，最可信，适合长跑 / 过夜 / 多 feature 并行（配 git worktree）。`/pdlc-loop-run` 可打印该脚本。

**便捷选项：插件内 Task 版**。`/pdlc-loop-run` 作为外层 skill 持有循环状态，每个 stage 通过 Task 工具派发给一个 subagent（context 相对隔离），返回后读 `last_phase_result` 决定 推进 / 停 / block。开箱即用，适合短收敛；长跑仍建议走外部 Runbook。

**共同的护栏**：
- **迭代上限**：收敛段是线性前进 `tdd→implement→review`（3 段）。上限设 **4**——3 段正常执行 + **1 段容错余量**，专供「首轮 block、人工介入修好后从原 stage 续跑一次」。超过即停机（防病态空转）。不给更多余量，因为 §2.3「只前进不回炉」已排除同一 stage 反复重跑。
- **fail-stop**：某 stage `ok=false` 且不可自动修复 → 立即停，不重跑同一 stage。
- **stuck 防护**：某 stage 执行后 `current_stage` 未推进（违反 D）→ 停。

**与 IRON LAW 调和**：单个 stage 内「修复单次不递归」不变；循环只在**不同 stage 间前进**，**永不原地回炉**。review 段的自动修复仍在 review 内一次性完成，不回弹到 implement。故「循环」= 前进 + 失败即停 + 上限，不是「重试同一步」。

### G. 模型路由 + 预算护栏（○，省额度杠杆）

- Layer 1/2 skill frontmatter 增加建议档位（**可选字段，不进 required**）：
  ```yaml
  recommended_model: sonnet    # prd/design→opus；tdd/impl/review→sonnet；lint/格式化→haiku
  recommended_effort: medium
  ```
- `/pdlc-loop-run` 内派 Task subagent 时据此选模型；外部 bash 版据此拼 `claude -p --model $MODEL`。
- **预算护栏**（文档层）：Runbook 模板强制 `--max-budget-usd` + 迭代上限。自主循环持续烧 token（连续跑 Sonnet 量级约每小时数美元），护栏是一等公民而非可选装饰。

### H. `pdlc-status --json` + retro 消费（△）

- `skills/pdlc-status/SKILL.md` 增加 `--json` 机器可读输出，供 CI / 循环 `jq` 消费。
- △ `pdlc-retro` 统计「每 feature 循环轮数 / token 成本 / 一次过率」，反哺 prompt 与 check 质量。
- △ autonomous 产物在 `history` 标 `origin: "loop"`。

---

## 6. 状态机 schema 变更（before → after）

新增字段（全部向后兼容，旧文件缺失时视为默认）：

```diff
  {
    "feature_id": "...",
    "current_stage": "impl",
+   "run_mode": "autonomous" | "interactive",
    "history": [
      {
        "stage": "impl",
        "done_at": "...",
        "produced": [...],
        "self_audit": { "passed": 3, "failed": 0, "manual": 1 },
+       "auto_decisions": [ { "point": "测试已绿是否继续", "chose": "继续", "at": "..." } ]
      }
    ],
+   "last_phase_result": {
+     "stage": "impl", "ok": true, "advanced_to": "review",
+     "checks": { "tests_pass": true, "coverage_pass": true, "lint_clean": true },
+     "self_audit": { "failed": 0 },
+     "blocked_reason": null, "run_mode": "autonomous", "at": "..."
+   },
    "relations": { ... },
    "next_step": "pdlc-review"
  }
```

---

## 7. 安全边界（本方案自身的安全原则）

以下每条独立成立，是本方案不可协商的执行约束：

1. **破坏性操作永远留人**：ship / deploy / 打 tag / 触发 CI / force-push / DROP 等不可逆操作，即使带 `--autonomous` 也必须人工二次确认；`--autonomous` 对它们无效。
2. **零新增 CI**：本方案**不新增任何 GitHub workflow**；所有 check 走本地 `test-commands.yml`。`/pdlc-loop-run` 不触发 CI。
3. **预算护栏内建**：自主循环必须配 `--max-budget-usd` + 迭代上限，防失控烧 token（G）。
4. **不在主分支干活**：外部 Runbook 默认在 git worktree 里跑，天然隔离，产物经 PR 合入。
5. **PR 按功能点走**：本方案按 §9 拆 3 个 PR，一个功能点一个 PR，不零碎开 PR。

---

## 8. 改动点清单（file-level）

### 新增文件

| 文件 | 内容 | 批次 |
|---|---|---|
| `references/templates/prompts/noninteractive.md` | `--autonomous` 契约共享片段 | ★ |
| `references/templates/test-commands-template.yml` | test-commands 模板 | ★ |
| `skills/pdlc-loop-next/SKILL.md` | 打印下一条命令（白名单输出契约） | ★ |
| `skills/pdlc-loop-run/SKILL.md` | 收敛循环引擎 | ○ |
| `docs/decisions/0001-loop-engineering-integration.md` | 本方案（已建） | — |

### 修改文件

| 文件 | 改动 | 批次 |
|---|---|---|
| `references/templates/prompts/state-update.md` | schema 增 `last_phase_result` / `run_mode` / `auto_decisions[]` | ★ |
| `references/templates/prompts/iron-law.md` | 加第 6 条「状态必推进」 | ★ |
| `skills/pdlc-implement/SKILL.md` | `@include noninteractive`；改绿灯确认点（:37）；写 `last_phase_result`（真跑 check） | ★ |
| `skills/pdlc-tdd/SKILL.md` | 从 test-commands 取 check；写 `last_phase_result` | ★ |
| `skills/pdlc-review/SKILL.md` | 「需人工确认」项在 autonomous 下的处置；写 `last_phase_result` | ★ |
| `skills/pdlc-prd/SKILL.md`、`skills/pdlc-design/SKILL.md` | 关键取舍点新增「不猜→block」分支 | ○ |
| `skills/pdlc-fix/SKILL.md`、`skills/pdlc-feature/SKILL.md` | 本就全自动，补哨兵 + `last_phase_result` | ○ |
| `skills/pdlc-ship/SKILL.md`、`skills/pdlc-deploy/SKILL.md` | 显式声明 `--autonomous` 不绕过破坏性确认 | ★ |
| `skills/pdlc-bootstrap/SKILL.md`、`skills/pdlc-adopt/SKILL.md` | 生成 `docs/00_standards/test-commands.yml` | ○ |
| `skills/pdlc-standard/SKILL.md` | 认 test-commands.yml 为 00_standards 产物 | ○ |
| `skills/pdlc-status/SKILL.md` | 加 `--json` | △ |
| Layer 1/2 各 skill frontmatter | 加 `recommended_model` / `recommended_effort`（可选） | ○ |
| `tests/frontmatter-check.sh` | 纳入新 skill 校验；技能计数 33→35 | ★ |
| `CLAUDE.md` / `README.md` / `README.zh-CN.md` / `docs/usage-guide.md` / `plugin.json` | 「33 个」改「35 个」；补 Target-project contract（test-commands.yml + 新 state 字段）；usage-guide 写 loop 契约 / `--autonomous` / `pdlc-loop-*` / 哨兵 / Runbook | ★ |
| `VERSION` / `.claude-plugin/plugin.json` / `CHANGELOG.md` | 版本 bump（三处一致） | ★ |

> 计数说明：新增 `pdlc-loop-next` + `pdlc-loop-run` = 33 → **35**。

---

## 9. 实施计划

作为**单个 PR** 一起落地，发布为 **v1.2.0**（33 → 35 skills）：

| 批次 | 内容 | 达成 |
|---|---|---|
| **本 PR（v1.2.0）** | A 非交互契约 + B `last_phase_result` + C test-commands + D 推进不变式 + `/pdlc-loop-next` + `/pdlc-loop-run` 收敛引擎（Runbook + Task 版）+ G 模型路由（`recommended_model`）+ 连带文档/测试/版本 | 让循环「能跑、能停、判得准」并把引擎烧进插件 |
| **后续** | H `pdlc-status --json` + retro 消费循环数据 + `origin: "loop"` 留痕 | 可观测性与复盘 |

**验证前置**：合并前，用一个最小示例项目跑通「autonomous 推进 `tdd → implement`，遇 block 停机」的端到端 demo，贴出 `jq` 读 `last_phase_result` 的实际输出自证。此为**运行时行为验证**——结构性测试（frontmatter / smoke / shellcheck）覆盖不到 skill 的真实运行行为。

---

## 10. 验收标准（怎么证明「能跑、能停、判得准」）

- **能跑**：`claude -p "/pdlc-implement $ID --autonomous"` 在无人应答下不空转、不乱猜，走完并写 `last_phase_result`。
- **能停**：构造一个 PRD 关键取舍缺口，autonomous 下命令写 `blocked_reason` 且 `ok=false`，外层 `jq` 判停成功。
- **判得准**：`checks.tests_pass` 与真实 `test-commands.unit` 退出码**一致**（故意造一个失败测试，验证 `ok=false`，证明不是模型自评虚报）。
- **不空转**：造一个「stage 未推进」场景，第 6 条门禁报错、`/pdlc-loop-run` 迭代上限停机。
- **边界**：`--autonomous` 下 `/pdlc-ship` 仍要求人工确认（Q3）。

---

## 11. 开放问题（待定稿）

1. **Task 版 fresh context 的可靠性**：Task subagent 的 context 隔离程度取决于 Claude Code 实现。本方案已把外部 bash Runbook 定为长跑默认（§5.F），Task 版仅作短收敛便捷选项——是否够？
2. **流程性确认点的默认值定义**：autonomous 下「按默认前进」的默认值由谁、在哪定义？是否需要每个确认点在 skill 里显式声明其 autonomous 默认，避免隐式猜测？
3. **test-commands.yml 迁移**：老项目里 check 命令可能散在各自约定/脚本里，如何平滑迁移到 `test-commands.yml` 并避免两处不一致？
