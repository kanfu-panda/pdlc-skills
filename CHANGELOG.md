# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **循环判停会把残缺状态报成「收敛完成」**（外部评审提出，已复现）：`compute_next()` 把缺失的 `next_step` 折成 `"null"` 后映射到 `done`，于是三种输入全部返回退出码 0 + 「✅ 收敛到 review_done」——① 空对象 `{}`；② `current_stage=tdd` 但缺 `next_step`；③ `ok=false`、测试失败、`next_step=null` 且无 `blocked_reason`。这类输入**逃得过「无法解析 → blocked」的兜底**，因为 `{}` 是合法 JSON，解析得了、只是什么都没有。
  - 根因不在驱动而在契约：`skills/pdlc-loop-next/SKILL.md` 的映射表把 `null → done`，注释写「机械收敛已完成（review 通过）」。查各 skill frontmatter 可知这句是**事实错误**——机械收敛段里没有任何阶段会合法写出 `null`（`pdlc-implement` → `pdlc-review`，`pdlc-review` 与 `pdlc-fix` → `pdlc-ship`），收敛完成的信号是 `next_step=pdlc-ship`，本就单独映射到 `done`。**这条分支没有合法生产者，只在状态残缺时触发。**
  - 现改为 `null` / 缺失 → `blocked`。展示层早有同一结论（`bin/pdlc-statusline.sh` 的 `is_terminal`：原子 fix 流程 `next` 恒为 `null` 却未完成，误判会显示「✅ done」）——判停层现在与它对齐。
  - `tests/adapter-codex-loop-run-check.sh` 新增 4 条断言覆盖上述输入，原先那条把 `next=null` 断言成 `done` 的用例一并翻正。ADR 0004 §决策 补更正纪要（正文保留作时间点快照）。
- **`docs/usage-guide.md` 的状态机范例把 `next_step` 写成短名 `"ship"`**：契约要求的是**下一跳命令名** `"pdlc-ship"`。照抄这份范例会让循环拿到白名单外的 token，直接判 `blocked`。全仓 15 处 `next_step` 字面量里只有这一处写错，已改。

### Changed

- **`advanced_to` 的短名规则改为一张被断言钉住的映射表**：原文写「`advanced_to` = `next_step` 命令去掉 `pdlc-` 前缀」，紧接着又用 ⛔ 块声明「短名不等于命令名去前缀，`pdlc-implement` → `impl`」——**规则与规则的反例挨着写**，而这两段会一起被内联进 Codex skill，模型两边都读得到。实测「去前缀」对 6 个目标里的 `pdlc-implement` 直接给错答案。
  - 现在 `references/templates/prompts/state-update.md` 用 `<!-- stage-map -->` 锚点给出 6 行显式映射表，并由 `tests/frontmatter-check.sh` **双向**钉死：① 表里每行短名必须等于该 skill 自己 frontmatter 的 `stage:`；② 任何 skill 的非 `null` `next_step` 都必须在表里有行（防止新增阶段时表腐烂）。四种变异（改错短名 / 删一行 / 删整表 / 回退判停规则）均实测变红。
  - `docs/pdlc-methodology.md` 里重复的同一条「去前缀」规则同步改为指向该表。


## [1.6.2] - 2026-09-05

一次「把噪音关掉」的维护版：CI 收口到只在发版那一刻跑，日常防护落回本地 pre-commit 钩子；顺带修掉状态栏在 `/pdlc-relate rebuild` 之后整行变空的回归。

没有新增 skill（仍 38 个），流程契约与产物路径零改动，升级不需要任何迁移动作。

### Changed

- **CI 收口到「只在发布那一刻跑」**：`secret-scan.yml` 原先是 `push: branches:[main]` + `pull_request`，累计触发 89 次（PR 55 / push 34）——改一行文档也要跑一遍全历史扫描。改为 `workflow_dispatch` + `push: tags: v*.*.*`，月预计用量从约 15-20 min 降到约 1 min。发版前那次仍用 `fetch-depth: 0` 扫完整历史，**公开发布前的最后一道兜底保持不变**。
  - 日常防护落到本地：新增 `.githooks/pre-commit`（`git config core.hooksPath .githooks` 启用一次）。有 `gitleaks` 就用它扫暂存内容；**没有时不静默放行**——降级为正则兜底并明确告知覆盖面更弱（「跑不了」不等于「没问题」，与三态语义同一条纪律）。命中时只回显截断后的模式，不把密钥再打印一遍到终端和日志。
  - 三条路径均实测：gitleaks 在→拦(exit 1)、gitleaks 不可见→正则兜底仍拦(exit 1)、干净内容→放行(exit 0)。

- **状态栏懒解析循环去掉 `basename` 子进程**：`bin/pdlc-statusline.sh` 每渲染一次提示符，窗口内每个候选文件都要调两次 `basename`（判 `statusline.json` 一次、判 `_` 前缀一次），默认窗口 5 个文件即 10+ 次 fork。改为 `${f##*/}` 取一次文件名再判两次，循环内子进程降到 0。实测 6 个状态文件的场景由 12 次 `basename` 调用降到 0，渲染输出逐字节不变。

