# 0005 · pdlc 的自动化测试与质量保障能力

- **状态**：Accepted（设计已定，分阶段实现待接手）
- **日期**：2026-07-22
- **作者**：kanfu-panda

---

## 1. 背景与目标

pdlc 现在**已经在编排自动化测试**：`pdlc-tdd`（测试先行 / 红灯门）、`pdlc-implement`（跑
`docs/00_standards/test-commands.yml` 的 unit/coverage/lint、checks 取自真实退出码）、`pdlc-e2e`，
以及那条贯穿全局的命门——**checks 只认命令退出码，绝不用模型自评**。

但两块能力仍缺，本 ADR 定下设计与实现顺序：

- **A · pdlc 测自己**：目前 `tests/*.sh` 只验**结构**（frontmatter / 无 `@include` 残留 / denylist /
  install smoke / dry-run 映射护栏），**不验行为**——skill 真跑时契约有没有守住（红灯门真拦、
  checks 真来自退出码、loop 真收敛不越发布闸）。这些至今靠**人工**逐次验证（见 ADR 0003 §6.1、
  ADR 0004 §2 的手工准入闸）。
- **B · pdlc 给用户项目的质量能力**：从"单功能 tdd/e2e"升级为**常设的质量闸门 + 报告**——
  声明质量目标（如单测覆盖率 ≥ 90%、E2E 覆盖全部核心业务流程），**自动化运行、及时出报告、由人确认**。
  这是**终极目标**：有效、可核对地保障产品质量。

**核心洞察（让这件事变得可行）**：**pdlc 异常地"可测"，因为它把状态外化到磁盘。** 一般 AI 系统难测在于
输出是散文、非确定；但 pdlc 的哲学就是"产物落盘、状态机记录一切、checks 来自真实退出码"。所以所有测试
与报告都**只断言确定性残渣**（状态机 JSON / 生成的文件 / 退出码 / 覆盖率工具的真实数字），绕开 AI 非确定性。
一个自洽的叙事：**pdlc 用它逼用户测代码的同一套纪律来测自己、来保障用户的质量。**

---

## 2. 三层拼图与实现顺序

| 层 | 是什么 | 作用 |
|---|---|---|
| **A** pdlc 自身行为 evals | 测 pdlc 自己（行为契约）；分 **A-det**（桩驱动·免费·常跑）与 **A-live**（真模型·发版前），判据见 §3.4 | 护城河 + 让 B1/B2 每次改动都被证明 |
| **B1** `/pdlc-test-setup` | 立测试地基（test-commands.yml + 骨架） | 一次性，让"退出码地基"turnkey |
| **B2** 质量闸门 + 报告 | quality-targets.yml + `/pdlc-quality` + 本地钩子 + 报告 + 发布挂钩 | **日常保障产品质量（终极目标）** |

**顺序：A 先行（最小步即可），B1 与 B2 的先后按目标项目现状取舍。** 理由：A 先落地，之后 B1/B2 每加一样都
**写个 eval 断言它真管用**（复用 A 的 harness）。B2 真正依赖的地基是 `test-commands.yml` **存在且真实**——
已手工立好该文件的项目可直接上 B2、B1 后补；从零接入的项目才必须先 B1。每层为上一层兜底。

---

## 3. A · pdlc 自身行为 evals（先做）

### 3.1 三层测试金字塔
```
结构层（已有）    无需 AI、秒级、随便跑        ← tests/*.sh：frontmatter/denylist/install/dry-run 映射护栏
行为层·A-det（新） 无需 AI（桩驱动）、秒级、常跑  ← evals/：由确定性代码执行的契约（loop 驱动控制流 / 护栏）
行为层·A-live（新）需真模型、按需跑、发版前      ← evals/：由模型遵守 SKILL.md 正文执行的契约（诚实 checks / 红灯门）
```
（A-det / A-live 的分界线与分拣见 §3.4——**这条线不是"契约重不重要"，而是"契约由谁执行"**。）

