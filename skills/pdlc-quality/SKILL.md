---
name: pdlc-quality
description: 质量闸门——跑真实 check、对照质量目标、出可核对报告，由人签字放行
argument-hint: [--init] [--autonomous]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: quality
artifact_type: ledger
produces:
  # 主产物（ledger 型，一次一份可看趋势）
  - docs/07_reviews/quality/<YYYY-MM-DD>.md
  # 仅 --init 时创建（surface 型，就地编辑不累积）
  - docs/00_standards/quality-targets.yml
  - docs/00_standards/e2e-flow-map.yml
requires:
  - docs/00_standards/test-commands.yml
next_step: null
terminal_state: null
recommended_model: sonnet
recommended_effort: medium
---

# 质量闸门与报告

跑真实 check → 对照质量目标 → 出可核对的报告 → **人签字放行**。

<!-- @include templates/prompts/iron-law.md -->
<!-- @include templates/prompts/noninteractive.md -->

## 这个命令的立身之本

**一切判定来自客观数据**：覆盖率数字来自覆盖率工具、E2E 覆盖来自 flow→test 映射 + 真跑结果、lint 来自退出码。
**AI 只负责把这些数据整理成报告，不参与"达标与否"的判定**，放行由人。

> ⛔ 绝不允许出现的行为：用"我看了一下代码，测试挺全的"这类判断替代真实数据；
> 用上一次的结果冒充本次；命令没跑通却按通过处理；覆盖率没测量却写一个数字。
> **量不到就如实写"未测量"**——这与状态机里「无命令可跑 → `checks: {}`」是同一条纪律。

## 前置：两份真源

| 文件 | 作用 | 缺失时 |
|---|---|---|
| `docs/00_standards/test-commands.yml` | 怎么量（命令） | **中止**，提示先跑 `/pdlc-test-setup` |
| `docs/00_standards/quality-targets.yml` | 量到多少算达标 | 走 `--init` 交互创建（见下） |
| `docs/00_standards/e2e-flow-map.yml` | 核心流 → E2E 测试 的映射 | 若 targets 里声明了 `core_flows` 则**必须有**，否则 E2E 判定无法机械化 |

### `--init`：首次建立目标声明

1. 读 `templates/quality-targets-template.yml` 作骨架。
2. **从 PRD 自动抽 `core_flows` 草稿**：扫 `docs/01_requirements/prd/`，提取标记为 **P0 / P1** 的功能流程，
   生成候选清单（含来源 PRD 路径）**供人确认**——降低首次声明的摩擦，但**最终清单必须人确认**，不自动落盘。
3. 覆盖率达标线：默认与 `test-commands.yml` 的 coverage 命令参数对齐；两者不一致要提示人对齐
   （**以命令参数为准**——那才是真正的强制点）。
4. 同时生成 `e2e-flow-map.yml` 骨架（每条 flow 一个空 `tests` 列表待填）。

## 段一：跑真实 check

按 `test-commands.yml` 逐条真跑 `coverage` / `e2e` / `lint`，记录**命令原文 + 退出码 + 关键输出**：

- 命令为空字符串（项目未配置该项）→ 如实记为「留空，未测量」，**不得因此判为通过**
- 命令跑不起来（127 / 工具未装）→ 记为「无法执行」+ 原因，**按未达标处理**（不是通过）
- 覆盖率数字从工具输出中**摘取原文**，不重新计算、不四舍五入到好看的数

## 段二：三项机械核对

### 2.1 覆盖率

拿实测数字对 `quality-targets.yml` 的达标线。真正的强制点是命令参数里的阈值（如 `--cov-fail-under=85`）——
**退出码就是判定**；yml 里的数字用于报告展示与趋势。两处不一致 → 报告里提示对齐。

### 2.2 E2E 覆盖矩阵（B2 的第一个地基）

对每条 `core_flow`，按 `e2e-flow-map.yml` 找到映射的测试标识，再到**本次真跑的 E2E 结果**里核对：

| 情况 | 判定 |
|---|---|
| 映射存在 且 对应测试本次通过 | ✅ |
| 映射存在 但 测试本次失败 | ❌ |
| 映射存在 但 该测试在本次结果里**找不到** | ❌ **映射腐烂**（指向了不存在的测试） |
| `core_flow` 在映射文件里**没有条目** | ❌ 缺映射 |
| 映射里有 `core_flows` 中不存在的 id | ⚠️ 黄：孤儿映射，建议清理 |

**缺一条 = 红。** 绝不用"我觉得这条流程被别的测试覆盖了"来补空缺——那正是要消灭的主观判断。

### 2.3 PRD ↔ core_flows 对账（B2 的第二个地基，防 false-green）⭐

清单靠"有人记得改"维护必然腐烂；**腐烂的清单产出 false-green**——新增的核心流没进清单，矩阵照样全绿，
把"我们不知道"伪装成"我们覆盖了"，比没有闸门更坏。所以每次运行都强制对账：