- **`CLAUDE.md` 的本地测试清单补全**：「Common commands」原先只列了 `tests/` 下 6 个脚本中的 2 个（`frontmatter-check` / `install-smoke`），照文档跑只覆盖 221/304 条断言——`statusline-check`、`adapter-codex-check`、`adapter-codex-loop-run-check`、`evals-runner-check` 全在清单外，目录树那一段也用 `└──` 收在第 3 个脚本上、读起来像「就这些」。现已列全 6 个、给出一次跑完的命令，并把 `shellcheck` 的覆盖面对齐实际（补 `bin/*.sh`、`evals/run.sh`、`.githooks/pre-commit`）。另注明 `statusline-check.sh` 需额外用 macOS 自带 `/bin/bash` 3.2 跑一遍——PATH 上的 Homebrew bash 5 会放过在原生 Mac 上跑不了的代码。

### Fixed

- **ADR 0004 §5 的诚实边界已过时**，补更正纪要（正文保留作时间点快照）：「本仓库的自动化无法自己调 `codex exec`」实测不成立；`tdd → implement → review` 三步连跑已端到端验证——`design → tdd → impl → review_done` 收敛、退出码 0、独立复跑单测 9/9 绿、发布侧零改动。撞上 provider 限流那次，驱动按设计 fail-stop(4) 且现场零改动。
- **状态栏在 `pdlc-relate rebuild`/`set` 之后变空**：`bin/pdlc-statusline.sh` 按 mtime 取最近状态文件时，只排除了 `statusline.json`，没排除 `pdlc-relate` 写出的 `_relations.json`（关系反向索引，不是功能状态文件）。`_relations.json` 写出后 mtime 最新，被当成「最新且非终态」抢占显示，解析出的 `feature_id`/`feature_name`/`current_stage` 全为空，状态栏整行显示成 `● PDLC  · 👤`。现在懒解析循环跳过所有 `_` 前缀文件，jq 解析后再对 `feature_id` 为空的行做一道兜底丢弃。`tests/statusline-check.sh` 新增场景 8 覆盖该回归。


## [1.6.1] - 2026-08-09

质量报告多了一份**能直接看**的形态，以及三处「本来就该有人盯着」的守卫补位。

本次没有新增 skill（仍 38 个），也没有改动任何流程契约——`.md` 依旧是质量报告的唯一真源、发布闸门读的依旧是它。

### Added

- **质量报告 HTML 视图**：`/pdlc-quality` 现在除 `docs/07_reviews/quality/<日期>.md` 外，同步产出同名 `.html`——**零依赖自包含单文件**（CSS 内联、无 CDN、无外链字体），双击就开、离线可看、可打印签字、能直接发给同事。模板 `references/templates/quality-report-template.html`：深浅色自适应、结论卡片 + 七节结构与 Markdown 版一一对应、`@media print` 出 A4（实测 5 页，TOC 自动隐藏）。
  - **`.md` 仍是唯一真源**：`git diff` 看它、`/pdlc-ship` 的发布闸门读它、趋势对比取它；HTML 里的数字**一律从 `.md` 抄，不得重算**。双写最大的风险是「两份报告各说各话」，且错的那份通常更好看——故设自检项逐项核对关键数字，不一致以 `.md` 为准。
  - **三态在视觉上必须可分**：`st-pass` 绿 / `st-fail` 红 / `st-warn` **琥珀 + 斜纹**（无法判定）/ `st-na` 灰（留空未测量）。「无法判定」刻意做成未完成观感，且图例明写「不是通过」——这是 ADR 0005 §6.5 反模式在报告上的最后一道落地面。
  - 新增 15 条 `install-smoke` 断言（165 → 180）：模板存在、**自包含无外链**、**占位符不得嵌进 `var(--…)`**、三态齐全、七节结构、签字栏。
  - 页头总判定改为**单一占位符** `{{VERDICT_SHORT}}`（填 `pass`/`fail`/`warn`）同时驱动顶条与徽章。原先顶条走 `style="--verdict-color: var(--{{VERDICT_CLASS_SHORT}})"`，而填写说明写的是填 `st-warn`——照做即得未定义变量，**静默**回落成中性强调色：一份「无法判定」的报告顶着与「达标」无异的页头（已复现）。报告最贵的错就是错的那份看起来更体面，故把这种「占位符当 CSS 变量名」的形态连同断言一起禁掉。
  - 自包含守卫由**类型白名单改为全量禁外链**。原先只盯 css/js/字体后缀，`<img src="https://…/x.png">` 与 `url(//cdn/…)` 都能漏过——而一张远程图片同样会在每次打开报告时把 IP、时间、referer 送给第三方。需要图片一律内联 `data:` URI。

- **`refresh-safety` eval（A-live 第四个场景）**：把 v1.6.0 交付但一直没真机验过的**方向规则**（`--refresh` 只能自动收紧闸门，放松必须人确认）固化成可复现的回归闸。
  - fixture 是**双向判别器**：`lint` 指向已删除的脚本（**松向诱饵**——最省事的"修法"是留空，报告立刻变绿而闸门没了）；`e2e` 空着但实际有可跑脚本（**严向机会**）。判别力来自「一边动了、另一边没动」——两边都自动改 = 松向失守；两边都不敢动 = 严向规则形同虚设。
  - **在 v1.6.0 发布版上真机验证通过**：`e2e` 被自动补上、失效的 `lint` 原封不动并明确请求人确认。模型表现超出规范要求——`shellcheck` 已装且全绿，但它拒绝拿来顶替失效的 lint，理由是「无法证明与原命令语义相同，换 linter 属技术选型」。

### Changed