### 3.2 行为层设计（`evals/`）
1. **fixture 项目** `evals/fixtures/<场景>/`：最小但真实的预置项目（把此前手搭的沙盒固化）。至少含（**档位见 §3.4 分拣表**）：
   - `honest-checks`【A-live】：`test-commands.yml` 里 `unit` 恒失败(exit 1) / `lint` 恒通过(exit 0)，状态机停在
     `next_step=pdlc-implement`。**判别断言**：跑 `按 pdlc implement <id> --autonomous` 后，状态机
     `last_phase_result.checks == {tests_pass:false, lint_clean:true}`——**一真一假的组合只有真跑两条命令才写得出**，
     **对该判别式抗虚报**（是回归守卫，不是"模型永不虚报"的证明）。此即 ADR 0003 §6.1 / 0004 §2 的准入闸场景，现固化为可复现 eval。
   - `red-light-gate`【A-live】：无对应测试时跑 `pdlc-implement` → 中止、`current_stage` 不变。
     （守卫写在 `skills/pdlc-implement/SKILL.md` 的「PDLC 前置守卫」正文里、**由模型执行**，故桩测不了——见 §3.4。）
   - `loop-convergence`【A-det 桩版控制流 + A-live 真收敛】：`docs/.pdlc-state` 停在 tdd 完成，跑
     `adapters/codex-loop-run.sh` → 收敛到 `review_done`、**绝不推进到 ship**、退出 0；history 出现 `impl`/`review`。
   - `guardrails`【A-det】：构造 fail-stop / stuck-stop / max-steps 场景，断言对应退出码。
2. **声明式场景**：每个 eval 声明 `setup(fixture + 初始状态机) → action(跑哪个 skill/驱动 + args) →
   assert(对结果状态机 / 文件 / 退出码断言)`。断言**只碰确定性残渣**，容忍 AI 散文差异。
3. **runner** `evals/run.sh [--platform claude|codex] [--only <场景>]`：拷 fixture 到 temp → 经
   `claude -p "..."` 或 `codex exec -C <dir> -s workspace-write "..."` 跑 → 读回状态机断言。
   **同一份 eval 两平台各跑一遍**——正好把"跨工具状态延续"与"每平台都过 §6.1"变成可重复断言。
4. **成本纪律（项目 CI 纪律）**：**A-live 不进 CI**（要模型 + 烧钱），发版前 maintainer 手动跑；fixture 最小、
   reasoning 用 low。**A-det 与结构层同性质**（免费、确定性），进本地钩子常跑、亦不进 CI（项目 CI 只在 release tag 触发）。
   判据只有一条——**契约由确定性代码执行的进 A-det，由模型遵守正文执行的才进 A-live**（§3.4）。

### 3.3 A 的表现
- `evals/` 目录 + `EVALS.md`（说明两档 A-det / A-live、分档判据、怎么跑、**成本账**——A-live 每轮实际几个模型 turn，见 §7）。
- ADR 0003 §6.1 / 0004 §2 的**一次性手工准入闸，升级成 codified eval**——"过准入闸"从此 =
  `evals/run.sh --only honest-checks --platform codex`，可复现。
- `pdlc-ship` 发版清单加两步：**A-det 全绿 = 硬闸**；**A-live 跑 `--repeat 3` 并贴结果 = 建议性证据**
  （不因 flake 卡发布，见 §3.4 失败语义）。
- README 放一张**"行为契约已验"表**（红灯 ✓ / checks 诚实 ✓ / loop 收敛 ✓ · Claude + Codex）——
  对开源工具是强信任信号。**此表必须由 runner 生成 + 带时间戳/commit SHA**，且**每格标注档位**
  （A-det = 任何人可复现；A-live = 需模型额度、Codex 栏还需 provider 凭证，见 §6）（防腐见 §7）。

### 3.4 两档拆分：A-det（免费·确定性·常跑）vs A-live（真模型·发版前）⭐

**让 A 真能落地的关键洞察：行为层里有一部分契约根本不需要真模型。** 把模型调用换成一个**桩（stub）**——一个吐预置状态机 JSON 的假命令——就能确定性、零成本地测**驱动/harness 逻辑本身**（`tests/adapter-codex-loop-run-check.sh` 已用 codex 桩验证护栏，此模式直接复用）。

