# PDLC Skill 使用指南

> 面向日常使用的快速上手手册。需要命令完整参考或架构细节，请查 [`docs/reference.md`](./reference.md)。

---

## 0. 5 分钟上手

如果你是新手，只需学 3 个命令即可完成 80% 的日常工作：

| 我想做... | 用这个命令 |
|---|---|
| 写新功能 | `/pdlc-feature <功能描述>` |
| 修 bug | `/pdlc-fix <bug 描述>` |
| 看当前进度 | `/pdlc-status` |

示例：

```
/pdlc-feature 给用户登录加手机号验证
```

会自动走完 **PRD → 设计 → TDD → 实现 → 评审 → 发布** 所有阶段，每阶段自动质量自检，无需手动串联。

---

## 1. 安装

### 项目级（推荐，给单个项目用）

```bash
bash install.sh --project /path/to/my-project
```

### 全局级（多项目复用）

```bash
bash install.sh --global
```

### 升级 / 卸载

```bash
bash install.sh --upgrade   --project /path/to/my-project
bash install.sh --upgrade   --global

bash install.sh --uninstall --project /path/to/my-project
bash install.sh --uninstall --global
```

### 验证安装

```bash
ls <project>/.claude/skills/pdlc/   # 项目级
ls ~/.claude/skills/pdlc/           # 全局
```

在 Claude Code 里让它列出可用 skill，应该能看到 `pdlc`。

---

## 2. 三层命令结构

### Layer 1 · 入口（3 个，新手只学这 3 个）

| 命令 | 用途 |
|---|---|
| `/pdlc-feature` | 全自动新功能（串联 PRD → 设计 → TDD → 实现 → 评审 → 发布） |
| `/pdlc-fix` | 全自动 Bug 修复（定位 → 复现 → 修复 → 测试 → 文档） |
| `/pdlc-status` | 项目 PDLC 状态总览 |

### Layer 2 · 阶段（11 个，单阶段精细控制）

| 命令 | 用途 | 下一跳 |
|---|---|---|
| `/pdlc-prd` | 创建 PRD | `/pdlc-design` |
| `/pdlc-design` | 技术设计 | `/pdlc-tdd` |
| `/pdlc-tdd` | 测试先行 | `/pdlc-implement` |
| `/pdlc-implement` | 按设计实现代码 | `/pdlc-review` |
| `/pdlc-review` | 代码 + 文档评审 | `/pdlc-ship` |
| `/pdlc-e2e` | 端到端测试 | `/pdlc-review` |
| `/pdlc-refactor` | 代码重构 | `/pdlc-review` |
| `/pdlc-ship` | 发布流水线（测试 → bump → CHANGELOG → tag → CI） | `/pdlc-deploy` |
| `/pdlc-deploy` | 部署文档 | — |
| `/pdlc-retro` | 迭代复盘（趋势对比） | — |
| `/pdlc-task` | 阶段内任务跟踪 | — |

每条命令完成后会打印 `👉 下一步：/pdlc-xxx`，按提示串联即可。

### Layer 3 · 工具（17 个，专项叠加）

**🎨 设计（4）**
- `/pdlc-ui-design` — 快速 UI 设计
- `/pdlc-ui-design-pro` — 专业级 UI 设计（依赖 ui-ux-pro-max）
- `/pdlc-db-design` — 数据库表结构设计
- `/pdlc-arch` — 架构分析

**🔍 质量（3）**
- `/pdlc-lint` — Lint + 自动修复
- `/pdlc-perf` — 性能优化
- `/pdlc-security` — 安全审计

**🔧 工程（7）**
- `/pdlc-code-gen` — 代码脚手架
- `/pdlc-add-service` — 加后端微服务
- `/pdlc-add-app` — 加前端应用
- `/pdlc-api-mock` — API Mock 数据
- `/pdlc-db-migrate` — 数据库迁移
- `/pdlc-i18n` — 国际化
- `/pdlc-changelog` — 更新 CHANGELOG

**🏗️ 项目生命周期（3）**
- `/pdlc-bootstrap` — AI 对话式项目初始化
- `/pdlc-adopt` — 旧项目接入 PDLC
- `/pdlc-onboard` — 自动生成用户手册

---

## 3. 状态追踪

### 状态机文件

每个功能的进度记录在你的项目的 `docs/.pdlc-state/<feature-id>.json`，内容：