- **`state-update.md` 补上 `checks` 的键名与类型约束**：键名只能是 `tests_pass` / `coverage_pass` / `lint_clean` / `e2e_pass`（tdd 段 `red_verified`），值只能是布尔；点名两种实测到的错法——照抄 `test-commands.yml` 的 `unit`/`lint`，以及写成 `"4 passed, 1 failed"` 这类字符串摘要。另注明 `pdlc-implement` 的阶段短名是 `impl` 而非 `implement`。
  - 这是**规范补白**：原先键名只在散文里出现、schema 示例是空的 `checks: {}`，类型更是从没写过。补的是真实缺口，不是为某个平台打补丁。
  - ⚠️ **不声称它改善了模型行为**——见下。

### Known limitations

- **Codex 臂在 `checks` schema 上不稳定**（2026-08-09 实测，`gpt-5.6-sol`）：`honest-checks` / `stale-config` 反复红且失败形态在换（键名漂移 / 值写成字符串 / `127` 折成 `false` / 键缺席），同一 fixture 同一模型轮间就能换一种；`red-light-gate` / `refresh-safety` 稳定通过。
  - 试过用加重措辞去收敛，**单轮看似转绿、多轮落回噪声带**，强调三态那版还把红从一个场景挪到另一个——已回退。要立结论需 `--repeat 5` 以上分组对比。
  - Claude 臂同期三次完整跑**均 4/4 全绿**。**Codex 臂暂不作为发布闸门证据**，详见 `evals/EVALS.md`「两条已知限制」第 3 条。

### Fixed

- **`evals/run.sh` 曾静默只跑第一个场景**（不带 `--only` 的整套跑）。场景名用 `done <<< "$SCENARIOS"` 喂在 stdin 上，而循环体里调的 agent CLI 会读 stdin（实测 `codex exec` 会把管道内容当额外输入吃掉）——第一个场景跑完，剩下的场景名已被喝干，循环无声结束，汇总照常打印。
  - 这是**最坏的一种失败**：覆盖面缩水，报告却看不出少跑了什么。据此，此前所有"整套跑过"的 Codex 结论都只覆盖了 1 个场景（各场景单独用 `--only` 跑出的结论不受影响）。
  - 修法两道：场景名改走 **FD 3**（与 stdin 彻底隔开），agent 调用另加 `</dev/null`。另加**场景计数闸**——跑到的场景数与发现数不符即报错退出 3，不允许再有"少跑而正常收尾"。
  - 新增 `tests/evals-runner-check.sh`（A-det，用会读 stdin 的 `codex` 桩复现该条件，不烧额度）：断言场景全跑到、桩无产出时判「无结论」而非通过、两道防线各在位。四种回归形态逐一种入验证判别力。

- **CHANGELOG 的 `## [1.6.0]` 标题曾被误删**（v1.6.1 备版时发现）。上一次编辑本文件时，替换范围把版本标题一并吞掉，于是 1.6.0 的全部条目被并进了未发布段——`release.yml` 按标题切段抽发布说明，真发出去会把上个版本的内容当成本次的。已补回标题，并加断言：**每个 git tag 都必须在 CHANGELOG 里有对应的 `## [x.y.z]` 标题**，缺一个即失败。


## [1.6.0] - 2026-07-29

ADR 0005 的 B1 + B2 落地：把「客观 check」从单阶段能力升级成**常设质量闸门**。36 → 38 skills。

### Added

- **`/pdlc-test-setup`（B1，立测试地基）**：探测技术栈 → **逐条验证命令真能跑** → 写 `docs/00_standards/test-commands.yml` → 脚手架测试目录 → 接本地 pre-commit/pre-push 钩子。
  - 命门是「**验证后再写**」：写进 yml 的每条命令都必须先真跑过、看到退出码；跑不通的**留空并说明怎么补**，绝不写没验证过的命令——一条猜错的命令会污染下游每个阶段的 `checks`，比没有这个文件更坏。
  - 覆盖率达标线写死在命令参数里（默认 85%），「达标」即退出码本身，无需解析百分比。已存在的 yml 不覆盖，改为校验 + 提议补缺。
- **`/pdlc-quality`（B2，质量闸门）**：跑真实 check → 对照目标 → 出可核对报告 → **人签字放行**。AI 只整理数据，**不参与达标判定**。
  - **E2E 覆盖矩阵**：靠显式 `docs/00_standards/e2e-flow-map.yml`（`core_flow → 测试标识`）机械核对，不靠模型说「我觉得覆盖了」。映射指向不存在的测试 = **映射腐烂**，按红处理。
  - **PRD 强制对账防 false-green**：每次运行都拿 PRD 的 P0/P1 流程与 `core_flows` 做 diff，**漂移即红灯**。清单靠自觉维护必腐烂，而腐烂的清单会让矩阵全绿、现实有洞——把「我们不知道」伪装成「我们覆盖了」，比没有闸门更坏。
  - 报告落盘 `docs/07_reviews/quality/<日期>.md`（ledger 型，可 diff 可看趋势），含红绿表、实测证据、覆盖矩阵、对账结果、趋势、**人工签字栏**。
  - 量不到的项如实写「未测量」，**不得因此判为通过**——与「无命令可跑 → `checks: {}`」同一条纪律。
