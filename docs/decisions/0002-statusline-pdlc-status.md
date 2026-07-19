# 0002 · 在 Claude Code 状态栏显示 PDLC 运行状态

- **状态**：Accepted
- **日期**：2026-07-18
- **作者**：kanfu-panda

---

## 1. 背景与目标

pdlc-skills 已经把每个功能的完整生命周期落到一个机器可读的状态机文件
`docs/.pdlc-state/<功能ID>.json`（含 `current_stage` / `next_step` / `run_mode` /
`last_phase_result` 等）。用户在终端里跑 `/pdlc-*` 命令、尤其跑
`/pdlc-loop-run --autonomous` 自主收敛时，**当前进行到哪个阶段、下一步该跑什么、
检查过没过、是不是卡住在等人**——这些信息现在只能靠翻文件或看命令输出得知。

Claude Code 提供了**状态栏（statusLine）**机制：一个用户配置的命令，每次刷新时从
stdin 收到一个 JSON（含 `workspace.current_dir`、`model`、`context_window` 等），
其 stdout 就是终端底部那一行状态。本方案把 PDLC 的运行状态**作为可选的一段**接入
这条状态栏，让用户「一眼看清 PDLC 在跑什么」。

**目标**：pdlc-skills 提供一个自包含、零依赖注册、默认关闭的状态栏片段，读当前项目的
`docs/.pdlc-state/`，输出一行简洁的 PDLC 运行状态。

**非目标（明确不做）**：
- 不做花哨可视化（不画大进度条动画、不做 TUI）。
- 不改状态机语义、不改任何 `/pdlc-*` 命令的行为。这是纯**只读展示层**。
- 不替用户接管整条状态栏；不假设用户用不用别的状态栏插件。
- 不为「未来可能的展示项」提前抽象（YAGNI），只做下面列出的字段。

---

## 2. 机制约束（最容易翻车、必须先讲清）

Claude Code 的 settings.json **只有一个 `statusLine.command` 槽**，不能注册第二个。
所以「PDLC 独立占一行」的真实含义是：

- **「独立一行」= 视觉上单独一行**（状态栏支持多行输出），**不是**在 settings.json
  里新增第二个状态栏字段——那个字段只有一个。
- **「开」= 在用户那唯一的 command 里追加调用本片段**。例如把命令从
  `your-hud.sh` 改成 `your-hud.sh; ~/.claude/pdlc-statusline`（片段自己吐它那一行）。
- **「关」= 不追加**（或本片段检测到未启用/非 PDLC 项目时吐空）。

> ⚠️ **本片段是 shell 脚本，不是 Claude 技能**：状态栏机制跑的是 **shell 命令**，
> 而 `/pdlc-*` 是由 Claude 解释执行的技能（SKILL.md），**无法在 statusLine 里被调用**。
> 因此本功能交付物是一个真实可执行脚本 `bin/pdlc-statusline.sh`（经稳定路径符号链接
> `~/.claude/pdlc-statusline` 暴露，见 §8），**不是**给某个 `/pdlc-*` 技能加 flag。

> ⚠️ **文档措辞红线**：面向用户的说明**必须**写成「把 `~/.claude/pdlc-statusline`
> **追加**到你现有的状态栏命令后面」，**绝不能**写成「在 settings.json 里新增一个
> statusLine」——后者会诱导用户一把覆盖掉已有的状态栏配置。

因此 pdlc-skills 出的是**一个自包含、非 PDLC 项目 / 关闭时吐空**的片段，由用户拼进那条
唯一的命令。**代价**：多输出一行 = 状态栏整体变高一行（吃一行垂直空间）——这是「独立、
不与其它状态栏抢占同一行」换来的，是有意识的取舍。

---

## 3. 设计原则

1. **默认关闭、零副作用**：不装即无感；用户显式启用才生效。pdlc-skills **绝不擅自 / 静默**
   改用户 settings.json（插件也无权注册主状态栏）；仅在用户运行 `/pdlc-settings` 后，经
   **备份 + diff + 用户确认**幂等追加自己那一段，绝不覆盖其它内容。写入若被安全层拦截 → 优雅降级（见 §6.2）。
2. **只读、快、稳**：状态栏每次刷新都跑，渲染必须 <10ms；解析失败 / 无状态文件 →
   **静默吐空**，绝不报错、绝不阻塞终端。
