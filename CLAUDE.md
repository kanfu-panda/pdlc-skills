# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

PDLC Skill 是一个 **Anthropic Claude Skill**（不是应用代码）。它由一套 Markdown 命令规范 + 共享提示片段 + 文档模板组成，加载后给 Claude 提供"产品开发生命周期"（PRD → 设计 → TDD → 实现 → 评审 → 发布 → 部署 → 复盘）工作流。

仓库根目录的 `SKILL.md` 是 Skill 入口（有 `name` / `description` frontmatter），所有命令定义与模板都放在 `references/` 下；`install.sh` 负责把整个 skill 目录复制到 `~/.claude/skills/pdlc/`（全局）或 `<project>/.claude/skills/pdlc/`（项目级）。

这个 skill **只面向 Claude Code**。`install.sh` 是纯 `rsync` 复制，不做任何渲染——`@include` 指令由 Claude 在执行命令时按需展开。

## Common commands

Install / upgrade / uninstall:

```bash
# 交互式
bash install.sh

# 全局
bash install.sh --global
bash install.sh --upgrade   --global
bash install.sh --uninstall --global

# 项目级
bash install.sh --project /path/to/my-project
bash install.sh --upgrade   --project /path/to/my-project
bash install.sh --uninstall --project /path/to/my-project
```

Tests (run via GitHub Actions on every PR; can also be run manually):

```bash
bash tests/frontmatter-check.sh   # 校验 references/commands/*.md 的 frontmatter
bash tests/install-smoke.sh       # 跑 install.sh 到临时目录并校验关键文件落盘
```

## Architecture

```
pdlc-skills/
├── SKILL.md                       ← Skill 入口（Claude 先读这个决定调哪个命令）
├── install.sh                     ← 安装脚本（纯 rsync，无渲染）
├── VERSION                        ← 版本号
├── references/
│   ├── commands/*.md              ← 31 个命令定义（YAML frontmatter + Markdown body）
│   └── templates/
│       ├── *-template.md          ← 9 个用户文档模板（PRD / API / DB / arch / ...）
│       └── prompts/*.md           ← 共享提示片段（iron-law / handoff / state-update ...）
├── docs/
│   ├── reference.md               ← frontmatter schema + 目录契约 权威文档
│   └── usage-guide.md             ← 日常用户手册
└── tests/
    ├── frontmatter-check.sh
    └── install-smoke.sh
```

`install.sh` 的安装目标固定为 `<scope>/.claude/skills/pdlc/`，使用 `rsync -a` 复制，排除 `.git` / `.github` / `install.sh` / `tests` / `CONTRIBUTING.md` / `CHANGELOG.md` / `CLAUDE.md` / `CODE_OF_CONDUCT.md` / `SECURITY.md`。

## Command layering

命令按 `layer:` frontmatter 字段分组，不按目录分组：

- **Layer 1 (3)**: `feature`, `fix`, `status` — 一句话驱动的入口命令
- **Layer 2 (11)**: 每个阶段一条 — `prd`, `design`, `tdd`, `implement`, `review`, `e2e`, `refactor`, `ship`, `deploy`, `retro`, `task`
- **Layer 3 (17)**: 专项工具 — `ui-design(-pro)`, `db-design`, `arch`, `lint`, `perf`, `security`, `code-gen`, `add-service`, `add-app`, `api-mock`, `db-migrate`, `i18n`, `changelog`, `bootstrap`, `adopt`, `onboard`

## Invariants enforced by the commands themselves

Layer 1 / Layer 2 命令通过在正文中 `@include` `references/templates/prompts/iron-law.md` 来强化铁律（执行期由 Claude 展开，不是安装期）：

1. 必须落盘（真实文件，不仅仅在对话里显示）
2. 必须更新状态机 `docs/.pdlc-state/<feature-id>.json`
3. 代码实现前测试必须已存在且失败（TDD 红灯）
4. 每阶段结束前必须自检
5. 自动修复循环最多一轮，失败则记录为待人工处理

命令体遵循四阶段骨架（execute → self-check → one-shot repair → handoff），并在 frontmatter 里用 `next_step` 声明下一条命令，让"流程编排"由命令声明而非人脑记忆。

## Target-project contract

执行 `pdlc-*` 命令时读写如下路径：

- `docs/01_requirements/prd/`
- `docs/02_design/{api,database,architecture}/`
- `docs/04_testing/{unit-tests,e2e-tests}/`
- `docs/05_deployment/`
- `docs/06_tasks/`
- `docs/07_reviews/{doc,code}/`
- `docs/.pdlc-state/<feature-id>.json` — 每个功能一个状态机文件，ID 形如 `F20260419-01`

改动此契约时必须同步更新 `references/commands/` 中对应命令的正文，以及 `docs/reference.md` 中相应章节。

## When editing this skill

- 命令源文件改 `references/commands/*.md`；共享提示片段改 `references/templates/prompts/*.md`；文档模板改 `references/templates/*-template.md`。不要去改已安装目录的拷贝。
- 新增/修改 frontmatter 必填字段时，同时更新 `tests/frontmatter-check.sh` 里的 `required_fields`。
- 运行完两条 test 脚本再提交。
- 新的共享提示片段放到 `references/templates/prompts/` 下，并在命令正文用 `<!-- @include templates/prompts/<name>.md -->` 引用（路径相对于 `references/`）。

## Notes

- `README.md`（英文）和 `README.zh-CN.md`（中文）是面向用户的安装 / 使用文档。
- `docs/usage-guide.md` 是日常用户手册；`docs/reference.md` 是 frontmatter schema 与目录契约的权威文档，本文件的概要以它为准。