1. 扫 `docs/01_requirements/prd/` 所有 PRD，提取 **P0 / P1** 流程。
2. 与 `quality-targets.yml` 的 `core_flows` 做 diff。
3. **漂移即红灯**，不是温柔提示：
   - PRD 有、`core_flows` 无 → ❌「PRD 流程 X 未进 core_flows」
   - `core_flows` 有、映射无 → ❌「core_flow Y 尚无映射的 E2E」
   - 映射有、`core_flows` 无 → ⚠️ 孤儿映射

> ⛔ **"不可判"绝不能被当成"没问题"**（对账自身的 false-green，真项目上实测踩到过）：
> 若某份 PRD **不含任何 P0/P1 标记**，它提取出的就是空集，于是**不产生任何漂移条目**——
> 报告若就此显示"对账通过"，等于宣称"这份 PRD 里的流程都覆盖了"，而事实是**它整份都没进闸门视野**。
> 已上线的主链路最容易栽在这里（老 PRD 常只写"已上线/待开发"，不标优先级）。
>
> **规则**：统计"因无优先级标记而未参与对账"的 PRD，**在报告里单列告警**，并且
> **对账项不得判为 ✅**——写成 `⚠️ 无漂移，但另有 N 份 PRD 不可判`。
> 处理建议：给这些 PRD 补优先级标记，或在 `quality-targets.yml` 里显式声明豁免（写明理由）。

> 这样清单维护就从"靠自觉"变成**被产物纪律接管**——PRD 本就被 pdlc 逼着落盘并保持最新，
> 让它当 `core_flows` 的唯一上游真源，与「状态外化到磁盘」是同一个哲学。

## 段三：出报告

按 `templates/quality-report-template.md` 生成 `docs/07_reviews/quality/<YYYY-MM-DD>.md`（**ledger 型**：一次一份，
可 git diff、可看趋势；同日重跑则覆盖当日文件）。必须包含：

1. 结论红绿表　2. 实测证据（命令 + 退出码 + 关键输出）　3. E2E 覆盖矩阵
4. PRD 对账结果　5. 趋势（对比上一份报告；首次则写「无趋势基线」）　6. **人工确认签字栏**

## 段四：自检（强制）

<!-- @include templates/prompts/self-audit.md -->

- [ ] 报告里每一条判定，都能追到本次真跑的退出码 / 工具输出 / 映射核对结果
- [ ] 没有任何一项是靠"读代码觉得"得出的
- [ ] 留空 / 无法执行的项，如实标注且**未按通过处理**
- [ ] 覆盖率数字是从工具输出摘的原文
- [ ] E2E 矩阵里每条 `core_flow` 都有明确判定（含"映射腐烂"这种红）
- [ ] PRD 对账已执行，漂移项按红灯列出
- [ ] 报告落盘到 `docs/07_reviews/quality/`，含生成时间与 commit SHA
- [ ] 未在报告里替人做 go/no-go 决定

## 段五：修复（单次，不递归）

<!-- @include templates/prompts/loop-prevention.md -->

可自动修复的（如 lint 可自动修的告警）→ 修完**重跑该 check** 并以重跑结果为准，报告里注明"已自动修复后重测"。
不可自动修复 → 如实留红，写进报告。

## 怎么"自动化运行"（不依赖 CI）

- **pre-push 钩子**：push 前本地跑一遍质量闸，不达标就拦或告警——日常自动且**零 CI 成本**
- **按需**：随时 `/pdlc-quality` 出全量报告
- **发布挂钩**：`/pdlc-ship` 会读最近一份质量报告，未达标不让发（除非人显式 override 并写明理由）
- **要"每天一份"**：用本机 launchd / cron 跑，报告进 git；**绝不**用 GitHub Actions `schedule`

## 段六：交接

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
📊 质量报告：docs/07_reviews/quality/<YYYY-MM-DD>.md
  覆盖率      : <实测> / 目标 <目标>   ✅|❌
  E2E 核心流  : <M>/<N> 条已覆盖        ✅|❌
  Lint        : 退出码 <N>             ✅|❌
  PRD 对账    : <无漂移 | N 项漂移>     ✅|❌
🧾 总判定：<达标 | 未达标>
✍️ 待人工签字：报告第 6 节（go/no-go 由你拍，本命令不代劳）
👉 未达标项处理：<每条给出具体下一步>
```

## 诚实边界

- **达标不等于质量好**：覆盖率线挡的是"几乎没测"，不保证用例有效；矩阵证明"每条核心流有测试跑过"，
  不证明"测得对"。报告要如实呈现这层含义，不要把"全绿"说成"质量有保障"。
- **保障强度取决于 `core_flows` 维护得多勤**——这正是 §2.3 强制对账存在的原因，但对账只能发现
  "PRD 里有而清单里没有"，**PRD 本身漏掉的核心流谁也发现不了**。这条限制要让用户知道。

---

**参数**: $ARGUMENTS