3. **状态机是唯一真源**：只读 `docs/.pdlc-state/*.json`，不猜、不解析散文。
4. **智能默认而非一刀全开**：展示项跟随 `run_mode` 与是否 blocked 自适应（见 §5），
   减少手动模式下的噪音。
5. **blocked 优先可见**：状态栏的头号使命是让「卡住了、在等人」一眼可见。

---

## 4. 数据来源（状态文件 → 展示字段映射）

片段读取 `<current_dir>/docs/.pdlc-state/*.json`，可用字段（均已存在于现有 schema）：

| 展示信息 | 来源字段 |
|---|---|
| 功能名 | `feature_name`（默认显示）／`feature_id`（可选完整显示） |
| 当前阶段 | `current_stage`（短名 requirements/design/tdd/impl/review） |
| 下一步 | `next_step`（命令名，去 `pdlc-` 前缀显示） |
| 运行态 | `run_mode`（interactive/autonomous）+ `last_phase_result.blocked_reason` 是否非空 |
| 检查结果 | `last_phase_result.checks`（`tests_pass` / `coverage_pass` / `lint_clean`，布尔） |
| 停留时长 | now − `last_phase_result.at`（近似「在当前阶段停留多久」） |
| blocked 原因 | `last_phase_result.blocked_reason` |
| 终态判定 | `next_step == null` 或 `current_stage` 属终态 |

> ⚠️ **coverage 是布尔不是数值**：现 schema 只存 `coverage_pass`（过/不过），不存百分比。
> 所以默认显示 `✓cov` / `✗cov`，**不显示 `87%`**。若确需数值，需另行扩展 schema（列入 §10 待决）。

---

## 5. 显示设计

### 5.1 默认四样：迷你进度条 + 功能名 + 下一步 + 运行图标

**不使用 `④/6` 这类「第几/共几」数字**——因为不是每个 feature 都走满 6 段（bug 修复走 fix 流程、
loop 只在 `tdd→impl→review` 段活动），`/6` 会误导。改用**迷你进度条**，高亮当前段：

```
● PDLC auth · PRD·设计·TDD·[实现]·评审·发布 · →评审 · 👤
```

- `PDLC auth`：产品标识 + 功能名（默认名字，不显示完整长 ID）
- `PRD·设计·TDD·[实现]·评审·发布`：**功能流水线固定轨**，`[ ]` 标当前段
- `→评审`：`next_step`，一眼知道该跑什么
- `👤`：运行图标（👤 手动 / 🤖 autonomous / ⛔ blocked / ✅ done）

> ⚠️ **进度条是「固定的功能流水线轨」，不是「动态只铺经过的段」**（与实现对齐、避免二义）：
> - **F（功能）流程**：current_stage 属 `requirements/design/tdd/impl/review` → 显示完整 6 段轨、高亮当前。
>   loop 收敛期（tdd/impl/review）也显示**同一条 6 段轨**、只是高亮点落在中后段——**不裁成 3 段**。
> - **非 F 流水线阶段**（如 `B` 前缀的原子 fix 流程 `current_stage: fix`、或任何不在上述集合的自定义阶段）：
>   **只显示当前阶段名**（如 `· fix`），**绝不硬套「PRD·设计…」F 轨**（那会把一个 bug 修复误显成走 PRD 的功能）。
> - **终态**（`*_done`）：显示 `✅ done`。

### 5.2 last-check 与 elapsed：跟 `run_mode` 智能默认

不一刀全开，按场景默认：

- **检查结果 `✓unit ✓lint ✓cov`**：**autonomous 默认显示，interactive 默认隐藏**。
  理由：手动模式下用户自己在跑测试、心里有数，`✓unit ✓lint` 是噪音；它的价值全在
  **loop 无人跑时**（一眼看到自主收敛的健康度）。
- **停留时长 `⏱12m`**：**blocked / autonomous 下默认开**，手动下可选。
  理由：这是「是不是卡壳了 / loop 是不是停在等我」的最强信号，正对 loop 工程的
  stuck-stop / fail-stop 痛点。

autonomous / loop 模式的典型行（进度条仍是完整 6 段轨、高亮落在实现段）：

```
● PDLC auth · PRD·设计·TDD·[实现]·评审·发布 · →评审 · 🤖 ✓unit ✓lint ✓cov · ⏱3m
```

### 5.3 blocked：全行最醒目

blocked 是头号使命，做成整行最抢眼（自己的颜色/图标 + 截断的 reason + 停留时长）：