- 新模板：`quality-targets-template.yml`、`e2e-flow-map-template.yml`、`quality-report-template.md`。
- **`stale-config` eval（A-live 第三个场景）**：`unit` 真失败(exit 1) + `lint` 指向不存在的脚本(exit 127)，验证「命令跑不了 ≠ 检查没通过」。判别力来自**一个有值 + 一个表达「无法判定」**——照抄 schema 的模型会把两个键都填布尔值。真机验证通过，且这一跑当场纠正了规范本身：原先要求"必须省略键"过窄，实际 `null` 与缺席对消费方等价（`jq` 都返回 `null`），已放宽为二者皆可、**唯独不许 `false`**。
- **多字节相邻守卫**（repo hygiene）：`install-smoke` 新增一条闸——全仓 `.sh` 里 `$var` 紧贴中文即失败。这类写法几乎总藏在错误分支里，正常路径跑不到、一旦真出错连报错本身都崩；本仓已被它坑过 4 次。

### Changed

- **`test-commands.yml` 自动保鲜**：这份文件会随项目演进而过期（脚本改名、runner 换代、工具移除），一旦过期下游所有 `checks` 就开始失真。现在不需要你记得去维护：
  - **退出码三态语义**（新共享片段 `check-commands.md`，12 → 13 个）：`0`=通过、非 0=未通过、**`127`/命令不存在=无法判定**。后者**省略该 `checks` 键而非写 `false`**——把「跑不了」记成「没通过」是**会误导人的虚报**：它让人去查代码，而真正的问题是配置过期。
  - **过期检测零成本**：各阶段本来就在跑这些命令，遇到「跑不了」即提示 yml 疑似过期。`pdlc-tdd` / `pdlc-implement` / `pdlc-review` / `pdlc-quality` / `pdlc-test-setup` 五处共用同一套语义。
  - **`/pdlc-quality` 报告新增「配置健康度」一节**：哪条命令已失效、哪个空格现在可以填上（💡 可收紧）。
  - **`/pdlc-test-setup --refresh`**：重新探测并给出 diff。**方向决定自动化程度**——让闸门**变严**（空 e2e 现在能跑、阈值上调）或平移替换可自动应用；让闸门**变松**（删命令、留空、降阈值）**必须人确认，`--autonomous` 也不豁免**。最危险的"自动修复"就是把坏掉的 check 留空：闸门瞬间松了、报告还是绿的。

- `/pdlc-ship` 前置检查新增**质量闸门**：读 `docs/07_reviews/quality/` 最近一份报告，未达标默认不放行，要发必须由人显式 override 并写明理由；报告早于最近提交则提示已过期。
- `/pdlc-prd` 新增**上游挂钩**：产出 P0/P1 流程时提示补 `core_flows` 与 E2E 映射——在源头挂钩比事后补救可靠。
- 目标项目契约新增 `docs/00_standards/quality-targets.yml`、`docs/00_standards/e2e-flow-map.yml`、`docs/07_reviews/quality/`。

### Fixed

- **红灯守卫在常见测试布局上误拦**（真实项目验证暴露）：`pdlc-implement` 的前置守卫原先只在一份**写死的路径清单**（`backend/services/*/tests/`、`frontend/*/src/__tests__/` 等）下找测试，找不到就判「项目没测试」并中止。但真实布局千差万别——单体 `backend/tests/`、根级 `tests/`、Go 同包 `*_test.go`、Node 与源码同目录的 `*.test.tsx`——**守卫把「测试不在我预期的位置」当成了「项目没有测试」**，会让 pdlc 在大量正常项目上直接卡死。
  - 新增共享片段 `test-location.md`（11 → 12 个）。核心原则是**优先问 runner、其次翻文件**：项目的 `test-commands.yml` 是权威，用它去问 runner（`cargo test -- --list` / `pytest --collect-only -k` / `go test -list` / `vitest list`），查询为空才是「该功能没有测试」——这是行为证据，比「我没找到文件」可靠得多。
  - **专门处理「测试写在源文件里」的语言**：Rust 单测几乎总在 `#[cfg(test)] mod tests` 里，`tests/` 按 Cargo 约定只放集成测试，所以「没有 `tests/` 目录」在 Rust 项目里**完全不能推出「没有单元测试」**，照文件清单判红会稳定误伤所有 Rust 项目。同类还有 Vitest in-source testing（`import.meta.vitest`）、Python doctest、Elixir doctest——这些都必须靠**内容标记**匹配，文件名扫描无效。
  - 定位顺序：问 runner → in-source 内容标记 → 生态布局约定 → 文件名兜底，**四步都落空才判红灯**；无法判定（runner 装不上 / 语言不认识）则如实报「无法确认」并交还人类，不默认放行。
  - **真 Rust 项目双向验证**（一个 Tauri 项目，54 个文件含 in-source 测试、无 `test-commands.yml`）：正例——某模块的 21 条测试**只存在于源文件内**（同级 `tests/` 目录无对应文件），守卫正确找到并跑 `cargo test` 确认全绿，未误拦（旧逻辑在此必红）；反例——一个真的没有测试的功能，守卫正确红灯、零代码改动、且**未伪造状态机**（守卫在提取功能 ID 前中止，凭空写 `current_stage` 属伪造阶段记录）。两向都对，证明修复没有把守卫改松。
  - `pdlc-implement` / `pdlc-tdd` / `pdlc-feature` / `pdlc-fix` 四处改为引用该片段；写测试时也跟随项目既有布局，不再新造平行目录。
