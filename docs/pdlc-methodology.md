# PDLC 通用方法论（平台中立）

> **这是什么**：pdlc-skills 的**平台中立内核**——不依赖任何特定 AI 编程工具的 PDLC 方法论、
> 状态机契约与产出契约。任何能读写文件、能跑命令的 AI 编程 agent（Claude Code、Codex、
> Cursor、Windsurf、VS Code + Copilot、Cline …）都能照此驱动完整的产品开发生命周期。
>
> **定位（见 [ADR 0003](decisions/0003-multi-platform-adapters.md)）**：本文档是多平台策略里的
> **Tier 1「地板」**——覆盖所有工具、优雅降级。**Claude Code 集成最全（Tier 2）**，另有 36 个
> `/pdlc-*` 斜杠命令 + 状态栏 + 自主收敛引擎，体验最全（见 [ARCHITECTURE.md](ARCHITECTURE.md)）。
> 本文档描述的是**两者共享的方法论内核**。

---

## 0. 怎么用这份文档

**核心心智**：工具只是可替换的**驱动器**，PDLC 的产物（状态机 + 文档）长在**你的项目里**、
不属于任何工具。所以同一个仓库今天用 Claude Code、明天用 Codex 接着推，状态**无缝延续**。

- **在 Claude Code 里**：直接用 `/pdlc-feature`、`/pdlc-prd`、`/pdlc-review` 等斜杠命令，本文档是它们的底层规格。
- **在其它工具里**：把本文档作为项目规则（`AGENTS.md` / `.cursor/rules/` / `.windsurf/rules/` /
  `.github/copilot-instructions.md` / `.clinerules/` 等），然后用**自然语言**驱动，例如：
  - 「按 pdlc 给这个功能跑一遍需求分析」→ 走 §6 的 **需求（PRD）** 阶段
  - 「按 pdlc 跑 TDD」→ 走 **测试先行** 阶段
  - 「按 pdlc 做实现」/「按 pdlc 评审」→ 对应阶段
  - 自然语言 → 阶段映射见 §8。

不论哪种入口，**§2 的 IRON LAW、§3 的状态机契约、§4 的目录契约是硬约束，不可绕过。**

---

## 1. PDLC 是什么

Product Development Life Cycle——把一个功能的开发切成有序、有硬门禁的阶段流水线：

```
需求(PRD) → 设计 → 测试先行(TDD 红灯) → 实现(绿灯) → 评审 → 发布 → 部署 → 复盘
```

- **功能流程**（feature）：走完整流水线，功能 ID 形如 `F<YYYYMMDD>-<HHMMSS>`。
- **缺陷流程**（fix）：原子修复走精简流程（定位 → 红灯复现 → 修复 → 验证），缺陷 ID 形如 `B<YYYYMMDD>-<HHMMSS>`。

每个产出阶段都：**先落文档 → 再进下一步**；**代码实现前测试必须已存在且红灯**；**每阶段自检后才交接**。

---

## 2. IRON LAW · 不可违反的硬门禁

以下规则为**不可协商**的执行约束，任何产出阶段都必须遵守：

1. **文件必须落盘**：所有带编号（功能 ID / 缺陷 ID）的文档，必须作为实际文件写入磁盘，**不可仅在对话中输出**。
2. **阶段必须落章**：每个阶段完成后必须在状态机 `docs/.pdlc-state/<feature-id>.json` 追加 `history`，不可跳过。
3. **测试必须存在**：进入实现阶段前，对应测试必须存在且处于**红灯**状态。违反则中止。
4. **自检必须执行**：交接前的自检为强制步骤，不得以「已经很好了」为由跳过。
5. **防循环**：修复为**单次**，不递归。无法自动修复的问题记录到报告，继续往下走。
6. **状态必推进**：成功执行某阶段后 `current_stage` 必须变更。收尾时若发现未推进，视为失败并报错，
   **不得静默返回**（防止外层循环拿滞后状态空转）。唯一例外：命中人工判断点主动 block 时，
   `current_stage` 保持不变，但必须写 `last_phase_result.ok=false` + `blocked_reason`。

> **违反任一条 = 立即中止当前阶段，输出违规详情，等待人工介入。**

---

## 3. 状态机契约（唯一真源）

每个功能一个 JSON 文件 `docs/.pdlc-state/<feature-id>.json`。它是「进行到哪、下一步、检查过没过、
是否卡住」的**唯一真源**——不猜、不解析散文。