```
⛔ PDLC auth blocked: PRD 取舍需人工 · ⏱12m
```

### 5.4 pick_feature：多 feature 时选谁显示（优先级精确定义）

多个进行中的 feature 时只显示一个，**不能只按 mtime**（否则刚 `review_done` 的会盖住你
正在做的）。优先级规则：

1. **非终态优先**（`next_step != null` 且非 `*_done`）——排除已完成的
2. **其中 blocked 顶上**（`blocked_reason` 非空的抢显示权）
3. **再按最近修改**（`last_phase_result.at` 最新）

即：`blocked` 永远抢显示权（那是「loop 在等你」，最该被看见）；否则显示最近活跃的非终态
feature。可选配置 `pick_feature` 支持固定显示某个 ID 或强制 `latest`。

> ⚠️ **多 feature 下的性能策略（保住 §7 的 <10ms）**：feature 多时，上面这套
> 「非终态 → blocked → 最近修改」若逐个 `jq` 解析全部状态文件，N 一大每帧就超 10ms。
> 因此**先按文件 mtime 排序、只解析最近的少数几个（懒解析）**，命中非终态/blocked 即停，
> **绝不每帧全解**。（mtime 与状态内 `at` 通常一致；极端不一致只影响罕见的显示优先级，可接受。）
>
> ⚠️ **边界**：懒解析下「blocked 抢显示权」被收窄为「**blocked 只在被扫到的最近 N 个里抢权**」——
> 一个 mtime 很旧、排在窗口外的 blocked feature 不会被扫到、因此不抢权。这是「<10ms 预算」与
> 「全局 blocked 优先」之间的有意取舍：正在活跃的工作总在最近窗口内，旧 blocked 罕见且可接受漏显。
> `N` 取一个小常数（如 5）。

---

## 6. 配置方案：交互式 `/pdlc-settings`（主路径）

**用户不敲长命令行、也不裸手改文件。** 配置走一个**交互式命令 `/pdlc-settings`**，当前
**只做「状态栏」一节**。未来若有更多设置**可能**并入同一命令——但这**不是本方案的承诺**，
本方案只交付状态栏这一节（避免 §1 已声明的「为未来提前抽象」）。

### 6.1 为什么用命令而非裸手工

启用状态栏需要改用户全局 `~/.claude/settings.json` 的 `statusLine.command`——这正是 §2 警告的
「追加 vs 覆盖」高危点，裸手工极易把现有 HUD 覆盖掉。交给 `/pdlc-settings` 做可**幂等追加 + 改前备份 + 展示 diff**，
从根上规避误覆盖。

### 6.2 `/pdlc-settings` 的能力（含被 gate 时的优雅降级）

交互式菜单，选项即答（尽量不让用户敲长参数）：

- **状态栏 · 启用**：跑 `--install`（稳定路径符号链接，见 §8.1）→ 读现有 `statusLine.command`
  → 算出**幂等追加**后的新值（已存在则跳过）→ 备份 + 展示 diff → 写入。
- **状态栏 · 停用**：算出摘掉本段后的新值，**绝不动**用户其它命令 → 备份 + diff → 写入。
- **状态栏 · 展示项**：交互勾选下方各项 → 写配置文件 → **当场渲染一行预览**。
- **状态栏 · 状态**：显示当前是否已接线、生效配置、预览。

> ⚠️ **写全局 `~/.claude/settings.json` 会被 Claude Code 安全层 gate**（这是本会话亲历的真实约束：
> AI / 技能写全局配置是高影响动作、会被拦截或要人工放行）。因此 `/pdlc-settings` **绝不假设静默写成功**。
> 流程强制：**先备份 → 算好 diff（只增自己那一行）→ 展示给用户**；随后：
> - 若环境允许写 → 幂等写入，重复运行不叠加；
> - **若写入被 gate / 拒绝 → 优雅降级**：明确告知「已备份，这是需要追加的那一行 `<...>`，请你确认后手动粘贴到
>   `~/.claude/settings.json` 的 `statusLine.command`」，并给出精确位置——**不谎报「已启用」**。
>
> 停用同理：给出摘除后的确切值，被 gate 时降级为「请手动替换为 `<...>`」。**「零裸手工」是理想路径，
> 被 gate 时诚实回退到「命令算好 + 用户一步粘贴」，绝不静默失败。**

### 6.3 配置存储：小 JSON，不用 TOML