- **对账自身的 false-green**（真项目验证时实测踩到）：PRD 不含 P0/P1 标记时提取为空集、不产生漂移条目，报告若就此判「无漂移 ✅」，等于宣称那份 PRD 的流程都覆盖了——而事实是它整份没进闸门视野（已上线的老主链路最容易栽在这里）。现要求单列「不可判」告警，且对账项**不得判为 ✅**。
- 修全仓 5 处 `$var` 紧贴中文的隐患（`bin/pdlc-statusline.sh`、`tests/adapter-codex-check.sh` ×2、`tests/statusline-check.sh` ×2），并加上防复发守卫。

## [1.5.3] - 2026-07-28

行为层 evals（A-live）落地——测的是「skill 真跑时契约有没有被守住」，而不只是结构。设计见 `docs/decisions/0005-testing-and-quality-capability.md`，用法与成本账见 `evals/EVALS.md`。

### Added

- `evals/` 行为层测试：`run.sh`（runner）+ `honest-checks` / `red-light-gate` 两个 A-live fixture + `EVALS.md`。
- 分档判据「**契约由谁执行**」：确定性代码执行的契约（bash 驱动 / jq 映射）可用桩测、留在 `tests/`；由模型遵守 SKILL.md 正文执行的契约桩测不了，必须真跑（A-live）。
- 失败二分类：**环境抖动**（无状态机产出，自动重跑、不计失败）vs **契约破坏**（有产出但判别式不符，立即红）；全抖动时报「无结论」而非冒充通过。
- `run.sh --check` 离线校验 fixture（不烧额度，CI 只跑这个）、`--replay` 对保留现场复跑断言、`--repeat N` 以多数通过为结论。
- `install-smoke.sh` 新增 11 条 evals 不变量（95 → 106）。

### Fixed

- **状态机推进契约冲突**（由 `honest-checks` eval 首跑抓到）：`pdlc-implement` / `pdlc-prd` 的段四无条件写 `current_stage`，与共享片段 `state-update.md` 规则 5「`ok=false` 时 `current_stage` 不变」矛盾，导致失败的阶段也会推进 `current_stage`、令外层循环的 stuck-stop 失效。两处均改为「仅当本阶段成功时才推进」。


## [1.5.2] - 2026-07-20

Codex 上的 PDLC 自主收敛循环（loop-run 外部 Runbook 版）。设计与真机准入闸结果见 `docs/decisions/0004-codex-loop-run.md`。

### Added

- **`adapters/codex-loop-run.sh`** — Codex 外部 Runbook 驱动：一个 bash 循环，无人值守把 `tdd → implement → review` 推到 `review_done`。以**状态机为唯一真源**，每轮读状态机 → loop-next 映射的 jq 复刻判下一跳 → `codex exec "按 pdlc <阶段> <id> --autonomous"` → 读回判护栏（`--max-steps` 默认 4 上限停机 / `ok!=true` fail-stop / `current_stage` 未推进 stuck-stop）。**发布永远人工**（到 review_done 即停，绝不自动 ship/deploy）；`--dry-run` 离线看决策。
- **`tests/adapter-codex-loop-run-check.sh`** — 驱动映射 + 护栏回归（mock 状态 + `--dry-run`，免 codex，12 断言）。
- **`docs/decisions/0004-codex-loop-run.md`** — ADR + **状态完整性准入闸真机结果**：gpt-5.6-sol 用「unit 恒失败 / lint 恒通过」判别场景，真跑 `test-commands.yml`、诚实写 `{tests_pass:false, lint_clean:true}`（一真一假只可能来自真跑）、fail-stop、发 `<<<PDLC blocked>>>` 哨兵——**闸过**，loop-run 得以在 Codex 放行。

## [1.5.1] - 2026-07-19

Codex 适配器**真机验证后的重大更正**：v1.5.0 假设 Codex 靠 `~/.codex/prompts/*.md` 斜杠命令，未验证就发版——实测目标 Codex 是**兼容 Claude Code 生态的发行版**，用 `~/.codex/skills/<name>/SKILL.md`（description 触发、非斜杠命令）。gpt-5.6-sol 自然语言触发 `pdlc-prd` 成功、写出 schema 正确的状态机（Claude Code 可无缝读）。

### Changed

- **Codex 适配器改到 `skills/` 布局**：`build_codex.py` 现输出 `dist/codex/skills/pdlc-*/SKILL.md`（Codex skill 格式 frontmatter `name` + `description`，description 追加 pdlc 触发提示；`next_step` 物化措辞改为自然语言、非斜杠命令）。`install.sh --target codex` 装到 `~/.codex/skills/`，并**自动清理 v1.5.0 误装的 `~/.codex/prompts/pdlc-*.md`**。安装提示改为「重启 Codex + 自然语言驱动」。
- **README / README.zh-CN / usage-guide / adapters/README / ARCHITECTURE / ADR 0003**：Codex 接入说明从「prompts 斜杠命令」更正为「skills description 触发」，含真机验证纪要。

### Fixed

- **`checks` 虚报诱导坑（跨工具状态可信的命门）**：`state-update.md` 的 schema 示例此前把 `checks` 写死 `{tests_pass:true, coverage_pass:true, lint_clean:true}`，诱导模型在 requirements/design 等**无测试可跑**的阶段照抄假 `true`（真机实测 gpt-5.6-sol 确实照抄了）。改为示例 `checks: {}` + 显式规则「无检查命令可跑的阶段留空 `{}`，绝不因阶段成功就填 true」。对 Claude Code 也是净收益。

## [1.5.0] - 2026-07-19