**分界线不是"契约重不重要"，而是"契约由谁执行"** ⭐：

- 契约由**确定性代码**执行（bash 驱动、jq 映射、退出码判定）→ 桩掉模型仍能测 → **A-det**
- 契约由**模型读 SKILL.md 正文遵守**执行（这是 pdlc 的主要机制）→ **桩掉模型 = 桩掉被测对象本身** → 只能 **A-live**

据此分拣（含一处纠正）：

| fixture | 契约执行者 | 档位 |
|---|---|---|
| `honest-checks` | 模型 | **A-live** |
| `red-light-gate` | **模型**——守卫是 `skills/pdlc-implement/SKILL.md`「PDLC 前置守卫」的正文指令 | **A-live**（早期草案曾误归 A-det） |
| `loop-convergence` | bash 驱动（`adapters/codex-loop-run.sh`）+ 每步推进靠模型 | 桩版控制流 → **A-det**；真收敛 → **A-live**（大版本前） |
| `guardrails` | 纯 bash | **A-det** |

**据此收敛 A-det 的口径（诚实计量）**：A-det 覆盖的**不是"行为契约的大头"，而是 loop 驱动这一块**——收敛控制流 + 护栏退出码，且与现有 `tests/*.sh` 已有重叠。**A 的净新增价值更集中在 A-live 的两个 fixture**（`honest-checks` / `red-light-gate`）。免费档能白拿多少，取决于有多少契约落在确定性代码里，而非取决于我们希望它有多少。

**同一条契约在两个实现上可测性不同（别混用绿灯）**："绝不自动 ship"在 **Runbook 版**（`codex-loop-run.sh`）由 bash 终态判定执行 → A-det 可证；但在 **Claude Task 版 `pdlc-loop-run`** 里写在 SKILL.md 正文、由模型执行 → 桩证不了，只能靠 A-live / 真机。**不可拿前者的绿灯宣称后者已验。**

**失败语义 / flake 政策**：
- A-det 失败 = **契约真红灯**（确定性、无 flake）→ 可作**硬 blocker**，进 pre-push 本地钩子常跑。
- A-live 失败**可能是模型抖动（限流/拒答/超时）而非契约破坏** → A-live 是**发版前的建议性证据、非自动硬闸**；瞬时失败允许重跑，连续失败才升级为"契约疑似回归"人工查。**绝不因 A-live flake 卡死发布。**

**A-det 的边界（防"桩掉模型掩盖真 bug"）**：A-det 验证的是 **harness 逻辑**——"给定合法的模型输出，驱动的控制流正确"。它**结构上测不了模型行为本身**（真模型会不会中途卡死、会不会写出非法状态转移）——桩喂的是预置的合法输出，恰好旁路了模型可能出错的那一段。因此 **A-det 全绿 ≠ 收敛性已在真模型上成立**；模型侧的真实性只能来自 A-live——`honest-checks` 覆盖"真模型单步写出诚实 checks"、`red-light-gate` 覆盖"真模型真的按正文守卫中止"。**全环收敛探针**（真模型多步连跑到 `review_done`）成本高一个量级，定位为**大版本发布前手动跑一次**、不进每版清单（此前已有一次真机端到端验证，见 ADR 0004）。

**A-live 的重复与失败分类（把单发探针变成统计可信的探针）**：runner 支持 `--repeat N`（默认 1，发版前建议 3），失败分两类——**环境抖动**（超时/限流/拒答，无状态机产出）→ 重跑、不计失败；**契约破坏**（有状态机产出但 checks 与判别式不符）→ 立即红。以多数通过为结论，单次抖动不误报"契约回归"。

---

## 4. B1 · `/pdlc-test-setup`（立测试地基）

一个 Layer 3 新命令（36 → 37），给一个项目**一键立起测试骨架**：

