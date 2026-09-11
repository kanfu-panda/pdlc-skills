<!-- 读状态机前的契约体检 · 被 pdlc-status / pdlc-retro / pdlc-relate @include -->

## 读状态机之前：先做契约体检

`docs/.pdlc-state/*.json` 不一定都是 `/pdlc-*` 命令写出来的——手写的、旧版本写的、照着格式仿写的
都可能混在里面。字段对不上契约时，**不许边猜边算、再把猜出来的东西当结论**。先体检，再计算；
体检发现的每一处偏差，都必须出现在输出的**最前面**。

### 1. 跑体检

<!-- adapter:claude-only-start -->
体检脚本随插件分发：`bin/pdlc-state-lint.sh`。按顺序取第一个存在的：

1. **本 skill 所在目录的上两级**：`<本 skill 目录>/../../bin/pdlc-state-lint.sh`（运行时会告知本 skill 的所在目录；
   这是与正在运行的 skill **同一版本**的那份）
2. `${CLAUDE_PLUGIN_ROOT}/bin/pdlc-state-lint.sh`（若该环境变量存在——skill 运行时通常**没有**它，不要指望）
3. 最新版本缓存：`ls -td ~/.claude/plugins/cache/pdlc-skills/pdlc/*/bin/pdlc-state-lint.sh 2>/dev/null | head -1`
4. `~/.claude/plugins/marketplaces/pdlc-skills/bin/pdlc-state-lint.sh`

> 第 1 条排最前，是因为体检规则（合法阶段名、偏差代码）必须和正在运行的 skill 同版本——否则新增一个阶段后，
> 旧脚本会把合法写法报成偏差。真机验证时 `CLAUDE_PLUGIN_ROOT` 不存在，缓存与 marketplace 克隆里又都是旧版本、
> 没有这个脚本，最后是模型自己按本 skill 的目录找到的同版本脚本——所以把它写成第 1 条，而不是留给临场发挥。
> 这与 `/pdlc-settings` 找状态栏脚本的顺序不同，是有意的：状态栏要一个**稳定路径**建符号链接，所以 marketplace 克隆优先。

在项目根执行 `bash <脚本路径> .`。stdout 每行一条偏差：`文件<TAB>代码<TAB>说明`。退出码三态：

- `0` 已体检、全部合契约 → 照常出结论，不输出体检块
- `1` 已体检、有偏差 → 照常计算，但输出最前面必须先放「输入契约体检」块（见 §3）
- `2` 无法体检（缺 jq / 无状态目录）→ 体检块写「无法体检：<原因>」，**不得当成合契约**
<!-- adapter:claude-only-end -->

体检脚本不可用时（找不到，或当前平台不分发它），按 §2 的规则逐条人工核对，
体检块首行注明「体检脚本不可用，以下为人工核对」。

### 2. 体检规则（偏差代码）

读侧跳过 `_` 前缀的索引文件（如 `_relations.json`）与 `statusline.json`，它们不是功能状态机。

<!-- finding-codes:start -->
| 代码 | 判定 | 读侧怎么处理 |
|---|---|---|
| `json-invalid` | 文件不是合法 JSON | 跳过该文件，列入体检块 |
| `missing-field` | 缺 `feature_id` / `current_stage` / `history` / `next_step` / `created_at` 之一 | 用到该字段的指标，对这份文件记「不可判」 |
| `missing-last_phase_result` | 缺 `last_phase_result`（多为旧文件） | 不推断本阶段结果与 checks |
| `terminal_state-in-instance` | 实例里出现 `terminal_state` | **忽略该字段**，判终态只看 §4 |
| `non-contract-field` | 其它表外顶层字段（如 `title`） | 忽略 |
| `stage-alias` | `stage` 用了已知别名 | 可按说明里的 `别名→短名` 归一化计数，**但必须在体检块写明归一化了哪些** |
| `stage-unknown` | `stage` 既不是短名也不是已知别名 | 单独成行，不并入任何阶段 |
| `current_stage-unknown` | `current_stage` 既不是短名，也不以 `_done` 结尾 | 该功能归入「❓ 异常」 |
| `next_step-not-command` | `next_step` 不是纯命令名（如带散文后缀） | 按原文展示，不据此推断下一步 |
| `timestamp-no-time` | 时间戳只有日期、没有时刻 | 依赖它的**耗时类指标记「不可测」**，不得算成 0 |
| `relations-not-object` | `relations` 不是六键对象（如数组） | 这份文件的关系**不入图**，列入体检块 |
| `relations-unknown-type` | 关系键不在六类之内 | 该键下的关系不入图 |
| `relations-target-not-id` | 关系目标不是 feature ID（散文、模块路径等） | 该条不入图 |
| `relations-dangling` | 目标 ID 没有对应的状态文件 | 标「悬空」，不参与影响半径计算 |
| `id-prefix-mismatch` | 走的是修复流程（有 `fix` 阶段），ID 却不以 `B` 开头 | 缺陷计数按 ID 前缀的契约口径算，同时在体检块点名这份 |
| `second-state-dir` | 仓库根另有一个 `.pdlc-state/` | 本命令只读 `docs/.pdlc-state/`，提示两处并存 |
<!-- finding-codes:end -->

