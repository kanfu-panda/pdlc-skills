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
| **A** pdlc 自身行为 evals | 测 pdlc 自己（行为契约） | 护城河 + 让 B1/B2 每次改动都被证明 |
| **B1** `/pdlc-test-setup` | 立测试地基（test-commands.yml + 骨架） | 一次性，让"退出码地基"turnkey |
| **B2** 质量闸门 + 报告 | quality-targets.yml + `/pdlc-quality` + 本地钩子 + 报告 + 发布挂钩 | **日常保障产品质量（终极目标）** |

**顺序 A → B1 → B2，不跳步。** 理由：A 先落地，之后 B1/B2 每加一样都**写个 eval 断言它真管用**（复用 A 的
harness）；B1 立地基，B2 的覆盖率 / E2E 都从这份地基跑；B2 长在地基上，成为常设闸门。每层为上一层兜底。

---

## 3. A · pdlc 自身行为 evals（先做）

### 3.1 两层测试金字塔
```
结构层（已有）  无需 AI、秒级、随便跑    ← tests/*.sh：frontmatter/denylist/install/dry-run 映射护栏
行为层（新增）  需 AI、按需跑、发版前     ← evals/：契约是否真被守住
```

### 3.2 行为层设计（`evals/`）
1. **fixture 项目** `evals/fixtures/<场景>/`：最小但真实的预置项目（把此前手搭的沙盒固化）。至少含：
   - `honest-checks`：`test-commands.yml` 里 `unit` 恒失败(exit 1) / `lint` 恒通过(exit 0)，状态机停在
     `next_step=pdlc-implement`。**判别断言**：跑 `按 pdlc implement <id> --autonomous` 后，状态机
     `last_phase_result.checks == {tests_pass:false, lint_clean:true}`——**一真一假只有真跑两条命令才写得出**，
     天然抗虚报（此即 ADR 0003 §6.1 / 0004 §2 的准入闸场景，现固化为可复现 eval）。
   - `red-light-gate`：无对应测试时跑 `pdlc-implement` → 中止、`current_stage` 不变。
   - `loop-convergence`：`docs/.pdlc-state` 停在 tdd 完成，跑 `adapters/codex-loop-run.sh` → 收敛到
     `review_done`、**绝不推进到 ship**、退出 0；history 出现 `impl`/`review`。
   - `guardrails`：构造 fail-stop / stuck-stop / max-steps 场景，断言对应退出码。
2. **声明式场景**：每个 eval 声明 `setup(fixture + 初始状态机) → action(跑哪个 skill/驱动 + args) →
   assert(对结果状态机 / 文件 / 退出码断言)`。断言**只碰确定性残渣**，容忍 AI 散文差异。
3. **runner** `evals/run.sh [--platform claude|codex] [--only <场景>]`：拷 fixture 到 temp → 经
   `claude -p "..."` 或 `codex exec -C <dir> -s workspace-write "..."` 跑 → 读回状态机断言。
   **同一份 eval 两平台各跑一遍**——正好把"跨工具状态延续"与"每平台都过 §6.1"变成可重复断言。
4. **成本纪律（军规 §13）**：行为层**不进 CI**（要模型 + 烧钱）。发版前 maintainer 手动跑；fixture 最小、
   reasoning 用 low；能 dry-run 的（映射 / 护栏）留在结构层免费跑，只有"诚实性 / 收敛"这类必须真跑 AI 的
   进行为层。

### 3.3 A 的表现
- `evals/` 目录 + `EVALS.md`（说明两层、怎么跑、成本约束）。
- ADR 0003 §6.1 / 0004 §2 的**一次性手工准入闸，升级成 codified eval**——"过准入闸"从此 =
  `evals/run.sh --only honest-checks --platform codex`，可复现。
- `pdlc-ship` 发版清单加一步："两平台跑行为 evals，贴结果"。
- README 放一张**"行为契约已验"表**（红灯 ✓ / checks 诚实 ✓ / loop 收敛 ✓ · Claude + Codex）——
  对开源工具是强信任信号。

---

## 4. B1 · `/pdlc-test-setup`（立测试地基）

一个 Layer 3 新命令（36 → 37），给一个项目**一键立起测试骨架**：

- **生成 `docs/00_standards/test-commands.yml`**（选配 unit / coverage / lint / e2e 命令，达标线写死在命令参数里）。
- 选配并接好测试 runner + 覆盖率工具 + lint（按项目语言探测：cargo / pnpm+vitest / pytest 等）。
- 脚手架测试目录结构，接 pre-commit / pre-push 钩子跑基础 check。
- 天然接 `pdlc-adopt`（老项目）与 `pdlc-bootstrap`（新项目）。可附带轻量"老项目特征化测试回填"到覆盖率底线。

