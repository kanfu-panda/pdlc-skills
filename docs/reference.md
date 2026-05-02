# PDLC Skill 进阶参考

> 完整的架构说明、命令参考、目录规范、扩展方法。日常使用请看 [`usage-guide.md`](./usage-guide.md)。

---

## 目录

1. [设计哲学](#1-设计哲学)
2. [架构概览](#2-架构概览)
3. [四段式工作流](#3-四段式工作流)
4. [命令完整参考](#4-命令完整参考)
   - [Layer 1 · 入口](#41-layer-1--入口)
   - [Layer 2 · 阶段](#42-layer-2--阶段)
   - [Layer 3 · 工具](#43-layer-3--工具)
5. [目录结构规范](#5-目录结构规范)
6. [状态机规范](#6-状态机规范)
7. [共享片段（@include）](#7-共享片段include)
8. [扩展与自定义](#8-扩展与自定义)
9. [相关资源](#9-相关资源)

---

## 1. 设计哲学

### 1.1 三层分层

PDLC Skill 把 31 条命令按使用频率分 3 层暴露：

- **Layer 1（3 个）**：高频入口，新手只学这层即可完成 80% 工作
- **Layer 2（11 个）**：单阶段精细控制，进阶用户用来插队补救
- **Layer 3（17 个）**：专项工具，按需叠加

**心智**：做功能用 `feature`，修 bug 用 `fix`，看状态用 `status`——三个动词级指令。

### 1.2 IRON LAW：硬门禁不可协商

每个产出文件的 Layer 1/2 命令顶部 `@include` 了 `templates/prompts/iron-law.md`，五条规则：

1. 文件必须落盘（不只在对话中输出）
2. 阶段必须落章（状态机 history 追加）
3. 测试必须存在（TDD 守卫）
4. 自检必须执行（不可跳过）
5. 防循环（单次修复，不递归）

**违反任一条 = 立即中止命令**。这是为了避免 AI "轻飘飘地说做了但没落盘"。

> 查询类命令（如 `pdlc-status`，`produces: []`）不产出文件，不在 IRON LAW 适用范围内。

### 1.3 Handoff：显式下一跳

每个 Layer 1/2 命令的 frontmatter 声明 `next_step`，命令末尾必须输出：

```
👉 下一步：/pdlc-<next_step>
```

这让多命令串联由"人工记忆"变为"命令级声明"。用户跟着提示走即可，不用背命令链。

### 1.4 防循环：单次修复原则

段二自检发现问题 → 段三修复**只做一轮** → 不过的问题记录到报告，流程继续。避免"修完再查、查完再修"的死循环。

---

## 2. 架构概览

```
┌────────────────────────────────────────────────────────────┐
│                      pdlc-skills 仓库                       │
├────────────────────────────────────────────────────────────┤
│  SKILL.md                       Skill 入口（YAML 头 + 索引） │
│  references/                                                │
│    ├── commands/*.md            31 条命令规范（YAML + 正文）│
│    │     带 @include 指令引用 prompts/* 片段                │
│    └── templates/                                           │
│        ├── *-template.md        9 份用户文档模板            │
│        └── prompts/             8 份共享提示片段            │
│            ├── iron-law.md      硬门禁                      │
│            ├── feature-id.md    功能 ID 分配                │
│            ├── handoff.md       交接格式                    │
│            └── ...                                          │
│  install.sh                     纯 rsync 安装器             │
│  tests/                                                     │
│    ├── frontmatter-check.sh                                 │
│    └── install-smoke.sh                                     │
└────────────────────────────────────────────────────────────┘
                             │
                             │  install.sh --project <用户项目>
                             ▼  （或 --global）
┌────────────────────────────────────────────────────────────┐
│                       用户项目                              │
├────────────────────────────────────────────────────────────┤
│  .claude/skills/pdlc/           skill 安装目录              │
│  docs/                          PDLC 阶段产出物             │
│    ├── 01_requirements/prd/     PRD 文档                    │
│    ├── 02_design/               技术设计                    │
│    ├── 04_testing/              测试与缺陷                  │
│    ├── 05_deployment/           部署文档                    │
│    ├── 06_tasks/                任务跟踪                    │
│    ├── 07_reviews/              评审 + 复盘                 │
│    └── .pdlc-state/<id>.json    状态机（每功能一份）        │
└────────────────────────────────────────────────────────────┘
```

`install.sh` 是纯 `rsync -a` 复制，不做渲染——`@include` 指令由 Claude 在执行命令时按需展开（读取 `references/templates/prompts/<name>.md`）。

排除清单：`.git`、`.github`、`.editorconfig`、`install.sh`、`tests`、`CONTRIBUTING.md`、`CHANGELOG.md`、`CLAUDE.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`。

---

## 3. 四段式工作流

Layer 1/2 命令统一为四段式：

| 段 | 名称 | 职责 |
|---|---|---|
| 段一 | 执行 | 产出主文档 / 代码 / 配置 |
| 段二 | 自检 | 重读产物，按质量清单逐项检查 |
| 段三 | 修复 | 自动修复可修部分（单次，防循环） |
| 段四 | 交接 | 更新状态机 + 输出 handoff 下一步 |

**示例**（`pdlc-prd` 的执行轨迹）：

```
段一：生成 PRD
  └→ docs/01_requirements/prd/F20260502-01-user-auth-prd.md

段二：自检
  ✓ 背景与目标清晰
  ✓ 用户故事 >= 3 条
  ✗ 功能清单缺优先级
  ✓ 验收标准可度量
  ...（8 项质量关卡）

段三：修复
  → 自动补齐 P0/P1/P2 优先级标注
  → 重新检查：✓

段四：交接
  ✅ PRD 已创建：docs/01_requirements/prd/F20260502-01-user-auth-prd.md
  📊 自检：8/8 通过
  📦 状态快照：docs/.pdlc-state/F20260502-01.json
  👉 下一步：/pdlc-design F20260502-01
```

---

## 4. 命令完整参考

每条命令的 frontmatter 字段说明：

| 字段 | 含义 |
|---|---|
| `name` | 命令名（带 `pdlc-` 前缀） |
| `description` | 一句话描述（Claude 用它做语义匹配） |
| `argument-hint` | 参数提示 |
| `allowed-tools` | 命令体可用的 Claude 工具 |
| `layer` | 1 / 2 / 3 |
| `stage` | requirements / design / tdd / impl / review / ship / deploy / retro / ops / quality / engineering / lifecycle |
| `produces` | 本命令的产出物路径（空数组表示查询命令） |
| `requires` | 前置依赖路径 |
| `next_step` | 主流程下一跳（Handoff 核心，可为 null） |
| `terminal_state` | 成功时写入状态机的标记（如 `feature_done`） |

### 4.1 Layer 1 · 入口

#### `/pdlc-feature`

- **用途**：全自动 PDLC 新功能开发
- **参数**：`<功能描述 | 已有 PRD 路径>`
- **产出**：PRD / 设计 / 测试 / 代码 / 评审记录 全套
- **下一跳**：`/pdlc-ship`
- **示例**：
  ```
  /pdlc-feature 给用户登录加手机号验证（P0）
  /pdlc-feature docs/01_requirements/raw/user-auth-brief.md
  ```

#### `/pdlc-fix`

- **用途**：全自动 Bug 修复
- **参数**：`<Bug 描述>`
- **产出**：`docs/04_testing/defects/<defect-id>-defect.md` + 回归测试 + 代码修复
- **下一跳**：`/pdlc-ship`
- **示例**：
  ```
  /pdlc-fix 分页器在 0 条时崩溃
  ```

#### `/pdlc-status`

- **用途**：读 `docs/.pdlc-state/` 输出项目 PDLC 总览
- **参数**：`[feature-id | --all | --stale <days>]`
- **产出**：控制台报告（不落盘，不更新状态机）
- **下一跳**：— （查询命令）
- **示例**：
  ```
  /pdlc-status                    # 所有功能
  /pdlc-status F20260502-01       # 单个功能 history
  /pdlc-status --stale 3          # 停留 > 3 天的功能
  ```

### 4.2 Layer 2 · 阶段

#### `/pdlc-prd`

- **用途**：创建 PRD
- **参数**：`<功能描述 | 已有需求文档路径>`
- **产出**：`docs/01_requirements/prd/<feature-id>-<name>-prd.md`
- **前置**：无
- **下一跳**：`/pdlc-design`
- **自检清单**：完整性 6 项 + 一致性 3 项

#### `/pdlc-design`

- **用途**：技术设计
- **参数**：`<功能ID | 功能描述>`
- **产出**：`docs/02_design/<subsystem>/<feature-id>-design.md`
- **前置**：`docs/01_requirements/prd/`
- **下一跳**：`/pdlc-tdd`

#### `/pdlc-tdd`

- **用途**：按设计写失败的测试用例
- **参数**：`<功能ID | 功能描述>`
- **产出**：`backend/services/*/src/test/**` 或 `frontend/*/src/__tests__/**`
- **前置**：`docs/02_design/`
- **下一跳**：`/pdlc-implement`

#### `/pdlc-implement`

- **用途**：按设计和测试写代码
- **参数**：`<功能描述 | 功能ID>`
- **产出**：代码文件 + 更新服务 CHANGELOG
- **前置**：测试必须存在且红灯（IRON LAW #3）
- **下一跳**：`/pdlc-review`
- **守卫**：未找到测试会中止并提示 `/pdlc-tdd`

#### `/pdlc-review`

- **用途**：代码 + 文档评审
- **参数**：`<功能ID | PR 描述>`
- **产出**：`docs/07_reviews/**`
- **下一跳**：`/pdlc-ship`

#### `/pdlc-e2e`

- **用途**：端到端测试
- **参数**：`<功能ID | 业务流程描述>`
- **产出**：`e2e/**/*.spec.ts` 或 `backend/e2e/**`
- **下一跳**：`/pdlc-review`

#### `/pdlc-refactor`

- **用途**：代码重构（保持外部行为不变）
- **参数**：`<重构目标 | 文件路径>`
- **产出**：修改既有代码
- **下一跳**：`/pdlc-review`

#### `/pdlc-ship`

- **用途**：发布流水线
- **参数**：`[--version <x.y.z>] [--skip-tests]`
- **流程**：前置检查 → 测试门询问 → bump VERSION → 更 CHANGELOG → 创建 tag → CI/CD 配置
- **下一跳**：`/pdlc-deploy`

#### `/pdlc-deploy`

- **用途**：部署文档
- **参数**：`<服务名 | 应用名>`
- **产出**：`docs/05_deployment/**`
- **下一跳**：— （发布流程终点）

#### `/pdlc-retro`

- **用途**：迭代复盘，读状态机历史出趋势报告
- **参数**：`[--range 7d|30d|all] [--feature <feature-id>]`
- **产出**：`docs/07_reviews/retro/<YYYY-MM>-retro.md`
- **指标**：交付量、自检通过率、阶段耗时中位数、卡点案例

#### `/pdlc-task`

- **用途**：阶段内任务跟踪（附在工作流上，用于细化大阶段）
- **参数**：`<功能ID | 任务描述>`
- **产出**：`docs/06_tasks/<feature-id>-tasks.md`
- **状态记号**：⬜ 未开始 / 🔄 进行中 / ✅ 已完成

### 4.3 Layer 3 · 工具

#### 🎨 设计组

- `/pdlc-ui-design` — 快速 UI 设计
- `/pdlc-ui-design-pro` — 专业级（依赖 `uipro-cli`，67 风格 / 161 配色 / 13 技术栈）
- `/pdlc-db-design` — 数据库表结构设计
- `/pdlc-arch` — 架构分析

#### 🔍 质量组

- `/pdlc-lint` — Lint + 自动修复（自动检测项目类型）
- `/pdlc-perf` — 性能优化分析 + 建议
- `/pdlc-security` — 安全审计

#### 🔧 工程组

- `/pdlc-code-gen` — 代码脚手架（按模板生成）
- `/pdlc-add-service` — 添加新的微服务
- `/pdlc-add-app` — 添加新的前端应用
- `/pdlc-api-mock` — API Mock 数据生成
- `/pdlc-db-migrate` — 数据库迁移管理
- `/pdlc-i18n` — 国际化（多语言资源生成 / 校对）
- `/pdlc-changelog` — 更新 CHANGELOG

#### 🏗️ 项目生命周期组

- `/pdlc-bootstrap` — AI 对话式项目初始化（新项目从零起手）
- `/pdlc-adopt` — 旧项目接入 PDLC（扫描现状生成接入报告）
- `/pdlc-onboard` — 自动生成面向最终用户的手册

---

## 5. 目录结构规范

skill 在用户项目下使用以下目录约定：

```
<用户项目>/
├── docs/
│   ├── 00_standards/              编码 / 架构规范（可选）
│   │   └── coding/
│   ├── 01_requirements/           需求
│   │   └── prd/
│   │       └── F<YYYYMMDD>-<NN>-<name>-prd.md
│   ├── 02_design/                 技术设计
│   │   ├── api/
│   │   ├── database/
│   │   ├── architecture/
│   │   └── ui/
│   ├── 04_testing/                测试
│   │   ├── unit-tests/
│   │   ├── e2e-tests/
│   │   └── defects/
│   │       └── B<YYYYMMDD>-<NN>-<name>-defect.md
│   ├── 05_deployment/             部署
│   ├── 06_tasks/                  任务跟踪
│   │   └── <feature-id>-tasks.md
│   ├── 07_reviews/                评审 + 复盘
│   │   ├── doc/
│   │   ├── code/
│   │   └── retro/
│   │       └── <YYYY-MM>-retro.md
│   └── .pdlc-state/               状态机
│       └── <feature-id>.json
├── backend/ 或 frontend/ 等        业务代码
├── CHANGELOG.md                   （由 /pdlc-ship 维护）
└── VERSION
```

### PDLC-TRACE 追溯头

每个带编号的 PDLC 文档顶部必须有：

```html
<!-- PDLC-TRACE -->
<!-- 功能ID: F20260502-01 -->
<!-- 功能名称: user-auth -->
<!-- 阶段: requirements -->
<!-- 前置文档: 无 -->
<!-- 创建时间: 2026-05-02T10:00:00+08:00 -->
```

作用：可以从任一文档反向追溯到它属于哪个功能、哪个阶段、前置文档是什么。

### ID 分配规则

- **功能 ID**：`F<YYYYMMDD>-<NN>`（如 `F20260502-01`）
- **缺陷 ID**：`B<YYYYMMDD>-<NN>`（如 `B20260502-01`）
- 按执行当天扫描已有 ID，取最大序号 + 1

---

## 6. 状态机规范

### 文件路径

`docs/.pdlc-state/<feature-id>.json`

### Schema

```json
{
  "feature_id": "F20260502-01",
  "feature_name": "user-auth",
  "created_at": "2026-05-02T10:00:00+08:00",
  "current_stage": "review",
  "history": [
    {
      "stage": "requirements",
      "done_at": "2026-05-02T10:05:00+08:00",
      "produced": ["docs/01_requirements/prd/F20260502-01-user-auth-prd.md"],
      "self_audit": { "passed": 8, "failed": 0, "manual": 0 }
    }
  ],
  "next_step": "pdlc-ship",
  "terminal_state": null
}
```

### 字段约定

| 字段 | 类型 | 说明 |
|---|---|---|
| `feature_id` | string | F / B 开头 |
| `feature_name` | string | kebab-case |
| `created_at` | ISO 8601 | 首次创建时间 |
| `current_stage` | string | 最近一个阶段名 |
| `history` | array | 按时间顺序追加 |
| `history[].produced` | array | 本阶段产出的相对路径 |
| `history[].self_audit` | object | passed / failed / manual 计数 |
| `next_step` | string \| null | 下一跳命令名 |
| `terminal_state` | string \| null | 成功完成时的标记（`feature_done` / `fix_done` 等） |

### 手动修改？

原则上**不要手动改**。如果状态机写错了（比如阶段漏记），可以：

1. 删除文件让命令重新从头记（会丢前序）
2. 或手动编辑 JSON 补正确（有经验的用户才这么做）

---

## 7. 共享片段（@include）

### 机制

源命令文件中用指令：

```markdown
<!-- @include templates/prompts/iron-law.md -->
```

这是**运行期** include——`install.sh` 不做替换，Claude 在执行命令时读取 `references/templates/prompts/<name>.md` 内联展开。

**规则**：
- 指令必须独占一行
- 路径相对于 `references/`，固定以 `templates/prompts/` 开头

### 现有 8 份共享片段

| 文件 | 被谁用 | 作用 |
|---|---|---|
| `iron-law.md` | 所有有产出的 Layer 1/2 | 硬门禁五条 |
| `feature-id.md` | `prd.md` / `feature.md` | 功能 ID 分配算法 |
| `defect-id.md` | `fix.md` | 缺陷 ID 分配算法 |
| `pdlc-trace.md` | 所有生成文档的命令 | 追溯头模板 |
| `self-audit.md` | Layer 2 | 自检骨架（段二段三） |
| `loop-prevention.md` | 所有带自检的命令 | 防循环规则 |
| `state-update.md` | Layer 1/2 | 状态机更新逻辑 |
| `handoff.md` | Layer 1/2 | Handoff 输出格式 |

---

## 8. 扩展与自定义

### 8.1 修改文档模板

`references/templates/*-template.md` 是给用户项目用的文档模板（PRD / 设计 / 测试计划等）。改完后重跑 install 即可：

```bash
bash install.sh --upgrade --global
bash install.sh --upgrade --project /path/to/my-project
```

### 8.2 修改共享片段

`references/templates/prompts/*.md` 是命令级复用片段（IRON LAW / 自检骨架等）。改完后所有引用它的命令在下一次执行时自动用新内容（运行期 include，无需重新 install 命令文件本身，但**要重跑 install 把片段同步到目标 skill 目录**）。

### 8.3 添加新的共享片段

1. 在 `references/templates/prompts/` 下新建 `<name>.md`
2. 在需要的命令里加 `<!-- @include templates/prompts/<name>.md -->`（独占一行）
3. 跑 `bash tests/frontmatter-check.sh` 验证 `@include` 路径解析
4. 跑 `bash tests/install-smoke.sh` 验证落盘
5. 更新本文档 §7 的片段清单

### 8.4 添加新命令

1. 在 `references/commands/` 下新建 `<name>.md`
2. 文件顶部加 YAML frontmatter（参考 §4 的字段表）
3. Layer 1/2 且产出文件的命令必须 `@include templates/prompts/iron-law.md`、`state-update.md`、`handoff.md`；Layer 3 一般只需 `handoff.md`
4. 运行 `bash tests/frontmatter-check.sh` 验证 frontmatter 合规
5. 运行 `bash tests/install-smoke.sh` 验证安装过程
6. 更新 README 的命令清单 + 本文档

### 8.5 自定义硬门禁语气

`references/templates/prompts/iron-law.md` 可以按团队风格调整。但建议保持：

- 用 ⛔ emoji 和 **IRON LAW** 大写关键词增强语感
- 用"必须 / 不可 / 违反即中止"这类**极硬语气**
- 保留"防循环"条款防 agent 死循环

### 8.6 回归测试

两份脚本在 `tests/`：

- **`frontmatter-check.sh`** — 验证所有 `references/commands/*.md` 的 frontmatter：必填字段、layer 取值、Layer 1/2 含 IRON LAW、`next_step` 有效、`@include` 路径可解析
- **`install-smoke.sh`** — 端到端验证 `install.sh` 落盘 / 排除清单 / upgrade 幂等 / uninstall 清理

CI 在每次 PR 上自动跑这两条。本地手动：

```bash
bash tests/frontmatter-check.sh    # 期望：31 passed
bash tests/install-smoke.sh        # 期望：全绿
```

---

## 9. 相关资源

- [README.md](../README.md) — 项目概览 + 命令速查（英文）
- [README.zh-CN.md](../README.zh-CN.md) — 项目概览 + 命令速查（中文）
- [usage-guide.md](./usage-guide.md) — 日常使用快速手册
- [CHANGELOG.md](../CHANGELOG.md) — 版本历史
- [CONTRIBUTING.md](../CONTRIBUTING.md) — 如何贡献
- [SECURITY.md](../SECURITY.md) — 安全策略
- [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — 行为准则
