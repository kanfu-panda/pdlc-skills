# PDLC Plugin

**[English](./README.md)** · **中文**

[![CI](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-1.2.1-blue)](./CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-orange)](https://docs.anthropic.com/)

> 作者：**kanfu-panda**
> 仓库：[github.com/kanfu-panda/pdlc-skills](https://github.com/kanfu-panda/pdlc-skills)
> License: [MIT](./LICENSE)

**PDLC** 是一个 [Claude Code plugin](https://docs.anthropic.com/)，给 Claude 加上"产品开发生命周期"工作流——**35 个标准化阶段**，全部以斜杠命令暴露：`/pdlc-feature`、`/pdlc-prd`、`/pdlc-tdd`、`/pdlc-implement`、`/pdlc-review`、`/pdlc-ship` 等。

每个阶段都强制硬契约（产物落到 `docs/`、每功能状态机、实现前必须有红灯测试、阶段交接前自检、自动修复仅一轮），让 AI 驱动的工程产出真实可审计的文件，而不是只活在对话里。

**当前仅支持 Claude Code**。安装后 plugin 在 `~/.claude/plugins/pdlc/`。

---

## 为什么需要 PDLC

不带这个 plugin 时，AI 助手做功能时常见的问题：

- 说"我把功能做完了"，但 PRD 只活在对话里，关掉就没了。
- 直接写代码，没有先写测试。
- 跳过设计阶段，架构腐烂悄无声息。
- 跨会话没有记忆，不知道某个功能处于哪个阶段。

**PDLC 把这些"软规范"升级为"硬契约"：**

| 硬契约 | 给你什么 |
|---|---|
| 每份产物落到 `docs/` 目录 | 可以 `git diff` 看 AI 真的做了什么 |
| 每个阶段写状态机文件 | `/pdlc-status` 永远知道当前进展 |
| 实现前测试必须已存在且失败 | 真正的 TDD 红灯门禁，不是建议 |
| 每条阶段交接前自检 | 阶段边界拦截偏差，而不是评审时才发现 |
| 自动修复至多一轮 | 杜绝"修复 → 检查 → 再修复"的死循环 |
| 每条阶段声明 `next_step` | 多阶段串联由命令驱动，不靠人脑记 |

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

上面每一个产物都是磁盘上的真实文件，可以 `git diff` 看 AI 真正做了什么。任何时候用 `/pdlc-status` 看每个功能的当前阶段。*（输出是示意图，Claude Code 实际输出是 markdown 流式响应。）*

---

## 安装

> 一行命令搞定，无需 clone 整个仓库。会从 GitHub 拉取最新发布版本。

```bash
# 全局安装（~/.claude/plugins/pdlc/）
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global

# 项目级安装（<project>/.claude/plugins/pdlc/）
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --project /path/to/my-project
```

就这一条。安装器会下载对应版本的 tarball，解压，把 plugin 文件复制到你的 `.claude/plugins/pdlc/` 目录下。

### 升级

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --upgrade --global
```

### 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --uninstall --global
```

### 查看版本

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --version
```

### 等价的原生命令

如果你想直接调 Claude Code 的 plugin CLI：

```bash
claude plugin marketplace add kanfu-panda/pdlc-skills
claude plugin install pdlc@pdlc-skills
```

### 贡献者 / 自定义模板

```bash
git clone https://github.com/kanfu-panda/pdlc-skills.git
cd pdlc-skills
# 改 references/templates/*.md 或 skills/pdlc-*/SKILL.md
bash install.sh --global   # 从你本地的 clone 安装
```

---

## 验证安装

```bash
claude plugin list | grep pdlc
# 应该输出： pdlc@pdlc-skills  Version: 1.2.1  Status: ✔ enabled
```

在 Claude Code 里（重启会话后），输入 `/` 然后开始打 `pdlc-`——下拉里应该出现全部 35 个子命令（`/pdlc-feature`、`/pdlc-prd`、`/pdlc-tdd` ...）。

---

## 阶段清单（三层结构）

### Layer 1 · 入口（3 个，新手只学这 3 个）

一句话需求驱动整条链路。

| 斜杠命令 | 用途 |
|---|---|
| `/pdlc-feature` | 全自动新功能（PRD → 设计 → TDD → 实现 → 评审 → 发布） |
| `/pdlc-fix` | 全自动 Bug 修复（定位 → 复现 → 修复 → 测试 → 文档） |
| `/pdlc-status` | 项目 PDLC 状态总览 |

### Layer 2 · 阶段（11 个，单阶段精细控制）

| 斜杠命令 | 用途 |
|---|---|
| `/pdlc-prd` | 创建 PRD |
| `/pdlc-design` | 技术设计 |
| `/pdlc-tdd` | 测试先行（TDD） |
| `/pdlc-implement` | 按设计实现代码 |
| `/pdlc-review` | 代码 + 文档评审 |
| `/pdlc-e2e` | 端到端测试 |
| `/pdlc-refactor` | 代码重构 |
| `/pdlc-ship` | 发布工作流（测试 → VERSION → CHANGELOG → tag → CI） |
| `/pdlc-deploy` | 部署文档 |
| `/pdlc-retro` | 迭代复盘（趋势对比） |
| `/pdlc-task` | 阶段内任务跟踪 |

### Layer 3 · 工具（21 个，专项叠加）

- **🎨 设计（4）**：`/pdlc-ui-design` · `/pdlc-ui-design-pro` · `/pdlc-db-design` · `/pdlc-arch`
- **🔍 质量（3）**：`/pdlc-lint` · `/pdlc-perf` · `/pdlc-security`
- **🔧 工程（7）**：`/pdlc-code-gen` · `/pdlc-add-service` · `/pdlc-add-app` · `/pdlc-api-mock` · `/pdlc-db-migrate` · `/pdlc-i18n` · `/pdlc-changelog`
- **🔗 治理（2）**：`/pdlc-standard` · `/pdlc-relate`
- **🏗️ 项目生命周期（3）**：`/pdlc-bootstrap` · `/pdlc-adopt` · `/pdlc-onboard`
- **🔁 循环工具（2）**：`/pdlc-loop-next`（打印下一条机械收敛命令）· `/pdlc-loop-run`（收敛引擎：自动推进 `tdd → implement → review` 到 `review_done`，发布留人）——[设计文档](./docs/decisions/0001-loop-engineering-integration.md)

---

## 新手路径（3 步上手）

1. **安装**（一行，免 clone）：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh | bash -s -- --global
   ```
2. **写功能**：在 Claude Code 里 `/pdlc-feature 给登录加验证码`
3. **修 bug**：`/pdlc-fix 修分页器在 0 条时崩溃的问题`

任何时候看进度：`/pdlc-status`

---

## 目标项目契约

执行命令时会在你项目下读写：

```
docs/00_standards/coding/            ← 编码规范（被 prd/implement/tdd/code-gen/onboard 读取，可选）
docs/00_standards/test-commands.yml  ← check 命令唯一真源（unit/coverage/lint/e2e），被 tdd/implement/review 与循环驱动读取
docs/01_requirements/prd/            ← PRD
docs/02_design/{api,database,architecture,ui-ux}/   ← 技术设计
docs/03_development/                 ← 开发者手册（onboard 命令产出）
docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/   ← 测试与缺陷
docs/05_deployment/                  ← 部署
docs/06_tasks/                       ← 任务跟踪
docs/07_reviews/{doc,code,design,retro}/   ← 评审 + 复盘
docs/.pdlc-state/<feature-id>.json   ← 每个功能一个状态机文件（如 F20260419-01.json）
```

---

## 包含的文档模板

`references/templates/` 下的 9 个标准模板会随 plugin 一起安装：

- `prd-template.md` · `api-design-template.md` · `arch-design-template.md`
- `db-design-template.md` · `db-migrate-template.md` · `test-plan-template.md`
- `deploy-doc-template.md` · `changelog-template.md` · `adopt-report-template.md`

---

## 执行铁律（IRON LAW）

每个**产出文件**的 Layer 1/2 阶段都强制五条规则（`/pdlc-status` 这种只读阶段豁免）：

1. **必须落盘**：所有产出必须作为真实文件写入磁盘，不可仅在对话中显示
2. **必须更新状态机**：每个阶段完成后写入 `docs/.pdlc-state/<feature-id>.json`
3. **必须有测试**：代码实现前测试必须已存在且失败（TDD 红灯）
4. **必须自检**：每阶段结束前运行 self-check
5. **修复仅一次**：自动修复循环最多一轮，失败则记录为待人工处理

---

## 提问 / 讨论

使用问题、设计讨论、不确定是 bug 还是用法不对——请优先用 [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions)。

确认的 bug 和功能建议——请用 [Issues](https://github.com/kanfu-panda/pdlc-skills/issues) 配合附带的模板。

私密安全问题——见 [SECURITY.md](./SECURITY.md)。

---

## 开发者文档

- `docs/usage-guide.md` — 完整使用手册（含目录契约、状态机、典型场景、扩展方式）
- `CONTRIBUTING.md` — 如何贡献
- `CODE_OF_CONDUCT.md` — 行为准则
- `SECURITY.md` — 安全策略
- `CHANGELOG.md` — 版本变更记录

---

## 💖 支持本项目

PDLC 是业余时间维护的开源项目。如果它给你省下了几个小时（或者一点头发），欢迎支持后续迭代。

**捐赠通道：**

- 🇨🇳 **[爱发电](https://afdian.com/a/kanfu-panda)** — 中国大陆用户首选，支付宝 / 微信支付，原生支持档位订阅与一次性打赏
- 🌍 **[PayPal](https://paypal.me/Leosh980)** — 国际用户专用，金额自定，一次性打赏

**档位（爱发电按档订阅 / 一次性同价）：**

| 档位 | 爱发电 | PayPal 等值 | 你将获得 |
|---|---|---|---|
| ☕ 打赏 | ¥10 一次性 | $1+ 一次性 | 真诚感谢，不进名单 |
| 🌱 支持者 | ¥30/月 | $5+ 一次性 | 昵称登上 [SPONSORS.md](./SPONSORS.md) |
| 🌳 长期赞助者 | ¥66/月 | $20+ 一次性 | 昵称 + 头像 + 个人链接登上 [SPONSORS.md](./SPONSORS.md) |
| 🏢 企业赞助 | ¥888/月 | $100+/月 | 企业 Logo + 链接出现在 `README.md` 顶部 |

通过 PayPal 赞助后，请在 [SPONSORS issue](https://github.com/kanfu-panda/pdlc-skills/issues/new?title=%5BSponsor%5D%20add%20me%20to%20the%20list) 留下你的 GitHub 用户名，方便加入名单。名单按月度同步，见 [SPONSORS.md](./SPONSORS.md)。