`/pdlc-settings` 把展示项写进一个 **jq 能读的小 JSON**（`~/.claude/pdlc-statusline.json`，
可被项目级 `docs/.pdlc-state/statusline.json` 覆盖）。不用 TOML——状态栏每帧渲染、子进程要省（见 §7），
bash 原生解析不了 TOML（得拉 python/toml、每帧多起进程）；JSON 用 **一把 jq** 合并两文件并一次性取全部键
（不逐键起 jq），另附一份带注释的 `.example` 供兜底手改。

可配置项（默认值见括号）：

| 配置项 | 默认 | 说明 |
|---|---|---|
| `show_progress_bar` | on | 迷你进度条 |
| `show_next` | on | 下一步 |
| `show_run_icon` | on | 运行态图标 |
| `show_checks` | auto（autonomous 显） | 检查结果，跟 run_mode |
| `show_elapsed` | auto（blocked/autonomous 显） | 停留时长 |
| `show_full_id` | off | 显示完整 `F...` ID 而非仅名字 |
| `pick_feature` | auto（§5.4 规则） | `auto` / `latest` / 具体 ID |
| `color` | on | 颜色 / 图标开关（终端不支持时降级为纯文本） |

### 6.4 默认关

不跑 `/pdlc-settings` 启用即「关」——状态栏命令里没有本片段，**默认零副作用**。

---

## 7. 性能与健壮性预算

- **子进程节流是硬指标**（本节的核心）：**全程 ≤3 个 jq**——① 解析 stdin 取 cwd（仅当 stdin 非空）、
  ② 一把合并 + 提取全部配置键、③ 一把解析窗口内全部状态文件。**绝不**「每个配置键起一个 jq」或
  「每个字段起一个 `cut`」——字段一律用 **bash builtin `read`**（配合非空白分隔符 Unit Separator 0x1f，空字段不像 tab 那样被折叠、列不错位）取，
  `date` 取一次当前时刻复用。这是避免与 HUD 组合后每帧几百 ms 的关键。
  > 实测：单帧约 3 个 jq + 3 个 date ≈ 6 个子进程（含一次 BSD `date -d` 失败探测）；瓶颈是 jq 自身启动
  > （每个约数 ms），全帧数十 ms 量级，远在状态栏刷新去抖窗口内。**注意**：早期设计写的「<10ms」对含 jq 的
  > 完整渲染不现实（3 次 jq 启动就超），故本节以「子进程数」为真实指标；**只有非 PDLC 快路径（0 个 jq）才 <10ms**。
- **jq 是本片段引入的软依赖**（并非 pdlc-skills 既有声明依赖）——**缺失即静默降级/吐空**，不给用户强加安装负担。
- **非 PDLC 项目快速短路**：先判 `docs/.pdlc-state/` 是否存在，不存在**立即吐空退出**（0 个 jq，绝大多数刷新走这条）。
- **多 feature 懒解析**：按 mtime 排序、只解析最近少数几个（见 §5.4），避免 N 大时子进程/耗时膨胀。
- **永不阻塞终端**：任何异常（无 jq、文件损坏、权限）→ 静默吐空，退出码 0。
- **无网络、无外发**：只读本地状态文件，绝不发起任何网络请求。

---

## 8. 交付物

```
skills/pdlc-settings/SKILL.md          ← 交互式设置命令（Layer 3）：状态栏启用/停用/展示项/状态（当前仅此一节）
bin/pdlc-statusline.sh                 ← 自包含片段：读 stdin JSON → 扫 docs/.pdlc-state → 吐一行
references/templates/pdlc-statusline.example.json   ← 带注释的配置样例（兜底手改用）
docs/usage-guide.md（新增一节）        ← 「在状态栏显示 PDLC 状态」：走 /pdlc-settings 的接入说明 + 配置项 + 截图
tests/statusline-check.sh（可选）      ← 用 mock 状态文件断言各场景输出
```

新增 `/pdlc-settings` 是一个 **Layer 3** 技能，命令驱动地完成 §6 的接线与配置（读写
`~/.claude/settings.json` 与配置 JSON，全部带备份 + diff + 确认 + 幂等，写被 gate 时降级为「算好 + 用户粘贴」）。
**范围仅状态栏一节**，不预建「所有设置的归口」框架（YAGNI）。