```json
{
  "feature_id": "F20260502-01",
  "feature_name": "user-auth",
  "current_stage": "review",
  "history": [
    { "stage": "requirements", "done_at": "2026-05-02T10:05:00+08:00", "produced": ["..."] },
    { "stage": "design",       "done_at": "2026-05-02T10:30:00+08:00", "produced": ["..."] }
  ],
  "next_step": "pdlc-ship"
}
```

### 用它做什么

- `/pdlc-status` — 读所有状态机，列"进行中 / 已完成 / 待办建议"
- `/pdlc-status F20260502-01` — 看单个功能的完整 history
- `/pdlc-status --stale 3` — 列出停留同阶段 > 3 天的功能
- `/pdlc-retro --range 30d` — 出本月交付量、质量趋势、卡点案例的复盘报告

---

## 4. 典型场景

### 场景 A：从零做个功能（一条命令）

```
/pdlc-feature 给用户登录加手机号验证（P0），支持中国大陆手机号，失败 3 次后锁定 15 分钟
```

AI 会自动：
1. 分配功能 ID `F20260502-01`，创建 PRD
2. 设计 API、数据模型、前端页面
3. 生成失败的测试用例（红灯）
4. 实现代码到测试绿灯
5. Review 代码 + 文档
6. 建议 `/pdlc-ship` 发布

### 场景 B：只走一部分，手动控制

如果你想审核 PRD 再继续：

```
/pdlc-prd 给用户登录加手机号验证    # 只生成 PRD 并停下
# 人工 review docs/01_requirements/prd/F20260502-01-*.md，调整后继续
/pdlc-design F20260502-01          # 做设计
/pdlc-tdd F20260502-01             # 写测试
/pdlc-implement F20260502-01       # 实现
/pdlc-review F20260502-01          # 评审
/pdlc-ship                         # 发布
```

### 场景 C：修 bug

```
/pdlc-fix 分页器在结果列表为 0 条时崩溃
```

自动：分配缺陷 ID `B20260502-01` → 定位根因 → 写回归测试（红） → 修代码（绿） → 跑全量测试 → 更新 CHANGELOG 和缺陷记录。

### 场景 D：发布一个版本

```
/pdlc-ship --version 1.2.0
```

自动：检测未完成功能 → 询问是否跑测试 → bump VERSION → 汇总 CHANGELOG → git tag → 触发 CI。

### 场景 E：月度复盘

```
/pdlc-retro --range 30d
```

生成 `docs/07_reviews/retro/2026-05-retro.md`，含本月交付量、各阶段自检通过率、平均耗时、卡点案例、值得保留的做法。

---

## 5. 常见问题

**Q：可以跳过某个阶段吗？**
A：Layer 2 可以。但 `/pdlc-implement` 会检查测试是否存在——没测试会提示 `👉 /pdlc-tdd`，这是**硬门禁（IRON LAW）**，不可绕过。

**Q：状态机文件要提交到 git 吗？**
A：建议**要**。`docs/.pdlc-state/*.json` 是审计记录，便于复盘。

**Q：我卡在某一阶段了，怎么办？**
A：三步排查：
1. `/pdlc-status <feature-id>` 看当前在哪、下一步建议什么
2. 如果下一步命令报错，读错误信息（通常是硬门禁：缺文档、缺测试）
3. 补齐前置条件后重跑——状态机会自动续接，不会重复做已完成的阶段

**Q：AI 自动走完所有阶段会不会"跑偏"？**
A：每阶段有**自检 + 单次修复**机制（防循环），走完会输出自检报告。如果对某阶段的产出不满意，用对应 Layer 2 命令重跑该阶段即可，前后阶段不受影响。

**Q：怎么接入 ui-ux-pro-max（专业级 UI 设计）？**
A：先装 `npm install -g uipro-cli && uipro init --ai claude`，然后 `/pdlc-ui-design-pro` 会自动调用它的 67 种 UI 风格 / 161 配色库 / 13 技术栈模板。

**Q：我改了模板（`templates/prd-template.md` 等）想让 AI 按我的格式生成，怎么办？**
A：改完模板后重跑 `bash install.sh --upgrade --global` 或 `--upgrade --project <path>` 即可。需要更深的自定义（改命令提示词、加共享片段、改硬门禁语气），见 [`docs/reference.md`](./reference.md) §「扩展与自定义」。

---

**更多细节（每个命令的参数、产出、目录结构语义、架构哲学、扩展方法）请查 [`docs/reference.md`](./reference.md)。**