```json
{
  "feature_id": "<F/B ID>",
  "feature_name": "<kebab-case>",
  "created_at": "<首次创建 ISO 8601>",
  "current_stage": "<当前阶段短名>",
  "run_mode": "interactive | autonomous",
  "history": [
    {
      "stage": "<阶段短名>",
      "done_at": "<ISO 8601>",
      "produced": ["<相对路径>", "..."],
      "self_audit": { "passed": 0, "failed": 0, "manual": 0 },
      "auto_decisions": [
        { "point": "<autonomous 下自动前进的确认点>", "chose": "<所选默认>", "at": "<ISO 8601>" }
      ]
    }
  ],
  "last_phase_result": {
    "stage": "<本次阶段短名>",
    "ok": true,
    "advanced_to": "<下一阶段短名 | null>",
    "checks": { "tests_pass": true, "coverage_pass": true, "lint_clean": true },
    "self_audit": { "failed": 0 },
    "blocked_reason": null,
    "run_mode": "interactive | autonomous",
    "at": "<ISO 8601>"
  },
  "relations": {
    "extends": [], "depends_on": [], "supersedes": [],
    "resolves": [], "conflicts_with": [], "relates_to": []
  },
  "next_step": "<下一跳命令名，如 pdlc-design；流程结束则为 null>"
}
```

**更新流程**：文件不存在 → 建初始结构；已存在 → 追加当前阶段到 `history`、更新 `current_stage` 与
`next_step`；用 `jq` 或等效工具保持格式化。更新失败（损坏 / 权限）**必须中止并报错**，状态机不可跳过。

### `last_phase_result`——循环判停的唯一真源

外层驱动只需读 `.last_phase_result.ok` 即可决定 继续 / 停止 / 交还人类。规则：

1. **`checks` 必须客观**：`tests_pass` / `coverage_pass` / `lint_clean` 全部来自**真跑命令的退出码**
   （命令取自 `docs/00_standards/test-commands.yml`，见 §7），**绝不用模型自评**。退出码 0 记 `true`、非 0 记 `false`。
   阶段语义不同则用对应键（如 TDD 段用 `{ "red_verified": true }` 表示红灯已验证）。
2. **`self_audit` 单列**：只放自检未通过数，**仅供参考，不作判停依据**。
3. **`ok` 定义**：本阶段全部 `checks` 通过且未命中 `blocked_reason` → `true`；否则 `false`。
4. **命名空间**：`advanced_to` = 下一阶段短名（= `next_step` 去掉 `pdlc-` 前缀）；到终态或无后续时 `advanced_to=null`。
5. **推进一致**：`ok=true` 时本阶段必须真的推进了 `current_stage`（呼应 IRON LAW #6）；
   `ok=false`（含 blocked）时 `current_stage` 不变、`advanced_to=null`、`blocked_reason` 写明原因。

---

## 4. 目标项目目录契约

PDLC 在**你的项目**里读写这套固定目录（缺失即创建）：

```
docs/
├── ARCHITECTURE.md              # 全系统总览（surface，就地编辑，history 走 git）
├── GLOSSARY.md                  # 项目术语表（surface）
├── 00_standards/                # 团队规范（surface）
│   ├── coding/                  #   编码规范（实现/TDD 阶段读）
│   └── test-commands.yml        #   客观检查命令的唯一来源（见 §7）
├── 01_requirements/prd/         # 各功能 PRD（ledger，一功能一文件，累积不覆盖）
├── 02_design/{api,database,architecture,ui-ux}/   # 各功能设计（ledger）
├── 03_development/              # 开发者手册（ledger）
├── 04_testing/{unit-tests,e2e-tests,defects,security,perf}/   # 测试产物（ledger）
├── 05_deployment/              # 部署文档（ledger）
├── 06_tasks/                   # 任务拆解（ledger）
├── 07_reviews/{doc,code,design,retro}/            # 评审记录（ledger）
└── .pdlc-state/
    └── <feature-id>.json        # 每功能状态机（见 §3）
```

**Ledger vs Surface**：ledger 记**事件**（累积、不就地改、一次一文件，如 PRD / 设计 / 评审）；
surface 记**状态**（单一文件、就地编辑、history 走 git，如 ARCHITECTURE / GLOSSARY / 00_standards）。

**产出文档顶部必须带 PDLC 追溯头**：

```
<!-- PDLC-TRACE -->
<!-- 功能ID: F20260326-090000 -->
<!-- 功能名称: user-auth -->
<!-- 阶段: 设计 -->
<!-- 前置文档: docs/01_requirements/prd/F20260326-090000-user-auth-prd.md -->
<!-- 创建时间: 2026-03-26T10:30:00 -->
```