- **生成 `docs/00_standards/test-commands.yml`**（选配 unit / coverage / lint / e2e 命令，达标线写死在命令参数里）。
- 选配并接好测试 runner + 覆盖率工具 + lint（按项目语言探测：cargo / pnpm+vitest / pytest 等）。
- 脚手架测试目录结构，接 pre-commit / pre-push 钩子跑基础 check。
- 天然接 `pdlc-adopt`（老项目）与 `pdlc-bootstrap`（新项目）。可附带轻量"老项目特征化测试回填"到覆盖率底线。

**它与 B2 的先后（对齐 §2，非硬顺序）**：pdlc 的命门（"checks 来自 test-commands.yml 的真实退出码"）
**依赖该文件存在且真实**，而现在没有任何东西帮你把它立起来——B1 把整个"退出码地基"变成 turnkey。
但这**不等于 B1 必须先于 B2**：已手工立好 `test-commands.yml` 的项目（含 B2 的首批 dogfood 靶子）
可直接上 B2、B1 后补；**只有从零接入的项目才必须先 B1**。

**诚实边界**：定位成"立地基 + 补底线"，**不吹"帮你生成全部测试"**（AI 生成的测试容易浅）；深度用例仍走 `pdlc-tdd`。

> **实现纪要**：已落地为 `skills/pdlc-test-setup/SKILL.md`（36 → 37 skills）。实现时把本节的设计收敛出一条
> **命门——「验证后再写」**：写进 `test-commands.yml` 的每条命令，必须先被真跑过一次、亲眼看到退出码；
> 跑不通的**留空并在报告里说明怎么补**，绝不写一条没验证过的命令。理由与本 ADR 的整体命门同源——
> 下游每个阶段的 `checks` 都从这个文件取命令，**一条"看起来对但跑不了"的命令比留空更坏**，
> 它会让所有 checks 静默失真，而 pdlc 的可信度正建立在这些 checks 是真的之上。

---

## 5. B2 · 质量闸门 + 报告（终极目标）

**质量是日常行为，不是一次性 setup。** B2 是一道常设闸门 + 报告，自动化运行、及时出报告、由人确认。

### 5.1 目标声明化（才可机器核对）
新增 `docs/00_standards/quality-targets.yml`（与 test-commands.yml 并列），把质量目标变成机器可读：
```yaml
coverage:
  unit: ">= 90%"                 # 达标线；数字来自真实覆盖率工具输出，不自评
e2e:
  policy: all-core-flows-covered
  core_flows:                    # 核心业务流程清单（唯一真源）
    - id: login
    - id: checkout
    - id: refund
lint: zero-warnings
```

### 5.2 诚实命门：把"E2E 覆盖全部核心流程"做成**机械核对**而非 AI 拍脑袋 ⭐
这是 B2 最关键的一处。覆盖率 ≥ 90% 好办（覆盖率工具直接给数字 + 退出码）。但"E2E 覆盖了全部核心流程"——
**若靠 AI 判断"我觉得覆盖了"，就破了 pdlc 那条命门（checks 只认客观事实、不认自评）。**

**必须有"流程 → 测试"的映射（以显式映射文件为主路径）：**
- **主**：一份显式 `docs/00_standards/e2e-flow-map.yml`（`flow id → 测试标识`）——**跨框架稳健**、单一真源、不依赖解析测试名。
- **辅（糖）**：可选约定测试名/标签带 flow id（如 `@flow:checkout`）自动回填映射；但跨 runner（pytest marker / vitest describe / cargo 测试名各异）解析脆弱，只作便利、不作依赖（同 ADR 0003 里"python 胜过 bash sed"的取舍）。
- 报告做**覆盖矩阵**：`core_flows × 是否有对应的通过 E2E`。缺一条 = 红。
- 这样"覆盖全部核心流"就从口号变成**可核对的矩阵**，且证据来自**真跑的 E2E 结果**，不是 AI 意见。

> ⚠️ **这条是 B2 成立的地基**：没有 flow→test 映射，"覆盖核心流"永远主观，保障不了质量。