**为什么它先于 B2**：pdlc 的命门（"checks 来自 test-commands.yml 的真实退出码"）**依赖该文件存在且真实**，
但现在没有任何东西帮你把它立起来。B1 把整个"退出码地基"变成 turnkey，B2 才有东西可跑。

**诚实边界**：定位成"立地基 + 补底线"，**不吹"帮你生成全部测试"**（AI 生成的测试容易浅）；深度用例仍走 `pdlc-tdd`。

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

**必须有"流程 → 测试"的映射：**
- 每个 E2E 测试**声明它覆盖哪条核心流**：约定 **测试名 / 标签带 flow id**（如 `@flow:checkout` 或
  `test_checkout__flow_checkout`），或一份显式 `docs/00_standards/e2e-flow-map.yml`。
- 报告做**覆盖矩阵**：`core_flows × 是否有对应的通过 E2E`。缺一条 = 红。
- 这样"覆盖全部核心流"就从口号变成**可核对的矩阵**，且证据来自**真跑的 E2E 结果**，不是 AI 意见。

> ⚠️ **这条是 B2 成立的地基**：没有 flow→test 映射，"覆盖核心流"永远主观，保障不了质量。

**降低"声明核心流"的摩擦**（决定 B2 是否真的有用）：
- `/pdlc-quality` 从 PRD（`docs/01_requirements/prd/`）的 P0/P1 流程**自动抽 `core_flows` 草稿**供人确认。
- 报告主动提示："PRD 里的流程 X 尚未进 `core_flows`" / "core_flow Y 尚无映射的 E2E"。

### 5.3 `/pdlc-quality`：跑 → 量 → 出报告 → 人确认
- 跑 test-commands.yml 的 coverage / e2e / lint（**真实退出码 + 真实覆盖率数字 + 真实 E2E 结果**，不自评）。
- 对照 quality-targets.yml：覆盖率达没达线、每条核心流有没有通过的 E2E、lint 干不干净。
- 产出报告落盘 `docs/07_reviews/quality/<日期>.md`：达标红绿表 + E2E 覆盖矩阵 + **趋势**
  （对比上一份报告，复用状态机 / `pdlc-retro` 那套）。
- **人确认**：报告是给人签字的（AI 只从真实数据生成报告，go/no-go 由人拍）——与"发布永远人工"一脉相承。

### 5.4 "自动化运行"怎么做到、又不踩军规 §13
军规 §13 严禁 `on:schedule` / 频繁 CI。**能本地全本地：**
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

- **不进 CI 跑行为 evals / 质量闸**（军规 §13）；自动化靠本地钩子 / 按需 / 发布挂钩 / 本地 cron。
- **不用 AI 判断替代客观数据**：覆盖率来自覆盖率工具、E2E 覆盖来自 flow→test 映射 + 真跑结果、checks 来自退出码。
  AI 只负责**生成报告**与**从 PRD 抽核心流草稿**，判定与放行由客观数据 + 人。
- **B1 不吹"生成全部测试"**；**B2 的 E2E 保障强度取决于 `core_flows` 清单与映射维护得多勤**——清单漏一条核心流，
  矩阵也照不出来，故 §5.2 的"降低声明摩擦"是 B2 真正有效的前提。
- **vanilla OpenAI Codex 不在覆盖范围**（见 ADR 0003 实现纪要）；A 的 evals 面向已验证的 Codex 发行版 + Claude Code。

---

## 7. 与既有 ADR 的关系

| ADR | 关系 |
|---|---|
| [0001 Loop 工程](0001-loop-engineering-integration.md) | loop-run 的护栏是 A `loop-convergence` / `guardrails` eval 的被测对象 |
| [0003 多平台适配](0003-multi-platform-adapters.md) | §6.1 状态完整性准入闸 → A 固化为 `honest-checks` eval，可复现、跨平台 |
| [0004 Codex loop-run](0004-codex-loop-run.md) | §2 手工准入闸结果 → A 的 `honest-checks` / `loop-convergence` eval |

---

## 8. 一句话小结

**pdlc 用它逼用户测代码的同一套纪律来测自己（A）、并把"日常质量保障"做成常设闸门（B2）。** 全程守一条命门：
**一切判定来自客观数据（退出码 / 覆盖率数字 / flow→test 映射 + 真跑），AI 只生成报告，放行由人。** 顺序
A → B1 → B2，每层为上一层兜底；自动化靠本地钩子而非 CI（军规 §13）。终极目标——**可核对、及时、由人确认地
保障产品质量。**