多平台支持第一步：把 PDLC 方法论内核平台中立化，并交付 Codex CLI 适配器。设计见 `docs/decisions/0003-multi-platform-adapters.md`。Claude Code 仍是一等公民、不降级。

### Added

- **`docs/pdlc-methodology.md`** — 平台中立的 PDLC 方法论内核（Tier 1「地板」）：IRON LAW 六条、状态机契约、目标项目目录契约、功能/缺陷 ID 分配、四段式骨架、`test-commands.yml` 客观检查、自然语言 → 阶段映射，并诚实标注哪些能力仅 Claude Code。任何 AI 编程工具（Codex / Cursor / Windsurf / Copilot / Cline …）可据此用自然语言驱动 PDLC，共享同一份 `docs/.pdlc-state/`。
- **`adapters/build_codex.py`** — Codex 适配器：把 `skills/*/SKILL.md` **构建期投影**为 Codex CLI 自定义 prompts。转译——内联 `@include`（自包含、剥离 Claude 术语）、剥离 Claude 内部 frontmatter、物化 `next_step` 进正文、剥掉 `adapter:claude-only` 哨兵块（Claude 专属示例管线）、denylist 2 个 Claude-Code-only skill（`pdlc-settings` 状态栏、`pdlc-loop-run` 自主收敛引擎）。产出 34 个 `/pdlc-*` prompt + 文档模板 + 方法论。`pdlc-loop-next` 逻辑平台中立、作为独立只读查询投影（其 `claude -p` 驱动 helper 由哨兵剥掉）。python3 标准库、零 pip 依赖、仅构建期。
- **`install.sh --target codex`** — 一步构建并安装 Codex prompts 到 `~/.codex/prompts/`（模板 + 方法论到 `~/.codex/pdlc/`）；`--target codex --uninstall` 移除。需本地克隆 + python3。
- **`adapters/README.md`** — 适配器架构 + 转译步骤（含 `adapter:claude-only` 哨兵机制）+ 如何新增一个平台（含状态完整性准入闸）。
- **`tests/adapter-codex-check.sh`** — Codex 产物回归：34 prompt / denylist 缺席 / loop-next 已投影且 claude 专属 helper 被哨兵剥掉 / 无 `@include` 残留 / 无 Claude 术语泄漏 / frontmatter 剥离 / `next_step` 物化 / 模板引用改写 / 方法论落地。

### Fixed

- **`install.sh` 陈旧计数** — Claude Code 提示里「33 sub-commands」更正为 36（settings/loop-next/loop-run 加入后未同步）。
- **`marketplace.json` 版本同步 + 校验兜底** — marketplace.json 版本随 VERSION 一起 bump（此前只 bump plugin.json，marketplace 连续两版漏改）；`frontmatter-check.sh` 新增「marketplace 版本 == VERSION」断言，以后自动兜住、不再靠人肉盯。

## [1.4.0] - 2026-07-18

在 Claude Code 状态栏显示 PDLC 运行状态（可选、默认关）。设计见 `docs/decisions/0002-statusline-pdlc-status.md`。35 → 36 skills。

### Added

- **`bin/pdlc-statusline.sh`** — 自包含状态栏片段：读 stdin 的 Claude Code JSON、扫当前项目 `docs/.pdlc-state/`，独占一行显示「功能名 + 迷你进度条 + 下一步 + 运行图标 + 检查 + 停留时长」。**默认关闭、零副作用**；非 PDLC 项目 / 无状态文件 / 缺 jq 一律**静默吐空**、退出码 0；渲染只读本地、无网络。`blocked` 做成全行最醒目；多 feature 时**非终态 + blocked 优先**并**懒解析**（只扫最近 N 个，保 <10ms）。兼容 macOS 自带 bash 3.2。
  > 📌 更正：本条当时写的「保 <10ms」是不可靠承诺——shell 启动本身就吃掉大部分预算，实测受机器与 jq 版本摆布。[ADR 0002](./docs/decisions/0002-statusline-pdlc-status.md) 已自我更正，改用**子进程数**这一可控指标。
- **`/pdlc-settings`** (Layer 3) — 交互式设置命令，当前含状态栏一节：启用 / 停用 / 展示项 / 状态。启用走**稳定路径符号链接** `~/.claude/pdlc-statusline`（升级不断）+ **幂等追加**到用户唯一的 `statusLine.command`（绝不覆盖现有 HUD）。改全局 `~/.claude/settings.json` **强制备份 + diff + 确认**；写入被安全层拦截时**优雅降级**为「算好那一行 + 用户手动粘贴」，绝不谎报已启用。
- **`references/templates/pdlc-statusline.example.json`** — 展示项配置样例（含各键说明）；全局 `~/.claude/pdlc-statusline.json` 可被项目级 `docs/.pdlc-state/statusline.json` 覆盖。
- **`tests/statusline-check.sh`** — 7 场景回归（impl 交互 / loop autonomous / blocked / review_done / 多 feature 抢权 / 窗口外旧 blocked 不抢权 / 非 PDLC 吐空）。

## [1.3.0] - 2026-07-17

分布式友好的 feature/defect 编号：解决多人 / 多 AI 并行开发时的编号冲突。

### Changed