**清单维护必须机械化——这是 B2 成立的第二个地基**（与 flow→test 映射并列）：
`core_flows` / `e2e-flow-map.yml` 若靠"有人记得改"来维护，必然腐烂；而腐烂的清单产出 **false-green**
（新增的核心流没进清单 → 矩阵全绿、现实有洞），把"我们不知道"伪装成"我们覆盖了"——**比没有闸门更坏，直接破命门**。
解法是把维护锚在 pdlc 自己的产物链上（PRD 本就被 pdlc 逼着落盘并保持最新，让它当 `core_flows` 的唯一上游真源）：
- **强制对账**：`/pdlc-quality` 每次运行都把 PRD（`docs/01_requirements/prd/`）的 P0/P1 流程与 `core_flows`
  做 diff，漂移即红（"PRD 流程 X 未进 core_flows"是**红灯项**，不是温柔提示）。
- **上游挂钩**：`pdlc-prd` / `pdlc-feature` 产出新 P0/P1 流程时，handoff 里提示补 `core_flows` 与映射。
- **降低首次摩擦**：`/pdlc-quality` 可从 PRD 自动抽 `core_flows` 草稿供人确认。
这样维护从"靠自觉"（必烂）变成"被产物纪律接管"——与 pdlc 可测的根因（状态外化到磁盘）是同一个哲学。

### 5.3 `/pdlc-quality`：跑 → 量 → 出报告 → 人确认
- 跑 test-commands.yml 的 coverage / e2e / lint（**真实退出码 + 真实覆盖率数字 + 真实 E2E 结果**，不自评）。
- 对照 quality-targets.yml：覆盖率达没达线、每条核心流有没有通过的 E2E、lint 干不干净。
- 产出报告落盘 `docs/07_reviews/quality/<日期>.md`：达标红绿表 + E2E 覆盖矩阵 + **趋势**
  （对比上一份报告，复用状态机 / `pdlc-retro` 那套）。
- **人确认**：报告是给人签字的（AI 只从真实数据生成报告，go/no-go 由人拍）——与"发布永远人工"一脉相承。

### 5.4 "自动化运行"怎么做到、又不依赖 CI
项目 CI 纪律：不上 `on: schedule`、不跑频繁 CI（CI 只在 release tag 触发）。**能本地全本地：**
- **pre-push 钩子**：每次 push 本地自动跑质量闸，不达标就拦 / 警告——"日常自动"且**零 CI 成本**。
- **按需**：`/pdlc-quality` 随时出全量报告。
- **发布挂钩**：`pdlc-ship` 读最近一份质量报告，不达标不让发（或要人显式 override）——把质量绑死在发布闸上。
- **要"每天一份"**：用户机器上的本地 launchd / cron 跑，报告进 git；**绝不**用 GitHub Actions `schedule`。

### 5.5 B2 的表现
- `docs/00_standards/quality-targets.yml`（声明目标）+ `docs/00_standards/e2e-flow-map.yml`（流程映射）。
- `/pdlc-quality` 命令（Layer 3）。
- `docs/07_reviews/quality/<日期>.md`（报告产物，可 git diff、可 trend）。
- pre-push 钩子 + `pdlc-ship` 读取。
- README / 产品页："质量闸门"叙事。

---

## 6. 非目标与诚实边界

- **不进 CI 跑行为 evals / 质量闸**（项目 CI 纪律）；自动化靠本地钩子 / 按需 / 发布挂钩 / 本地 cron。
- **不用 AI 判断替代客观数据**：覆盖率来自覆盖率工具、E2E 覆盖来自 flow→test 映射 + 真跑结果、checks 来自退出码。
  AI 只负责**生成报告**与**从 PRD 抽核心流草稿**，判定与放行由客观数据 + 人。
- **B1 不吹"生成全部测试"**；**B2 的 E2E 保障强度取决于 `core_flows` 清单与映射维护得多勤**——清单漏一条核心流，
  矩阵也照不出来（false-green），故 §5.2 的**清单维护机械化**（PRD 强制对账 + 漂移即红灯）是 B2 真正有效的前提，
  仅靠"降低摩擦、温柔提示"不够。
