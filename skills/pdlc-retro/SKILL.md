---
name: pdlc-retro
description: 迭代复盘——读状态机历史出趋势报告
argument-hint: [--range 7d|30d|all] [--feature <feature-id>]
allowed-tools: Read, Glob, Bash
layer: 2
stage: retro
produces:
  - docs/07_reviews/retro/<YYYY-MM>-retro.md
requires:
  - docs/.pdlc-state/
next_step: null
terminal_state: retro_done
---

# PDLC 迭代复盘

读取 `docs/.pdlc-state/` 下的状态机历史，按时间范围聚合，生成趋势复盘报告。

<!-- @include templates/prompts/iron-law.md -->

<!-- @include templates/prompts/state-read.md -->

## 段一：聚合统计

### 1.1 参数解析

- `--range <N>d | all`：时间窗口（默认 `30d`）
- `--feature <feature-id>`：只看单个功能的时间线（输出 history 详情而非聚合）

### 1.2 读取与过滤

1. 列出 `docs/.pdlc-state/*.json`（跳过 `_` 前缀的索引文件与 `statusline.json`）
2. **跑契约体检**（见上方「读状态机之前：先做契约体检」），结果写进报告开头的「输入契约体检」节
3. 按 `created_at` 过滤到时间窗口内。缺 `created_at` 的文件改用 `history` 末条 `done_at`——**这是口径替换，必须计入体检块**，不得静默
4. 解析每份文件的 `history` 数组

### 1.3 计算指标

对时间窗口内的所有功能聚合：

**交付量**：
- 完成功能数：`current_stage` 以 `_done` 结尾——**判终态的唯一依据**，不看 `terminal_state`（它是目标不是事实）、不用封闭列表
- 修复缺陷数：`feature_id` 以 `B` 开头（契约口径）。体检报 `id-prefix-mismatch` 的文件在体检块点名，**不据此改口径**——两个口径打架时，报出来比悄悄挑一个更有用

**质量趋势**：
- 每阶段自检通过率（`passed / (passed + failed + manual)`）；某阶段一条自检记录都没有 → 写「无数据」，不写 0%
- 各阶段自检平均 `failed`、`manual` 数
- 行按阶段短名：`stage-alias` 按 `别名→短名` 归一化后计数（归一化了哪些写进体检块）；`stage-unknown` 单独成行，不并入任何阶段

**阶段耗时**：
- 相邻 history 条目的 `done_at` 差值作为阶段耗时，输出各阶段中位数
- 任一端时间戳没有时刻（体检报 `timestamp-no-time`）→ 该间隔**不可测**，不计入中位数；全部不可测 → 整节写「不可测：<原因>」。**不得输出 0.0h**——它会被读成「快到不耗时」，实际是精度不够

**卡点案例**：
- 自检 `failed > 2` 或 `manual > 1` 的阶段
- 同一阶段耗时 > 3 天的功能

## 段二：自检

<!-- @include templates/prompts/self-audit.md -->

**复盘报告自检清单：**
- [ ] 时间窗口正确（参数解析无误）
- [ ] 数值可加总（交付量、质量趋势）
- [ ] 列出了至少 1 个卡点案例或明确说明"无卡点"
- [ ] 体检有偏差时，报告**开头**有「输入契约体检」节，且后文计算没有再用已声明忽略的字段（如 `terminal_state`）
- [ ] 阶段耗时没有把「不可测」写成 0.0h

<!-- @include templates/prompts/loop-prevention.md -->

## 段三：生成报告文件

1. 确定输出路径：`docs/07_reviews/retro/<YYYY-MM>-retro.md`（按当月归档）
2. 写入模板：

```markdown
# <YYYY-MM> PDLC 迭代复盘

> 时间窗口：<起> ~ <止>
> 生成时间：<ISO 时间>

## 输入契约体检
（仅在体检有偏差或无法体检时出现；按「偏差类 × 份数 × 处理方式」汇总，放在全文最前面）

## 交付量
- 完成功能：<N> 个
- 修复缺陷：<M> 个

## 质量趋势
| 阶段 | 自检通过率 | 平均失败数 | 平均人工介入数 |
|------|----------|------------|--------------|
| requirements | XX% | N.N | N.N |
| design       | XX% | N.N | N.N |
| tdd          | XX% | N.N | N.N |
| impl         | XX% | N.N | N.N |
| review       | XX% | N.N | N.N |

## 阶段耗时中位数
- 需求: X.Xh  设计: X.Xh  TDD: X.Xh  实现: X.Xh  评审: X.Xh
  （时间戳缺时刻导致不可测时，写「不可测：<原因>」，不写 0.0h）

## 卡点案例
- <feature-id> 在 <stage> 阶段: <原因>

## 值得保留的做法
- <从高通过率/低耗时的功能中提炼>
```

3. **IRON LAW 落盘**：文件必须实际写入磁盘，不可仅在对话中输出

## 段四：交接

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 复盘报告已生成：docs/07_reviews/retro/<YYYY-MM>-retro.md
📊 时间窗口：<起> ~ <止>，共 <N> 个功能
⚠️ 输入契约体检：<M> 处偏差（见报告开头；无偏差则省略本行）
👉 下一步：（本次流程结束，建议人工 review 报告）
```

---

**参数**：$ARGUMENTS