---

## 5. 功能 / 缺陷 ID 分配

1. 取当前时刻：`date +%Y%m%d`（如 `20260717`）、`date +%H%M%S`（如 `122801`）。
2. 生成 ID：功能 `F<YYYYMMDD>-<HHMMSS>`、缺陷 `B<YYYYMMDD>-<HHMMSS>`（用执行时的**真实值**，严禁复制示例）。
3. **本地防撞**：若该 ID 已被占用（`docs/` 或 `docs/.pdlc-state/` 下已有同名前缀），重取 `date +%H%M%S`
   （生成本身耗时、通常已跨秒；仍同秒则 `sleep 1` 后再取，**不手算时分秒**，天然处理跨天边界）。
4. 从描述提取功能名关键词（英文小写 + 连字符，如 `user-auth`）。

> **为什么用时分秒而非当日序号**：多人 / 多 AI 并行时，各自取「当日序号 max+1」会分到相同编号、合并冲突；
> 用创建时刻的 `HHMMSS` 零协调也几乎不撞、合并零冲突。旧的 `F<日期>-<NN>` 序号 ID 仍可解析。

---

## 6. 每个阶段的四段式骨架

每个产出阶段都按这四段走：

- **段一 · 执行**：产出本阶段文档 / 代码（按 §4 落盘、带追溯头）。
- **段二 · 自检（强制）**：重读产出物，按本阶段质量清单逐项检查，勾选通过、标注未通过原因。
- **段三 · 修复（单次，不递归）**：可自动修复的直接修并回验一次；无法修复的记录到自审报告，**不再递归**，流程继续。
- **段四 · 交接**：更新状态机（§3）后，输出最终消息：

  ```
  ✅ <阶段名> 完成：<主要产出物路径>
  📊 自检：<通过数>/<总数> 通过（若有未通过，附要点）
  📦 状态快照：docs/.pdlc-state/<feature-id>.json
  👉 下一步：<下一阶段命令 / 自然语言指令>；若流程结束则注明「无后续」
  ```

**各阶段的自检要点（摘）**：

| 阶段 | 自检重点 |
|---|---|
| 需求(PRD) | 背景 / 目标用户 / 用户故事(≥3) / 功能清单(有优先级) / 验收标准(可度量) / 非功能 / 不在范围 |
| 设计 | 每条 P0/P1 功能有对应设计覆盖；API（URL 规范、请求/响应、统一响应、分页、鉴权）；DB（主键、索引、审计字段、迁移 DDL）；跨文档一致 |
| 测试先行 | 每条验收标准≥1 个测试用例；边界（空/最大/零值）与异常（401/403/404/409）；命名描述场景；**运行确认红灯** |
| 实现 | 不偏离设计；覆盖率达标；lint 快检；**运行确认绿灯** |
| 评审 | 设计一致性、验收标准逐条、代码质量、安全（SQL 注入/XSS/鉴权/敏感数据）、性能（N+1/分页/索引）；能修直接修、修后回验、失败回滚 |

---

## 7. 客观检查：`docs/00_standards/test-commands.yml`

阶段的 `checks` 必须来自**真跑命令的退出码**，命令集中声明在这一个文件里（单一真源）：

```yaml
# docs/00_standards/test-commands.yml（可选；缺失时退化为「据实说明无法客观验证」）
unit:     "<跑单元测试的命令>"      # 退出码 0 → tests_pass=true
coverage: "<跑覆盖率并卡阈值的命令>"  # 退出码 0 → coverage_pass=true
lint:     "<跑 lint 的命令>"        # 退出码 0 → lint_clean=true
e2e:      "<跑 e2e 的命令>"         # 可选
```

**绝不用模型自评填 `checks`**。命令缺失或无法跑时，如实在 `checks` / 报告里标注「无法客观验证」，
不伪造 `true`——这是「跨工具状态可信」的命门：多个平台的 agent 写同一份状态机，**最弱的那个一旦虚报就污染全部**。

---

## 8. 用自然语言驱动（无斜杠命令时）

其它工具没有 `/pdlc-*` 自动补全，用自然语言触发对应阶段即可。agent 读到指令后，**按本文档对应章节执行**：