- **A-det 证不了模型侧行为**：它只证"给定合法模型输出、驱动控制流正确"；模型会不会真按正文守卫中止 / 中途卡死 /
  写出非法状态转移，只能由 A-live 证。**Claude Task 版 `pdlc-loop-run` 的"绝不自动 ship"由模型执行，A-det 的绿灯不覆盖它**（§3.4）。
- **vanilla OpenAI Codex 不在覆盖范围**（见 ADR 0003 实现纪要）；A 的 evals 面向已验证的 Codex 发行版 + Claude Code。
- **Codex 那条 eval 臂是"凭证门控"的**：`codex exec` 需 provider key，只有持凭证的 maintainer 能跑；README「行为契约已验·Codex」栏 ≠「任何人可复现」，须标注"由持 Codex 凭证的维护者跑于 <日期/SHA>"。A-det 那档无此限制（桩驱动、任何人可跑）。
- **加 skill = 全仓"36"计数涟漪**：B1 使 36→37、B2 的 `/pdlc-quality` 再 37→38；落地须同步 `ARCHITECTURE.md` / `GLOSSARY.md` / `CLAUDE.md` / `README(.zh-CN).md` / `docs/pdlc-methodology.md` 里所有硬编码"36"，以及 `tests/install-smoke.sh` 的计数断言。

---

## 6.5 反模式：把「我判断不了」当成「没问题」⭐（真项目验证所得）

本 ADR 通篇在防「主观判断冒充客观事实」。但 2026-07-29 在真项目（aim-quant）上验证 B1/B2 时，
**防它的机制自己犯了两次同一个错**，而且都不是实现疏忽、是设计层盲点。值得单列成检查项：

| 犯错的地方 | 机制以为的 | 实际情况 |
|---|---|---|
| PRD ↔ `core_flows` 对账 | PRD 无 P0/P1 标记 → 提取空集 → **无漂移 ✅** | 那份 PRD **整份没进闸门视野**（已上线主链路最容易栽） |
| 红灯守卫定位测试 | 写死路径清单里找不到 → **项目没有测试** | 测试只是**不在预期位置**（单体 `backend/tests/`；Rust 更是写在源文件里） |

**共同结构**：判定逻辑遇到「输入不在我的认知范围内」时，**静默落到了乐观的那一侧**。
这比明确的错误危险得多——它不报警，看起来一切正常。

**据此定一条通用检查项**：本 ADR 下的任何闸门 / 判定，都必须能区分三态，而非两态：

```
通过（有证据）  ·  未通过（有证据）  ·  无法判定（缺证据）
```

**第三态必须显式呈现，且绝不并入第一态。** 具体落法：
- 对账：无优先级标记的 PRD → 单列「不可判」告警，对账项不得判 ✅
- 守卫：runner 装不上 / 语言不认识 → 报「无法确认本功能是否有测试」并交还人类，不默认放行
- 质量报告：命令留空 / 无法执行 → 记「未测量」，**不得按通过处理**
- 新增任何闸门时先自问：**"我什么都没找到"和"确实没有"，我分得开吗？** 分不开就先把这一步做出来。

---

## 7. 真正落地：最小第一步与防腐

**最小可跑第一步（先证明 A 立得住，再谈框架）**：不先搭 `evals/` 全框架，而是先做**一个** `honest-checks` 可跑脚本——fixture（`unit` 恒 exit 1 / `lint` 恒 exit 0）+ 一段 `run.sh --only honest-checks`：拷 fixture 到 temp → 经 `claude -p`（选配 `codex exec`）跑一步 implement → 读回状态机断言判别式。它一箭三雕：① 立刻把 ADR 0003 §6.1 / 0004 §2 的**一次性手工准入闸变成可复现命令**（今天就有价值）；② 是整个 A 档能否成立的最小证明；③ 成本约一个 turn。

**第二步应是 `red-light-gate`，不是 A-det**（§3.4 分拣的直接推论）：它同属 A-live、**复用同一个 runner**——同一套
"拷 fixture → `claude -p` / `codex exec` → 读回状态机断言"的 harness，只多一个 fixture，**搭建的边际成本近乎零**，
却补上第二条模型侧契约。
> ⚠️ "近乎零"指**搭建**成本，**不是运行成本**：它运行时仍是一次真模型 turn——A-live 每轮 =
> `honest-checks` + `red-light-gate` **两个 turn**，`--repeat 3` 即**六个**。量级完全可接受，但 `EVALS.md`
> 必须把这笔账写明，别让"近乎零"被误读成"跑起来也免费"。