> 📌 **随附 chore（新增技能的连带同步）**：`skills/pdlc-settings/SKILL.md` 会把技能数 **35 → 36**，
> 需同步更新：`README.md` / `README.zh-CN.md`（命令目录与计数）、`.claude-plugin/plugin.json`、
> `.claude-plugin/marketplace.json`、`tests/install-smoke.sh`（技能数与片段数断言）、`docs/usage-guide.md` 命令表。
> `tests/frontmatter-check.sh` 会在漏改时报错兜底，但实现时应主动一并改。

### 8.1 稳定路径机制（升级不断）—— 设计项，非「建议」

插件装在 `~/.claude/plugins/cache/pdlc-skills/pdlc/<版本>/bin/`，**路径带版本号，每次升级就变**。
若让用户在 statusLine 命令里硬编这个 cache 路径，**每次 plugin update 后状态栏就断**。
「建议用户自行拷到固定位置」太脆（每次升级手动重拷）。因此需要一个真实机制：

- 提供 `bin/pdlc-statusline.sh --install` 步骤（或在 `install.sh` 里做）：在**固定路径**
  `~/.claude/pdlc-statusline` 建一个**指向当前版本脚本的符号链接**（或薄 wrapper）。
- 用户只在 statusLine 命令里指这个**稳定路径** `~/.claude/pdlc-statusline`。
- 升级时 `--install` **重指符号链接**即可，用户侧命令一字不改、永不断。

（若目标环境不支持符号链接，wrapper 方案退化为一个转发到当前版本脚本的一行 bash。）

---

## 9. 验证方式（原型阶段）

用 mock 状态文件覆盖以下场景，逐一喂给脚本、核对真实输出：

1. impl 阶段 · interactive（默认隐检查、隐 elapsed；显示完整 6 段轨、高亮实现）
2. loop 收敛中 · autonomous（显检查、显 elapsed；进度条仍是**完整 6 段轨**、高亮落在实现段）
3. blocked（全行最醒目 + reason + elapsed）
4. review_done 终态（`✅ done`）
5. 多 feature 并行（验证 §5.4 优先级：blocked 抢显示权）
6. **§5.4 边界负例**：一个 mtime 很旧、落在最近 N 窗口**之外**的 blocked feature —— 验证它**不**抢权
   （被更近的活跃 feature 正常显示），坐实「blocked 只在窗口内抢权」的取舍
7. **B 前缀原子 fix（非 F 流水线阶段）**：`current_stage: fix` —— 验证**只显阶段名**、**不**伪造 `PRD·设计…` F 轨、不误显 done
8. 非 PDLC 项目 / 无状态文件（吐空、退出 0）

---

## 10. 待决问题

1. **coverage 数值**：现只存布尔。要显示 `87%` 需扩展 `last_phase_result.checks`
   存百分比（涉及改 `pdlc-review` / `pdlc-implement` 写状态逻辑）——本方案默认**不做**，
   先用 `✓cov/✗cov`。是否值得扩展？
2. **loop 步数 `loop 2/4`**：现 schema 无步数字段。要显示需 `pdlc-loop-run` 在状态里
   记 `loop.step/max`（小改动）。本方案默认**不做**，待确认是否值得。
3. **颜色 / OSC8 链接**：是否让功能名做成可点击（OSC8）跳到状态文件？倾向暂不做。
4. **刷新频率**：依赖 Claude Code 的事件刷新即可，是否需要 `refreshInterval` 兜底？倾向不设。

---

## 11. 一句话小结

pdlc-skills 出一个**自包含、默认关、非 PDLC 吐空**的**真实 shell 脚本** `bin/pdlc-statusline.sh`
（经稳定路径符号链接 `~/.claude/pdlc-statusline` 暴露、升级不断，**不是**给某个 `/pdlc-*` 技能加 flag），
通过**交互式 `/pdlc-settings`** 命令幂等接线到用户唯一的状态栏命令后独占一行——理想路径**用户零裸手工**，
但**写全局 settings.json 会被安全层 gate**，届时优雅降级为「命令算好那一行 + 用户一步粘贴」，绝不谎报已启用。
默认显示**进度条 + 名字 + 下一步 + 运行图标**四样，
**检查结果与停留时长跟 `run_mode` 智能默认**（loop 时自动多显），**blocked 做成全行最醒目**，
多 feature 时**非终态 + blocked 优先 + 懒解析**。必须焊死的机制是「单 command 追加一行」，
绝不做成第二个 statusLine。
