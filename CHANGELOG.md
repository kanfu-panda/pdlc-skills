# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **多字节相邻守卫**（repo hygiene）：`install-smoke` 新增一条闸——全仓 `.sh` 里 `$var` 紧贴中文即失败。这类写法几乎总藏在错误分支里，正常路径跑不到、一旦真出错连报错本身都崩；本仓已被它坑过 4 次。

### Changed

- `/pdlc-ship` 前置检查新增**质量闸门**：读 `docs/07_reviews/quality/` 最近一份报告，未达标默认不放行，要发必须由人显式 override 并写明理由；报告早于最近提交则提示已过期。
- `/pdlc-prd` 新增**上游挂钩**：产出 P0/P1 流程时提示补 `core_flows` 与 E2E 映射——在源头挂钩比事后补救可靠。
- 目标项目契约新增 `docs/00_standards/quality-targets.yml`、`docs/00_standards/e2e-flow-map.yml`、`docs/07_reviews/quality/`。

### Fixed

- **红灯守卫在常见测试布局上误拦**（aim-quant 真项目验证暴露）：`pdlc-implement` 的前置守卫原先只在一份**写死的路径清单**（`backend/services/*/tests/`、`frontend/*/src/__tests__/` 等）下找测试，找不到就判「项目没测试」并中止。但真实布局千差万别——单体 `backend/tests/`（aim-quant 即是）、根级 `tests/`、Go 同包 `*_test.go`、Node 与源码同目录的 `*.test.tsx`——**守卫把「测试不在我预期的位置」当成了「项目没有测试」**，会让 pdlc 在大量正常项目上直接卡死。
  - 新增共享片段 `test-location.md`（11 → 12 个）。核心原则是**优先问 runner、其次翻文件**：项目的 `test-commands.yml` 是权威，用它去问 runner（`cargo test -- --list` / `pytest --collect-only -k` / `go test -list` / `vitest list`），查询为空才是「该功能没有测试」——这是行为证据，比「我没找到文件」可靠得多。
  - **专门处理「测试写在源文件里」的语言**：Rust 单测几乎总在 `#[cfg(test)] mod tests` 里，`tests/` 按 Cargo 约定只放集成测试，所以「没有 `tests/` 目录」在 Rust 项目里**完全不能推出「没有单元测试」**，照文件清单判红会稳定误伤所有 Rust 项目。同类还有 Vitest in-source testing（`import.meta.vitest`）、Python doctest、Elixir doctest——这些都必须靠**内容标记**匹配，文件名扫描无效。
  - 定位顺序：问 runner → in-source 内容标记 → 生态布局约定 → 文件名兜底，**四步都落空才判红灯**；无法判定（runner 装不上 / 语言不认识）则如实报「无法确认」并交还人类，不默认放行。
  - **真 Rust 项目双向验证**（aitm，54 个文件含 in-source 测试、无 `test-commands.yml`）：正例——`cli.rs` 的 21 条测试**只存在于源文件内**，守卫正确找到并跑 `cargo test` 确认全绿，未误拦（旧逻辑在此必红）；反例——一个真的没有测试的功能，守卫正确红灯、零代码改动、且**未伪造状态机**（守卫在提取功能 ID 前中止，凭空写 `current_stage` 属伪造阶段记录）。两向都对，证明修复没有把守卫改松。
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
