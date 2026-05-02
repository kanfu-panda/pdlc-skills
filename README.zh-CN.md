# PDLC Skill

**[English](./README.md)** · **中文**

[![CI](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-blue)](./CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-orange)](https://docs.anthropic.com/)

> 作者：**LEO**
> 仓库：[github.com/kanfu-panda/pdlc-skills](https://github.com/kanfu-panda/pdlc-skills)
> License: [MIT](./LICENSE)

PDLC（产品开发生命周期）Claude Skill — 提供 31 条覆盖需求、设计、开发、测试、质检、评审、部署、复盘全流程的标准化命令规范。

**当前仅支持 Claude Code**（作为 Anthropic Skill 分发）。`SKILL.md` 是 skill 入口，安装后 Claude Code 会自动加载。

---

## 为什么需要 PDLC

不带这个 skill 时，AI 助手做功能时常见的问题：

- 说"我把功能做完了"，但 PRD 只活在对话里，关掉就没了。
- 直接写代码，没有先写测试。
- 跳过设计阶段，架构腐烂悄无声息。
- 跨会话没有记忆，不知道某个功能处于哪个阶段。

**PDLC Skill 把这些"软规范"升级为"硬契约"：**

| 硬契约 | 给你什么 |
|---|---|
| 每份产物落到 `docs/` 目录 | 可以 `git diff` 看 AI 真的做了什么 |
| 每个阶段写状态机文件 | `pdlc-status` 永远知道当前进展 |
| 实现前测试必须已存在且失败 | 真正的 TDD 红灯门禁，不是建议 |
| 每条命令交接前自检 | 阶段边界拦截偏差，而不是评审时才发现 |
| 自动修复至多一轮 | 杜绝"修复 → 检查 → 再修复"的死循环 |
| 每条命令声明 `next_step` | 多阶段串联由命令驱动，不靠人脑记 |

---

## 一眼看效果

一个典型端到端流程：

```text
$ # 在 Claude Code 里：
$ /pdlc-feature 给用户登录加手机号验证

→ 分配功能 ID F20260502-01（user-auth-phone）
→ 阶段一：生成 PRD
   ✓ docs/01_requirements/prd/F20260502-01-user-auth-phone-prd.md
   ✓ 自检 8/8 通过
→ 阶段二：技术设计
   ✓ docs/02_design/api/F20260502-01-user-auth-phone-api.md
   ✓ docs/02_design/database/F20260502-01-user-auth-phone-db.md
→ 阶段三：TDD 红灯
   ✓ 写了 14 条测试，全部预期失败
→ 阶段四：实现
   ✓ 14/14 测试转绿
→ 阶段五：代码评审 + 自动修复
   ✓ 自动修复 3 个 lint 问题
   ✓ docs/07_reviews/code/F20260502-01-user-auth-phone-review.md
→ 阶段六：交接
   📦 docs/.pdlc-state/F20260502-01.json 已更新
   👉 下一步：/pdlc-ship
```

上面每一个产物都是磁盘上的真实文件，可以 `git diff` 看 AI 真正做了什么。任何时候用 `/pdlc-status` 查看每个功能的当前阶段。

---

## 安装

```bash
git clone git@github.com:kanfu-panda/pdlc-skills.git
cd pdlc-skills
```

### 项目级安装（推荐）

```bash
bash install.sh --project /path/to/my-project
# 安装到 <project>/.claude/skills/pdlc/
```

### 全局安装

```bash
bash install.sh --global
# 安装到 ~/.claude/skills/pdlc/
```

### 交互式安装

```bash
bash install.sh
# 按提示选择全局 / 项目级
```

### 升级

```bash
bash install.sh --upgrade --global
bash install.sh --upgrade --project /path/to/my-project
```

### 卸载

```bash
bash install.sh --uninstall --global
bash install.sh --uninstall --project /path/to/my-project
```

### 查看版本 / 获取最新版

```bash
bash install.sh --version       # 显示本地克隆 / 已安装 / GitHub 最新版本
bash install.sh --self-update   # git pull 拉取最新源码（需是 git clone）
```

示例输出：

```text
PDLC Skill version status
──────────────────────────────────────
  Local clone:         1.0.0
  Installed (global):  1.0.0
  Latest on GitHub:    1.1.0

⚠️  Your local clone (1.0.0) is behind GitHub (1.1.0).
    To upgrade:
      cd /path/to/pdlc-skills && git pull
      bash install.sh --upgrade --global
```

## 使用方式

安装完成后，在 Claude Code 中直接用自然语言描述任务，skill 会自动被调用；也可以显式要求走 PDLC 流程：

```
帮我用 PDLC 流程做用户登录功能
修一下分页在 0 条数据时崩溃的 bug
帮我看一下当前 PDLC 状态
```

Claude 会读取 `SKILL.md` 入口索引，定位到对应命令规范文件（`references/commands/<名称>.md`），并按其中的工作流执行。

## 命令清单（v2 分层结构）

### Layer 1 · 入口（3 个，新手只学这 3 个）

| 命令 | 用途 |
|---|---|
| `feature` | 全自动新功能开发（串联 PRD → 设计 → TDD → 实现 → 评审 → 发布） |
| `fix` | 全自动 Bug 修复（定位 → 复现 → 修复 → 测试 → 文档） |
| `status` | 查看项目 PDLC 状态总览 |

### Layer 2 · 阶段（11 个，单阶段精细控制）

| 命令 | 用途 |
|---|---|
| `prd` | 创建 PRD 文档 |
| `design` | 技术设计 |
| `tdd` | 测试先行（TDD） |
| `implement` | 按设计实现代码 |
| `review` | 代码 + 文档评审 |
| `e2e` | 端到端测试 |
| `refactor` | 代码重构 |
| `ship` | 发布工作流（测试 → VERSION → CHANGELOG → tag → CI） |
| `deploy` | 部署文档 |
| `retro` | 迭代复盘（趋势对比） |
| `task` | 阶段内任务跟踪 |

### Layer 3 · 工具（17 个，专项叠加）

**🎨 设计（4）**：`ui-design` / `ui-design-pro` / `db-design` / `arch`
**🔍 质量（3）**：`lint` / `perf` / `security`
**🔧 工程（7）**：`code-gen` / `add-service` / `add-app` / `api-mock` / `db-migrate` / `i18n` / `changelog`
**🏗️ 项目生命周期（3）**：`bootstrap` / `adopt` / `onboard`

---

## 新手路径（3 步上手）

1. 安装：`bash install.sh --project /path/to/my-project`
2. 写代码：对 Claude 说 "用 PDLC 流程给登录加验证码"
3. 修 bug：对 Claude 说 "按 PDLC 流程修分页器在 0 条时崩溃的问题"

## 目标项目契约

执行命令时会在目标项目下读写：

```
docs/01_requirements/prd/
docs/02_design/{api,database,architecture}/
docs/04_testing/{unit-tests,e2e-tests}/
docs/05_deployment/
docs/06_tasks/
docs/07_reviews/{doc,code}/
docs/.pdlc-state/<feature-id>.json   ← 每个功能一个状态机文件（如 F20260419-01.json）
```

## 包含的文档模板

`references/templates/` 下的 9 个标准文档模板（PRD、API 设计、架构设计、数据库设计、迁移脚本、测试计划、部署手册、变更日志、接入报告）会随 skill 一起安装到 `.claude/skills/pdlc/references/templates/`，命令执行时从这里取模板落盘到目标项目的 `docs/…` 下。

模板文件：
- `prd-template.md` — PRD 产品需求文档
- `api-design-template.md` — API 设计文档
- `arch-design-template.md` — 架构设计文档
- `db-design-template.md` — 数据库设计文档
- `db-migrate-template.md` — 数据库迁移脚本
- `test-plan-template.md` — 测试计划
- `deploy-doc-template.md` — 部署手册
- `changelog-template.md` — 变更日志
- `adopt-report-template.md` — 旧项目接入报告

## 执行铁律

1. **必须落盘**：所有产出必须作为真实文件写入磁盘，不可仅在对话中显示
2. **必须更新状态机**：每个阶段完成后写入 `docs/.pdlc-state/<feature-id>.json`
3. **必须有测试**：代码实现前测试必须已存在且失败（TDD 红灯）
4. **必须自检**：每阶段结束前运行 self-check
5. **修复仅一次**：自动修复循环最多一轮，失败则记录为待人工处理

## 验证安装

```bash
ls ~/.claude/skills/pdlc/              # 全局安装
ls <project>/.claude/skills/pdlc/      # 项目级安装
```

在 Claude Code 中让它列出可用 skill，应该能看到 `pdlc`。

## 提问 / 讨论

使用问题、设计讨论、不确定是 bug 还是用法不对——请优先用 [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions)。

确认的 bug 和功能建议——请用 [Issues](https://github.com/kanfu-panda/pdlc-skills/issues) 配合附带的模板。

私密安全问题——见 [SECURITY.md](./SECURITY.md)。

---

## 开发者文档

- `docs/usage-guide.md` — 日常使用手册
- `docs/reference.md` — 完整架构、frontmatter schema、目录契约
- `CONTRIBUTING.md` — 如何贡献
- `CODE_OF_CONDUCT.md` — 行为准则
- `SECURITY.md` — 安全策略
- `CHANGELOG.md` — 版本变更记录
