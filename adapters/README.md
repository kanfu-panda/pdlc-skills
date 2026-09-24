# 平台适配器（Agent Skills 标准投影）

把 pdlc-skills 的**单一源**（`skills/*/SKILL.md`）**构建期投影**成符合 [Agent Skills 开放标准](https://agentskills.io/specification) 的 skill 集，
供 Claude Code 以外、支持这个标准的工具加载。设计与取舍见 [ADR 0007](../docs/decisions/0007-agent-skills-standard.md)
（它取代了 [ADR 0003](../docs/decisions/0003-multi-platform-adapters.md) 里「每个平台写一个转译器」的做法）。

## 心智模型

- **唯一源**：`skills/*/SKILL.md`。**永远只改这里**，不手维护投影产物。
- **Claude Code 直接用源码**（本仓库即插件），不经投影：顶层的 `argument-hint` 等字段 Claude Code 用得上，标准却不允许。
- **其它工具用同一份标准投影**：Codex、GitHub Copilot、Gemini CLI、OpenCode、Amp、Goose、Cursor……文件格式相同，
  区别只在装到哪个目录。所以新增一个工具通常不写代码，只是多一个安装位置 + 过准入闸。

## 投影做什么（`build_agent_skills.py`）

```bash
python3 adapters/build_agent_skills.py [输出目录]   # 默认 dist/agent-skills
python3 adapters/build_codex.py [输出目录]          # 同一份产物，默认 dist/codex（install.sh --target codex 用）
```

1. **内联片段**：源里的内联区块（`adapters/sync_skills.py` 生成）先折叠回裸标记，再内联；剥掉片段首行的来源注释
   和 `adapter:claude-only` 块（只对 Claude Code 成立的内容，如 `claude -p` 管线、到 `~/.claude/plugins` 下找脚本）。
2. **frontmatter 只留标准字段**：`name`、`description`（追加「用 pdlc …」触发提示）、`license: MIT`、
   `metadata`（`pdlc-layer` `pdlc-stage` `pdlc-next-step`，值一律为字符串，规范只允许字符串）。
   字符串都写成双引号，避免冒号、方括号被当成 YAML 语法。
3. **参数行改写**：「<标签>: `$ARGUMENTS`」改成「<标签>：用户请求里跟在技能名后面的内容」——只有 Claude Code 保证替换占位符。
4. **斜杠命令说明**：正文开头加一句「`/pdlc-<名字>` 指同名技能 `pdlc-<名字>`」，不逐处改写 400 多处引用（容易误伤示例与路径）。
5. **下一步**：`next_step` 写成正文末尾的「下一步（PDLC 链式推进）」。
6. **不投影**（2 个）：`pdlc-settings`（Claude Code 状态栏配置）、`pdlc-loop-run`（Task 版依赖 Claude 子代理）。
   共 36 个 skill 投影。多功能循环驱动 `scripts/pdlc-loop.sh` 随 `pdlc-status` 一起投影。
7. **模板与脚本**：随 skill 自带在 `assets/`、`scripts/` 下，连目录一起拷，不改写路径。

- **语言**：python3 **标准库**（零 pip 依赖），构建期专用、不进运行时。
- **校验**：`tests/adapter-agent-skills-check.sh` 内置一份与标准一致的确定性检查；本机有官方校验器 `agentskills`
  （`pip install skills-ref`）时再对全部产物跑一遍，没有则明确打印「跳过」。

## 安装位置

```bash
bash install.sh --target agents                  # ~/.agents/skills/（Copilot、Gemini CLI、OpenCode、Amp、Goose 读这里）
bash install.sh --target agents --project DIR    # DIR/.agents/skills/
bash install.sh --target agents --dest DIR       # 任意目录，如 .cursor/skills、.windsurf/skills
bash install.sh --target codex                   # ~/.codex/skills/
# 以上都可加 --uninstall；只写入、只删除 pdlc-* 目录，不碰同目录下的其它 skill
```

> ⚠️ 标准统一的是**加载与触发**，不是模型行为。某个工具能加载这些 skill，不代表它会老实写状态机——
> 见下方「新增一个工具」第 3 步的准入闸。

### Codex 自主收敛循环（`codex-loop-run.sh`）

`pdlc-loop-run` 的默认「Task 版」耦合 Claude 子代理派发、未投影；本脚本是它的**外部 Runbook 版**，无人值守把 `tdd → implement → review` 推到「评审通过、等发布」（`next_step: pdlc-ship`）。它只是 `bin/pdlc-loop.sh --platform codex` 的入口：多个功能、`--parallel`、`depends_on` 排序、运行记录与 `--status` 都由那个平台中立的驱动实现（见 [ADR 0006](../docs/decisions/0006-multi-feature-loop-driver.md)）。

```bash
adapters/codex-loop-run.sh <功能ID>... [--project DIR] [--max-steps N] [--parallel N] [--dry-run]
```

- **状态机是唯一真源**：每轮读状态机、用 loop-next 映射的 jq 复刻判下一跳、调 `codex exec "按 pdlc <阶段> <id> --autonomous"`、读回状态机判护栏。
- **护栏**（对齐 Claude 版 loop-run）：`--max-steps`（默认 4）上限停机、`ok!=true` fail-stop、`current_stage` 未推进 stuck-stop。
- **发布永远人工**：到「评审通过、等发布」（`next_step: pdlc-ship`）或更后即 `done` 停机，绝不自动 ship/deploy。
- `--dry-run` 停在首个决策、不真跑 codex（离线看决策 + 回归测试用）。
- **放行前提**：Codex 已过[状态完整性准入闸](../docs/decisions/0004-codex-loop-run.md)（真机验证 gpt-5.6-sol 真跑 test-commands、诚实写 checks、fail-stop、发 block 哨兵）。设计与真机结果见 ADR 0004。

## 新增一个工具

1. 查它读哪个目录、是否遵守 Agent Skills 标准（读 `name` + `description`、按描述触发、带着 `scripts/` `assets/`）。
   遵守的，**不写适配代码**：用 `--target agents`（它读 `.agents/skills/` 时）或 `--dest <它的目录>` 即可。
2. 偏离标准的地方（例如不支持 skill 目录里的脚本），才在投影或安装脚本里加针对它的处理，并加断言。
3. **过准入闸**（ADR 0003 §6.1）：在该工具上跑 `evals/` 的 `honest-checks`（造一个红灯测试，验证写进
   `docs/.pdlc-state/` 的 `checks` 来自真实退出码、`ok=false` 不虚报）。`evals/run.sh` 已有 claude / codex / copilot 三条臂，
   新工具照 copilot 臂加一条。过了才在 README 的平台表里标「已过准入闸」，并考虑加进循环驱动的 `--platform`。

## 产物不入库

`dist/` 是构建产物，`.gitignore` 忽略，按需 `python3 adapters/build_*.py` 现生成（见 ADR 0003 §9#1）。