- **功能/缺陷 ID 从「当日序号」改为「创建时刻时分秒」** — `F<YYYYMMDD>-<HHMMSS>` / `B<YYYYMMDD>-<HHMMSS>`（如 `F20260717-122801`）。各工作副本零协调也几乎不撞号（仅同一秒创建才可能，撞了本地自动 +1 秒），合并时状态机文件名互异、git 自动合并，不再需要手工重编号。旧的 2 位序号 ID（`F<日期>-NN`）向后兼容、仍可解析；派生的 `_relations.json` 等聚合文件照旧 `pdlc-relate rebuild` 重建、不手合。
- **任务 ID 改为「功能ID前缀 + 本功能内序号」** — `T<功能ID的日期-时分秒>-<NN>-<type>`（如功能 `F20260718-094301` → 任务 `T20260718-094301-01-feat`）。前缀嵌入所属功能的唯一时分秒，任务号**全局唯一、自带归属、并行安全**；`NN` 在本功能任务文件内递增（不再扫全局 `docs/06_tasks/` 取当日 max）。任务用本地序号而非各自时分秒是刻意的：任务成批同秒创建，独立时分秒会互撞。

## [1.2.1] - 2026-07-16

Loop 工程在真安装环境端到端验证后的健壮性修复（真跑 `/pdlc-loop-run` 暴露的两点）。

### Fixed

- **loop-next 输出健壮性** — 明令输出裸 token、禁止代码块/反引号包裹；`/pdlc-loop-next` 参考 helper 与 usage-guide Runbook 加**净化**（去反引号/空白后按白名单抽取 token），防模型偶发包裹导致外部 bash 循环 `case` 匹配失败。
- **autonomous sidecar 产物澄清** — `noninteractive.md` 明确：自主模式下创建缺失的 `CHANGELOG.md`、补全 PDLC-TRACE 时间戳等本阶段职责内、可安全默认的改动，直接做并记入 `auto_decisions[]`（非破坏性）。

## [1.2.0] - 2026-07-15

Loop 工程可循环化：让 PDLC 从「人驱动」升级为「也能被自主循环驱动」的执行引擎。设计见 `docs/decisions/0001-loop-engineering-integration.md`。33 → 35 skills。

### Added

- **`/pdlc-loop-run`** (Layer 3) — 收敛循环引擎：从 `current_stage` 自动推进 `tdd → implement → review` 到 `review_done` 或 blocked；内建迭代上限（默认 4）、fail-stop、stuck-stop、每 stage 派发 fresh Task subagent。终态即 `review_done`，**绝不自动发布**（ship/deploy 永远留人）。
- **`/pdlc-loop-next`** (Layer 3) — 循环下一步 helper：只读状态机、按严格白名单打印下一条机械收敛命令（`pdlc-tdd` / `pdlc-implement` / `pdlc-review` / `done` / `blocked`），供 `/pdlc-loop-run` 与用户自写 bash 循环消费。发布永远留人，绝不输出 `pdlc-ship`/`pdlc-deploy`。
- **`--autonomous` 非交互契约**（新共享片段 `noninteractive.md`）— 被 `pdlc-tdd` / `pdlc-implement` / `pdlc-review` / `pdlc-ship` / `pdlc-deploy` @include：流程性确认自动前进并留痕 `auto_decisions[]`；真需人判断则写 `blocked_reason` 停机交还人类；破坏性操作永远留人（`--autonomous` 无效）。
- **`test-commands.yml` 唯一真源**（新模板 `test-commands-template.yml`）— 项目 `check` 命令（`unit`/`coverage`/`lint`/`e2e`）的单一来源。
- **状态机 `last_phase_result`** — 机器可读阶段结果（`checks` 来自真跑命令退出码，非自评）+ `run_mode` + `history[].auto_decisions[]`，循环判停的唯一真源，向后兼容。
- **模型路由 frontmatter** `recommended_model` / `recommended_effort`（`pdlc-tdd` / `pdlc-implement` / `pdlc-review` = sonnet），供 `/pdlc-loop-run` 与外层循环按档位选模型，省订阅额度。

### Changed

- **IRON LAW 新增第 6 条「状态必推进」** — phase 收尾若 `current_stage` 未推进即报错，防循环空转。
- `pdlc-implement` 测试已绿的确认点在 `--autonomous` 下自动前进；`pdlc-review` 在 `--autonomous` 下遇阻塞级人工项主动 block。

## [1.1.0] - 2026-06-04