**「不入图」不是丢弃**：关系目标是散文时，把它硬解读成某个 feature，等于把猜测升格成结构——
影响半径会因此多出一条本不存在的强依赖。宁可在体检块里原样列出，交给人判断。

#### 阶段短名全集

`history[].stage` 与 `last_phase_result.stage` 只能取下表的短名——每个短名由对应命令写入，
等于该命令 frontmatter 的 `stage:`。别名只为**读**旧数据时容忍，归一化必须披露；**写**的时候一律用短名。

<!-- stage-names:start -->
| 短名 | 由哪个命令写入 | 已知别名（读侧可归一化，须披露） |
|---|---|---|
| `requirements` | `pdlc-prd` | `prd` |
| `design` | `pdlc-design` | |
| `tdd` | `pdlc-tdd` | |
| `impl` | `pdlc-implement` | `implement, implementation` |
| `review` | `pdlc-review` | |
| `e2e` | `pdlc-e2e` | |
| `ship` | `pdlc-ship` | |
| `deploy` | `pdlc-deploy` | |
| `fix` | `pdlc-fix` | `bugfix` |
| `refactor` | `pdlc-refactor` | |
| `task` | `pdlc-task` | |
| `feature` | `pdlc-feature` | |
<!-- stage-names:end -->

### 3. 体检块的格式（放在输出最前面）

```
⚠️ 输入契约体检：<N> 份状态文件，<M> 处偏差——以下结论建立在这些处理之上
  · 3/5 份缺 created_at → 时间窗改用 history 末条 done_at
  · 阶段别名 prd→requirements ×1、implementation→impl ×2 → 已归一化计数
  · 5/5 份含 terminal_state → 已忽略（判终态只看 current_stage）
  · 2 份的 done_at 只有日期 → 阶段耗时记「不可测」
```

- **按「偏差类 × 份数 × 处理方式」汇总**，不要把脚本输出原样倒出来
- **放最前面，不放末尾**——结论会被单独引用，偏差得跟着结论走；写在报告末尾的偏差表，
  读者看到的时候已经信了前面的数字
- **计数照抄脚本输出，不要自己重数**：按代码计数用 `cut -f2 | sort | uniq -c`，份数按第一列去重。
  真机验证时脚本报 25 处无时刻的时间戳，报告正文却自己数成了 26——同一份报告里两个数字对不上，
  读者就不知道该信哪个
- 同一次输出里，前面披露了「已忽略 X」，后面的计算就不得再用 X

### 4. 判终态的唯一依据 ⛔

**已抵达终态 ⇔ `current_stage` 以 `_done` 结尾**（编排器写入的是 `feature_done` / `fix_done`）。

- **不看 `terminal_state`**。状态机实例本就没有这个字段。skill frontmatter 里的 `terminal_state:`
  说的是「这个命令走完后**应当**到达的终态名」——是**目标**，不是**事实**。拿它判终态，
  等于把「打算完成」当成「已经完成」。
- **不用封闭列表**（如只认 `[feature_done, fix_done]`）。封闭列表会把合法的终态漏判成「进行中」，
  逼着读侧去别的字段里找答案——而最顺手的那个字段恰好就是 `terminal_state`。
- **`next_step` 为 `null` 也不等于终态**：原子 fix 流程的 `next_step` 恒为 `null`，却未必完成。