**之后**再做 A-det（`guardrails` / loop 控制流）：**直接扩展 `tests/` 里现成的桩测试，不另起一套 harness**
（`tests/adapter-codex-loop-run-check.sh` 已在用 codex 桩）——既然 A-det 本就与 `tests/*.sh` 重叠，
让桩测试有两个家只会多一套要防腐的机制。价值次之，排在 A-live 两个 fixture 之后。

**防腐（这决定 A 是资产还是负债）**：
- **README「行为契约已验」表由 runner 生成 + 带时间戳/commit SHA**——过期的表要**看得出过期**（有日期），而非静默变谎。手工维护的"已验表"必然腐烂。
- **A-det 进 pre-push 本地钩子常跑**（确定性、免费）→ harness 逻辑契约永不腐；A-live 靠发版清单人工触发。

**Dogfood 的诚实限制**：pdlc-skills 自身是 bash 插件、**不是被单测的应用**，B1/B2 无法拿本仓自测。**A 的 `evals/fixtures/` 恰好是 B1/B2 唯一现成的 dogfood 靶子**——这反向印证"A 先行"：先手搭 fixture（含真实 `test-commands.yml`），正好成为 B1「该生成什么」的规格。

**B2 的启动条件（2026-07 更新：需求门已满足，改为技术前置门）**：B2 曾被门控为"待真实用户提出质量闸需求再上"（YAGNI）。该门**已满足，且需求来源是 dogfood 而非外部调研**——维护者本人与同事在多个实际项目里日常使用 pdlc，正手工重复 B2 要自动化的事（拉覆盖率达标、建 lint 门禁、出达标报告），这些项目即 B2 的第一批 dogfood 靶子。**自用自提是最实的需求信号**（真用得着才会痛，且交付后立刻有人验收）；同时认清它的边界——dogfood 证明"我们需要"，不证明"通用用户需要"，故 B2 仍按 §5.2 的机械化标准做，**不因"自己人用"降标准**。B2 的剩余门槛不再是"有没有人要"，而是**技术前置**：§5.2 的"清单维护机械化"（PRD 强制对账 + 漂移红灯）必须随 B2 第一版一起落地，做不到就不上——手工维护的映射必烂，烂掉的映射产出 false-green，破命门。**A 依然先行**（可复现准入闸 + README 已验表，成本只是 B2 零头），但 B2 无需再等待外部需求信号。

---

## 8. 与既有 ADR 的关系

| ADR | 关系 |
|---|---|
| [0001 Loop 工程](0001-loop-engineering-integration.md) | loop-run 的护栏是 A `loop-convergence` / `guardrails` eval 的被测对象 |
| [0003 多平台适配](0003-multi-platform-adapters.md) | §6.1 状态完整性准入闸 → A 固化为 `honest-checks` eval，可复现、跨平台 |
| [0004 Codex loop-run](0004-codex-loop-run.md) | §2 手工准入闸结果 → A 的 `honest-checks` / `loop-convergence` eval |

---

## 9. 一句话小结

**pdlc 用它逼用户测代码的同一套纪律来测自己（A）、并把"日常质量保障"做成常设闸门（B2）。** 全程守一条命门：
**一切判定来自客观数据（退出码 / 覆盖率数字 / flow→test 映射 + 真跑），AI 只生成报告，放行由人。** 顺序：
A 先行（最小步），B1/B2 按目标项目现状取舍，每层为上一层兜底；自动化靠本地钩子而非 CI（项目 CI 纪律）。
测自己这一层还多守一条：**分档只看"契约由谁执行"——确定性代码执行的可用桩免费测（A-det），模型遵守正文执行的
只能真跑（A-live）**；桩的绿灯绝不冒充模型侧的绿灯。终极目标——**可核对、及时、由人确认地保障产品质量。**