| 你说 | 走的阶段 | 对应 Claude Code 命令 |
|---|---|---|
| 「按 pdlc 开个新功能：<一句话>」 | 全流程（PRD→…→评审） | `/pdlc-feature` |
| 「按 pdlc 修个 bug：<现象>」 | 缺陷精简流程 | `/pdlc-fix` |
| 「按 pdlc 写/看需求」 | 需求(PRD) | `/pdlc-prd` |
| 「按 pdlc 做技术设计」 | 设计 | `/pdlc-design` |
| 「按 pdlc 跑 TDD / 写测试」 | 测试先行(红灯) | `/pdlc-tdd` |
| 「按 pdlc 做实现」 | 实现(绿灯) | `/pdlc-implement` |
| 「按 pdlc 评审」 | 评审 | `/pdlc-review` |
| 「按 pdlc 看状态」 | 只读状态视图 | `/pdlc-status` |
| 「按 pdlc 发布」 | 发布（**始终人工确认**） | `/pdlc-ship` |

驱动时 agent 必须：读/建状态机（§3）→ 执行阶段四段式（§6）→ 客观检查（§7）→ 更新状态机并交接。
**链式推进靠状态机 `next_step` + 交接消息驱动，不靠记忆。**

---

## 9. 哪些能力仅 Claude Code（诚实标注）

本 Tier 1 内核在所有工具可用；下列是 **Claude Code 专属**，其它平台**没有等价物**，不夸大：

- **`/pdlc-*` 斜杠命令 + 自动补全**：其它平台用自然语言（§8）或该平台的原生命令文件（Tier 3 适配器，逐个平台加）替代。
- **状态栏片段**（`bin/pdlc-statusline.sh` + `/pdlc-settings`）：Claude Code 状态栏机制专属，见 [ADR 0002](decisions/0002-statusline-pdlc-status.md)。
- **自主收敛引擎**（`pdlc-loop-run` + `--autonomous` 契约）：可无人值守把 `tdd→implement→review` 推到 `review_done`。
  **并非绑死 Claude**——`--autonomous` 契约平台中立，`loop-run` 的「外部 Runbook 版」原理也可移植；真正 Claude-only
  的只有 `loop-run` 默认「Task 版」用的子代理派发机制。`pdlc-loop-next`（只读状态机、按 `next_step` 打印下一跳阶段）
  逻辑平台中立，**已作为独立只读查询投影到 Codex**（问「下一步该跑哪个阶段」）；缺的是 `loop-run` 引擎的各平台
  **循环驱动 harness** + 过状态完整性准入闸，属后续工作。当前其它平台可**手动逐阶段驱动**达到同样产物，只是没有
  内置的循环引擎与判停哨兵。
- **关系子系统自动化**（`/pdlc-relate rebuild` 生成 `_relations.json` / `_graph.md`）：状态机里的 `relations`
  块本身平台中立、可手维护，但反向索引与图的自动重建是 Claude Code 命令。

> 状态机数据结构本身**完全中立**：即便在只有 Tier 1 的平台上手工维护，切回 Claude Code 后其全套自动化照常识别、无缝接管。

---

## 10. 产出物语言策略

所有产出物（PRD、设计、代码注释、评审报告、测试计划、部署手册、changelog 等）：

1. **默认精确匹配对话语言**——用户用中文对话 → 产中文产物；用英文 → 产英文；用别的语言 → 用那个语言。**绝不无视输入固定用某语言。**
2. **显式指定优先**——用户为某产物指定语言（如「用英文写 API 设计」）时，该产物按指定语言。
3. **混合语言**——用户要不同产物用不同语言（常见：中文 PRD + 英文 API 文档给合作方），逐产物遵从。
4. **不确定**——无法可靠判断对话语言时，产第一份产物前问一次。

本策略作用于**内容**（散文、注释、标题），**不**推翻技术约定（英文变量名、英文 git commit subject、英文错误码等）。

---

## 附：跨工具状态延续（本方法论的第一性价值）

因为 `docs/.pdlc-state/` 长在项目里、结构平台中立，**换工具 = 换驱动器，状态不丢**：

- Claude Code 额度受限 → 切 Codex，读同一份状态机、从 `next_step` 继续。
- 团队里有人用 Cursor、有人用 Claude Code → 推同一个功能、共享一份状态。

**唯一前提**：每个平台都老实遵守 §2（IRON LAW）与 §7（客观检查不虚报）。任一平台写脏状态，
就污染所有平台共用的那份——这也是新平台接入前必须过「状态完整性准入闸」的原因（见 [ADR 0003 §6.1](decisions/0003-multi-platform-adapters.md)）。
