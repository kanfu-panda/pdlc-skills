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

## 段一：聚合统计

### 1.1 参数解析

- `--range <N>d | all`：时间窗口（默认 `30d`）
- `--feature <feature-id>`：只看单个功能的时间线（输出 history 详情而非聚合）

### 1.2 读取与过滤

1. 列出 `docs/.pdlc-state/*.json`
2. 按 `created_at` 字段过滤到时间窗口内
3. 解析每份文件的 `history` 数组

### 1.3 计算指标

对时间窗口内的所有功能聚合：

**交付量**：
- 完成功能数（`current_stage` 在 `[feature_done, fix_done]`）
- 修复缺陷数（`feature_id` 以 `B` 开头）

**质量趋势**：
- 每阶段自检通过率（`passed / (passed + failed + manual)`）
- 各阶段自检平均 `failed`、`manual` 数

**阶段耗时**：
- 相邻 history 条目的 `done_at` 差值作为阶段耗时
- 输出各阶段中位数

**卡点案例**：
- 自检 `failed > 2` 或 `manual > 1` 的阶段
- 同一阶段耗时 > 3 天的功能

## 段二：自检

<!-- @include templates/prompts/self-audit.md -->

**复盘报告自检清单：**
- [ ] 时间窗口正确（参数解析无误）
- [ ] 数值可加总（交付量、质量趋势）
- [ ] 列出了至少 1 个卡点案例或明确说明"无卡点"

<!-- @include templates/prompts/loop-prevention.md -->

## 段三：生成报告文件

1. 确定输出路径：`docs/07_reviews/retro/<YYYY-MM>-retro.md`（按当月归档）
2. 写入模板：

```markdown
# <YYYY-MM> PDLC 迭代复盘

> 时间窗口：<起> ~ <止>
> 生成时间：<ISO 时间>

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
👉 下一步：（本次流程结束，建议人工 review 报告）
```

---

**参数**：$ARGUMENTS