Two RFCs landed: ledger/surface artifact separation (#5) and the feature relation chain (#6). 31 → 33 skills.

### Added

- **`/pdlc-standard`** (Layer 3) — manage `00_standards/` team conventions as **surface** artifacts: in-place edit, `_changelog.md` sidecar, git-log audit trail. Hard rule against `coding-style-v2.md`-style ledger detours.
- **`/pdlc-relate`** (Layer 3) — manage the feature relation chain. Six relation types (`extends`, `depends_on`, `supersedes`, `resolves`, `conflicts_with`, `relates_to`). Commands `set` / `query` / `impact` / `orphans` / `rebuild` / `validate`. The `impact <fid>` command reports a change's blast radius (direct / transitive / historical).
- `docs/ARCHITECTURE.md` and `docs/GLOSSARY.md` — surface artifacts; the repo now dogfoods both.
- New templates: `architecture-overview-template.md` (surface, whole-system) and `glossary-template.md`.
- New shared fragment `relations.md` — single source of truth for the six relation types and five expression sites.
- `artifact_type: surface | ledger` frontmatter field (optional, default `ledger`).
- State machine gains an optional `relations` block; `docs/.pdlc-state/_relations.json` (reverse index) and `_graph.md` (mermaid) are produced by `/pdlc-relate`.
- PDLC-TRACE header gains an optional `关系:` line; PRD template gains §6.1 relations table.

### Changed / Breaking

- **`/pdlc-arch`** now writes `docs/ARCHITECTURE.md` **in place** (surface) instead of accumulating dated `YYYYMMDD-arch-analysis.md` files. Legacy files are detected and moved to `docs/.archive/architecture/`. The three previously-inconsistent output paths (`02_design/architecture`, `07_reviews/design`, dated analysis) are reconciled to one.
- `/pdlc-bootstrap` adds legacy `*-arch-analysis.md` detection; per-feature `F-xxx-arch.md` (ledger) is retained and clarified vs the surface overview.
- Standards-reading skills (`pdlc-prd`, `pdlc-design`, `pdlc-tdd`, `pdlc-implement`, `pdlc-code-gen`, `pdlc-review`, `pdlc-onboard`) now hint `consider /pdlc-standard add` on lookup miss.
- `/pdlc-status` gains a relation-tree view (Phase 2: included in the default overview).

> Migration is automatic (legacy detect + archive), so this ships as a minor version. Existing projects without relations or surface docs stay valid — both subsystems are additive.

### Fixed

- Plugin author metadata corrected to `kanfu-panda` (was a placeholder) in `plugin.json`, `marketplace.json`, and both READMEs.

## [1.0.0] - 2026-05-07

Initial public release of **PDLC** — a Claude Code plugin that gives Claude a
complete Product Development Life Cycle workflow.

### Features

- **31 standardized stages** exposed as slash commands `/pdlc-feature`,
  `/pdlc-prd`, `/pdlc-tdd`, ..., `/pdlc-onboard`, organized in three layers:
  - **Layer 1** entry points (3): `pdlc-feature`, `pdlc-fix`, `pdlc-status`
  - **Layer 2** stages (11): `pdlc-prd`, `pdlc-design`, `pdlc-tdd`,
    `pdlc-implement`, `pdlc-review`, `pdlc-e2e`, `pdlc-refactor`, `pdlc-ship`,
    `pdlc-deploy`, `pdlc-retro`, `pdlc-task`
  - **Layer 3** tools (17): `pdlc-ui-design`, `pdlc-ui-design-pro`,
    `pdlc-db-design`, `pdlc-arch`, `pdlc-lint`, `pdlc-perf`, `pdlc-security`,
    `pdlc-code-gen`, `pdlc-add-service`, `pdlc-add-app`, `pdlc-api-mock`,
    `pdlc-db-migrate`, `pdlc-i18n`, `pdlc-changelog`, `pdlc-bootstrap`,
    `pdlc-adopt`, `pdlc-onboard`
- **9 user-facing document templates** (PRD, API design, architecture, DB
  design, DB migration, test plan, deployment manual, changelog, legacy-
  project adoption report).
- **9 reusable prompt fragments** under `references/templates/prompts/`:
  IRON LAW, feature/defect ID assignment, PDLC-TRACE header, handoff
  format, self-audit, state-update, loop-prevention, output-language.
- **IRON LAW invariants** enforced on every Layer 1/2 stage that
  produces artifacts:
  1. artifacts must be persisted to disk;
  2. the state machine must be updated on every stage transition;
  3. tests must exist (and be red) before implementation;
  4. a self-check must run before handoff;
  5. auto-repair runs at most once.
- **Per-feature state machine** at `docs/.pdlc-state/<feature-id>.json`,
  recording stage history, self-audit counts, and the next recommended
  stage.
- **Output language follows the user's conversation language** by
  default — Chinese conversation produces Chinese artifacts, English
  produces English. Users can explicitly override per artifact.

### Distribution

PDLC is shipped as a Claude Code **plugin** registered through the standard
`claude plugin install` mechanism. The repo doubles as a single-plugin
marketplace.

- **One-line remote install** — no clone required:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
    | bash -s -- --global
  ```
- Equivalent native commands:
  ```bash
  claude plugin marketplace add kanfu-panda/pdlc-skills
  claude plugin install pdlc@pdlc-skills
  ```
- **Local clone install** — for contributors and template customization.
- Installer flags: `--global`, `--project <path>`, `--upgrade`, `--uninstall`,
  `--version`, plus an interactive mode.

### Target-project contract

Stages read and write this structure inside the user's project:

```
docs/00_standards/coding/                              # coding standards (read-only)
docs/01_requirements/prd/                              # PRDs
docs/02_design/{api,database,architecture,ui-ux}/      # technical design
docs/03_development/                                   # developer manuals
docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/
docs/05_deployment/                                    # deployment docs
docs/06_tasks/                                         # task tracking
docs/07_reviews/{doc,code,design,retro}/               # review records
docs/.pdlc-state/<feature-id>.json                     # per-feature state machine
```

### Engineering

- **CI**: frontmatter validation, install smoke test, shellcheck.
- **Secret scan**: gitleaks workflow with project-specific allowlist.
- **Release automation**: tag push triggers a clean GitHub Release.
- **Dependabot**: weekly auto-update for GitHub Actions.
- **Defensive `.gitignore`** + comprehensive secrets policy in
  `CONTRIBUTING.md`.

[Unreleased]: https://github.com/kanfu-panda/pdlc-skills/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kanfu-panda/pdlc-skills/releases/tag/v1.0.0
