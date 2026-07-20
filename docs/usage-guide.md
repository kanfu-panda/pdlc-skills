# pdlc-skills 使用手册

> 这是 pdlc-skills 唯一的用户文档。涵盖：怎么安装、怎么调用、有哪些工作流、状态机怎么看、典型场景、扩展方式。

---

## 目录

1. [5 分钟上手](#1-5-分钟上手)
2. [安装 / 升级 / 卸载](#2-安装升级卸载)
3. [怎么调用 PDLC](#3-怎么调用-pdlc)
4. [36 个内置阶段（按层）](#4-36-个内置阶段按层)
   - [在状态栏显示 PDLC 状态（可选）](#45-在状态栏显示-pdlc-状态可选)
5. [状态机文件](#5-状态机文件)
6. [目标项目目录契约](#6-目标项目目录契约)
7. [典型场景](#7-典型场景)
8. [设计哲学 + IRON LAW](#8-设计哲学--iron-law)
9. [四段式工作流](#9-四段式工作流)
10. [扩展：自定义文档模板](#10-扩展自定义文档模板)
11. [FAQ](#11-faq)

---

## 1. 5 分钟上手

pdlc-skills 是一个 Claude Code plugin，给 Claude 加上完整的 PDLC（产品开发生命周期）工作流——36 个标准化阶段，全部以斜杠命令暴露。

最常用三件事：

| 我想做... | 在 Claude Code 里输入 |
|---|---|
| 写一个新功能（PRD → 设计 → TDD → 实现 → 评审） | `/pdlc-feature 给登录加手机号验证` |
| 修一个 bug | `/pdlc-fix 修分页器在 0 条时崩溃` |
| 看当前 PDLC 进展 | `/pdlc-status` |

输入 `/pdlc-` 后下拉菜单会列出全部 36 个阶段，按 Tab 补全或直接挑。

---

## 2. 安装 / 升级 / 卸载

### 安装（推荐：一行 curl，无需 clone）

```bash
# 全局
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global

# 项目级
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --project /path/to/my-project
```

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

输出会告诉你"已安装版本 vs GitHub 最新版本"，落后时给出升级命令。

### 验证安装

```bash
ls ~/.claude/plugins/pdlc/                       # 全局
ls /path/to/my-project/.claude/plugins/pdlc/     # 项目级
```

应能看到 `.claude-plugin/` / `skills/` / `references/` / `VERSION` 等。

在 Claude Code 里输入 `/pdlc-`，下拉框出现 36 个阶段就说明 plugin 已生效。

### 想自定义模板的高级用户

```bash
git clone https://github.com/kanfu-panda/pdlc-skills.git
cd pdlc-skills
# 改 references/templates/*-template.md
bash install.sh --global
```

---

## 3. 怎么调用 PDLC

pdlc-skills 是 Claude Code plugin，**36 个阶段都是独立斜杠命令**，全部以 `/pdlc-` 开头：

```
/pdlc-feature      ← 一句话需求驱动全流程
/pdlc-prd          ← 单独走 PRD 阶段
/pdlc-design       ← 单独走技术设计
/pdlc-tdd          ← 测试先行
/pdlc-implement    ← 实现代码
/pdlc-review       ← 代码评审
/pdlc-ship         ← 发布
... 共 36 个
```

输入 `/` 然后开始打 `pdlc-`，Claude Code 会自动补全。

每个斜杠命令后跟参数（自然语言描述）：

```
/pdlc-feature 给用户登录加手机号验证（P0）
/pdlc-prd 只生成 PRD：登录加验证码
/pdlc-tdd 给 F20260502-090000 写测试用例
/pdlc-fix 分页器在结果列表为 0 条时崩溃
```

每个阶段也支持自然语言自动触发——不打斜杠也能 work：

```
"用 PDLC 给登录加验证码"  ← Claude 自动路由到 /pdlc-feature
"按 PDLC 写测试"          ← Claude 自动路由到 /pdlc-tdd
```

---

## 4. 36 个内置阶段（按层）

### Layer 1 · 入口（3 个，新手只看这层）

一句话需求驱动整条链路。

| 斜杠命令 | 用途 |
|---|---|
| `/pdlc-feature` | 全自动新功能（PRD → 设计 → TDD → 实现 → 评审 → 发布） |
| `/pdlc-fix` | 全自动 Bug 修复（定位 → 复现 → 修复 → 测试 → 文档） |
| `/pdlc-status` | 项目 PDLC 状态总览（不落盘） |

### Layer 2 · 阶段（11 个，单阶段精细控制）

| 斜杠命令 | 用途 | 下一阶段 |
|---|---|---|
| `/pdlc-prd` | 创建 PRD | `/pdlc-design` |
| `/pdlc-design` | 技术设计（API/DB/架构/UI 按需） | `/pdlc-tdd` |
| `/pdlc-tdd` | 测试先行（红灯） | `/pdlc-implement` |
| `/pdlc-implement` | 按设计 + 测试实现代码（绿灯） | `/pdlc-review` |
| `/pdlc-review` | 代码 + 文档评审 + 自动修复 | `/pdlc-ship` |
| `/pdlc-e2e` | 端到端测试 | `/pdlc-review` |
| `/pdlc-refactor` | 代码重构（外部行为不变） | `/pdlc-review` |
| `/pdlc-ship` | 发布流水线（测试 → bump → CHANGELOG → tag → CI） | `/pdlc-deploy` |
| `/pdlc-deploy` | 部署文档 | — |
| `/pdlc-retro` | 迭代复盘（趋势对比） | — |
| `/pdlc-task` | 阶段内任务跟踪 | — |

### Layer 3 · 工具（22 个，专项叠加）

**🎨 设计（4）**：`/pdlc-ui-design` · `/pdlc-ui-design-pro` · `/pdlc-db-design` · `/pdlc-arch`
**🔍 质量（3）**：`/pdlc-lint` · `/pdlc-perf` · `/pdlc-security`
**🔧 工程（7）**：`/pdlc-code-gen` · `/pdlc-add-service` · `/pdlc-add-app` · `/pdlc-api-mock` · `/pdlc-db-migrate` · `/pdlc-i18n` · `/pdlc-changelog`
**🔗 治理（2）**：`/pdlc-standard` · `/pdlc-relate`
**🏗️ 项目生命周期（3）**：`/pdlc-bootstrap` · `/pdlc-adopt` · `/pdlc-onboard`
**🔁 循环工具（2）**：`/pdlc-loop-next`（打印下一条机械收敛命令）· `/pdlc-loop-run`（收敛引擎：自动推进 `tdd → implement → review` 到 `review_done`，发布留人）。见 `docs/decisions/0001-loop-engineering-integration.md`
**⚙️ 设置（1）**：`/pdlc-settings`（交互式配置，当前含状态栏 statusline 的启用/停用/展示项）。见下方「在状态栏显示 PDLC 状态」及 `docs/decisions/0002-statusline-pdlc-status.md`

---

## 4.5 在状态栏显示 PDLC 状态（可选）

pdlc-skills 可在 Claude Code 底部状态栏**独占一行**显示当前 PDLC 运行状态——功能名、阶段进度条、下一步、检查结果、blocked。**默认关闭**，用 `/pdlc-settings` 一步开启，无需手改配置文件。

```
● PDLC auth · PRD·设计·TDD·[实现]·评审·发布 · →评审 · 👤          ← 手动开发中
● PDLC payment · PRD·设计·TDD·[实现]·评审·发布 · →评审 · 🤖 ✓unit ✓lint ⏱3m   ← loop 自主收敛中
⛔ PDLC search blocked: PRD 取舍需人工 · ⏱12m                     ← 卡住等人（全行最醒目）
```

### 开启

```
/pdlc-settings statusline
```

选「启用」，它会：建稳定链接 `~/.claude/pdlc-statusline` → **追加**到你现有的 `statusLine.command` 后（幂等、绝不覆盖你已有的状态栏/HUD）→ 备份 + 展示 diff + 你确认后写入。

> ⚠️ **机制**：Claude Code 只有一个 `statusLine.command` 槽。PDLC 段是**追加**进这条命令（多输出一行），**不是**新增第二个 statusLine——所以不会覆盖你现有的状态栏。写全局 `~/.claude/settings.json` 可能被安全层拦截，届时 `/pdlc-settings` 会给出「算好的那一行 + 手动粘贴位置」，不会谎报已启用。
>
> ℹ️ **和会排空 stdin 的状态栏（如 claude-hud）组合时**：`your-hud.sh; ~/.claude/pdlc-statusline` 里前一条命令会读掉 stdin，PDLC 段拿到空输入——此时它**自动回退用终端当前目录**（Claude Code 会把状态栏命令的 cwd 设为你的项目），照常识别 PDLC 状态。无需你做额外处理。

### 展示项与配置

`/pdlc-settings` 的「展示项」交互勾选下列开关，写入 `~/.claude/pdlc-statusline.json`（或项目级 `docs/.pdlc-state/statusline.json` 覆盖）；模板见 `references/templates/pdlc-statusline.example.json`：

| 键 | 默认 | 说明 |
|---|---|---|
| `show_progress_bar` | on | 迷你进度条 |
| `show_next` | on | 下一步 |
| `show_run_icon` | on | 👤手动 / 🤖autonomous |
| `show_checks` | auto | 检查结果，auto=仅 autonomous 显 |
| `show_elapsed` | auto | 停留时长，auto=blocked/autonomous 显 |
| `show_full_id` | off | 显示完整 ID 而非仅功能名 |
| `pick_feature` | auto | 多 feature 选谁：非终态+blocked 优先 |
| `color` | on | ANSI 颜色（`NO_COLOR` 也会关） |

非 PDLC 项目 / 无状态文件时该行**自动为空**，不干扰其它项目。

### 停用

```
/pdlc-settings statusline   # 选「停用」——只摘掉 PDLC 段，不动你其它状态栏配置
```

---

## 4.6 在其它工具里用 PDLC（多平台）

Claude Code **集成最全**（本手册前面全部内容）。但 PDLC 的方法论、状态机、模板是**平台中立**的——同一份 `docs/.pdlc-state/` 谁都能推，换工具不丢状态。设计与路线见 `docs/decisions/0003-multi-platform-adapters.md`。

**两种用法：**

1. **任意工具（Codex / Cursor / Windsurf / Copilot / Cline …）· 自然语言驱动**
   把平台中立方法论文档 `docs/pdlc-methodology.md` 作为你项目的规则文件（`AGENTS.md` / `.cursor/rules/` / `.github/copilot-instructions.md` / `.clinerules/` 等），然后用自然语言驱动：
   ```
   按 pdlc 给这个功能跑一遍需求分析     → 走 PRD 阶段
   按 pdlc 跑 TDD / 做实现 / 评审        → 对应阶段
   按 pdlc 看状态                        → 只读状态视图
   ```
   agent 读到指令后按方法论文档执行：读/建状态机 → 四段式 → 客观检查 → 更新状态机并交接。

2. **Codex · 原生 skills**（面向兼容 Claude Code 生态的 Codex 发行版）
   ```bash
   git clone https://github.com/kanfu-panda/pdlc-skills.git
   cd pdlc-skills && bash install.sh --target codex
   ```
   构建适配器（`adapters/build_codex.py`）并把 34 个 pdlc skill 装到 `~/.codex/skills/`、模板与方法论到 `~/.codex/pdlc/`。Codex skill 靠 **description 触发，不是斜杠命令**——重启 Codex 后用自然语言驱动（如 `用 pdlc 写个 PRD：<一句话需求>`），gpt 系模型按描述匹配到对应 skill。需本地克隆 + python3。移除：`bash install.sh --target codex --uninstall`。

3. **Codex · 自主收敛循环**（无人值守把 `tdd → implement → review` 推到 `review_done`）
   ```bash
   adapters/codex-loop-run.sh <功能ID> --project <项目目录> [--max-steps 4] [--dry-run]
   ```
   外部 bash 循环（loop-run 的 Runbook 版）：每轮读状态机 → 判下一跳 → `codex exec "按 pdlc <阶段> <id> --autonomous"` → 读回判护栏（上限停机 / fail-stop / stuck-stop）。**发布永远人工**——到 `review_done` 即停，绝不自动 ship/deploy。放行前 Codex 已过状态完整性准入闸（真机验证真跑 test-commands、诚实写 checks），设计与真机结果见 `docs/decisions/0004-codex-loop-run.md`。`--dry-run` 可离线看每步决策不真跑 codex。

> **哪些能力仅 Claude Code**：状态栏（§4.5，本就是 shell 脚本非 skill）、自主收敛引擎的 `pdlc-loop-run` **skill**（Task 版耦合 Claude 子代理，改用上面的 `codex-loop-run.sh` Runbook 驱动替代）、配置命令 `pdlc-settings`——这 2 个 skill 不投影到其它平台（`pdlc-loop-next` 逻辑平台中立，已投影）。
>
> **跨工具状态延续的前提**：每个平台都老实遵守 IRON LAW 与「客观检查不虚报」（`checks` 来自真实退出码，不用模型自评）。任一平台写脏状态就污染所有平台共用的那份——这也是新平台接入前要过「状态完整性准入闸」的原因（ADR 0003 §6.1）。

---

## 5. 状态机文件

每个功能在你的项目里对应一个 `docs/.pdlc-state/<feature-id>.json`，记录该功能走过的阶段、产物、自检结果、下一跳建议。

### Schema 示例

```json
{
  "feature_id": "F20260502-090000",
  "feature_name": "user-auth",
  "created_at": "2026-05-02T10:00:00+08:00",
  "current_stage": "review",
  "history": [
    {
      "stage": "requirements",
      "done_at": "2026-05-02T10:05:00+08:00",
      "produced": ["docs/01_requirements/prd/F20260502-090000-user-auth-prd.md"],
      "self_audit": { "passed": 8, "failed": 0, "manual": 0 }
    }
  ],
  "next_step": "ship",
  "terminal_state": null
}
```

### 怎么用

- `/pdlc-status` → 列所有功能的当前阶段、待办建议
- `/pdlc-status F20260502-090000` → 单功能完整 history
- `/pdlc-status --stale 3` → 列出停 3 天以上的功能
- `/pdlc-retro --range 30d` → 月度复盘趋势报告

### 提交 git

**建议提交**。这是项目交付审计记录，别加 `.gitignore`。

---

## 6. 目标项目目录契约

执行 PDLC 命令时会在你项目的 `docs/` 下读写这些路径：

```
docs/00_standards/coding/                                   # 编码规范（被 prd/implement/tdd/code-gen/onboard 读取，可选）
docs/00_standards/test-commands.yml                        # check 命令唯一真源（unit/coverage/lint/e2e），被 tdd/implement/review 与循环驱动读取
docs/01_requirements/prd/                                   # PRD
docs/02_design/{api,database,architecture,ui-ux}/           # 技术设计
docs/03_development/                                        # 开发者手册（onboard 产出）
docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/   # 测试与缺陷
docs/05_deployment/                                         # 部署
docs/06_tasks/                                              # 任务跟踪
docs/07_reviews/{doc,code,design,retro}/                    # 评审 + 复盘
docs/.pdlc-state/<feature-id>.json                          # 状态机（每功能一份）
```

### PDLC-TRACE 追溯头

每个带编号的 PDLC 文档顶部必须有：

```html
<!-- PDLC-TRACE -->
<!-- 功能ID: F20260502-090000 -->
<!-- 功能名称: user-auth -->
<!-- 阶段: requirements -->
<!-- 前置文档: 无 -->
<!-- 创建时间: 2026-05-02T10:00:00+08:00 -->
```

作用：从任一文档反向追溯它属于哪个功能、哪个阶段、前置文档是什么。

### ID 规则

- **功能 ID**：`F<YYYYMMDD>-<HHMMSS>`（创建时刻的时分秒，如 `F20260717-122801`）
- **缺陷 ID**：`B<YYYYMMDD>-<HHMMSS>`（如 `B20260717-122801`）
- 用时分秒而非当日序号，是为了**多人 / 多 AI 并行时零协调也几乎不撞号、合并零冲突**（仅同一秒创建才可能撞，撞了自动 +1 秒）。旧的 2 位序号 ID（`F<日期>-01`）仍兼容可解析。

---

## 7. 典型场景

### 场景 A：从零做个功能（一条命令）

```
/pdlc-feature 给用户登录加手机号验证（P0），支持中国大陆手机号，失败 3 次锁定 15 分钟
```

Claude 会自动：
1. 分配功能 ID `F20260502-090000`，创建 PRD
2. 设计 API、数据模型、前端页面
3. 生成失败的测试用例（红灯）
4. 实现代码到测试绿灯
5. Review 代码 + 文档
6. 提示用 `/pdlc-ship` 触发发布

### 场景 B：手动控制每阶段

```
/pdlc-prd 登录加手机号验证      # 停在 PRD
# 你审 docs/01_requirements/prd/F20260502-090000-*.md，调整后：
/pdlc-design F20260502-090000
/pdlc-tdd F20260502-090000
/pdlc-implement F20260502-090000
/pdlc-review F20260502-090000
/pdlc-ship
```

### 场景 C：修 bug

```
/pdlc-fix 分页器在 0 条时崩溃
```

自动：分配缺陷 ID `B20260502-090000` → 定位根因 → 写回归测试（红） → 修代码（绿） → 跑全量测试 → 更新 CHANGELOG 和缺陷记录。

### 场景 D：发布版本

```
/pdlc-ship --version <目标版本号>   # 如 1.5.0
```

自动：检测未完成功能 → 询问是否跑测试 → bump VERSION → 汇总 CHANGELOG → git tag → 触发 CI。

### 场景 E：月度复盘

```
/pdlc-retro --range 30d
```

生成 `docs/07_reviews/retro/2026-05-retro.md`，含交付量、各阶段自检通过率、平均耗时、卡点案例。

### 场景 F：旧项目接入 PDLC

```
/pdlc-adopt 帮我接入 PDLC 流程
```

走 `adopt` 阶段：扫描现有 `docs/`，逆向生成基线状态机，输出"接入报告"列出哪些章节需要补齐。

### 场景 G：自主循环收敛（Loop 工程）

`/pdlc-loop-run <功能ID>` 从 `current_stage` 自动推进 `tdd → implement → review` 到 `review_done` 或 blocked，无人值守。**终态即 `review_done`——发布永远留人**，循环绝不自动 `/pdlc-ship`（详见 [ADR 0001](./decisions/0001-loop-engineering-integration.md)）。

前提：项目有 `docs/00_standards/test-commands.yml`（check 命令唯一真源），循环靠真跑退出码判停，不靠模型自评。

**插件内（便捷，适合短收敛）**：

```
/pdlc-loop-run F20260714-090000
```

每个 stage 派发一个 fresh Task subagent，遇 `blocked` 或状态未推进即停，默认迭代上限 4。

**外部 bash Runbook（真进程隔离，推荐长跑 / 过夜）**：每轮独立进程 = 真 fresh context，必须配预算护栏防烧 token：

```bash
ID="F20260714-090000"; MAX_STEPS=4
for _ in $(seq 1 "$MAX_STEPS"); do
  # 净化：切成 token（去反引号、按空白分行）再用 grep -x 整 token 匹配白名单
  # ——容忍空白/代码块包裹，又避免 done_at / blocked_reason 等子串被误抽成 done/blocked
  RAW=$(claude -p "/pdlc-loop-next $ID")
  CMD=$(printf '%s' "$RAW" | tr '`' ' ' | tr -s ' \t' '\n' | grep -xE '(pdlc-tdd|pdlc-implement|pdlc-review|done|blocked)' | head -1)
  case "$CMD" in
    pdlc-tdd|pdlc-implement|pdlc-review)
      # 模型按 skill frontmatter recommended_model 选；--max-budget-usd 是预算硬护栏
      claude -p --max-budget-usd 5 "/$CMD $ID --autonomous" || break ;;
    done)    echo "✅ 已到 review_done，交人工决定是否 /pdlc-ship"; break ;;
    blocked) echo "⛔ 需人工介入"; break ;;
    *)       echo "❌ 非法命令（原始输出：$RAW）"; exit 1 ;;
  esac
done
```

**护栏（不可省）**：迭代上限 + `--max-budget-usd` 预算 + 每轮读 `last_phase_result.ok` 判停。破坏性发布/部署永远留人。

---

## 8. 设计哲学 + IRON LAW

### 三层分层心智

PDLC 把 36 个阶段按使用频率分 3 层暴露：

- **Layer 1（3 个）**：高频入口，新手只学这层即可完成 80% 工作
- **Layer 2（11 个）**：单阶段精细控制
- **Layer 3（22 个）**：专项工具，按需叠加（含循环工具 `/pdlc-loop-next` · `/pdlc-loop-run`、设置 `/pdlc-settings`）

**你的心智**：做功能用 `feature`，修 bug 用 `fix`，看状态用 `status`——三个动词级指令。其他 29 个阶段需要时再用。

### IRON LAW：硬门禁不可协商

每个**产出文件**的 Layer 1/2 阶段都强制六条规则（`/pdlc-status` 这种只读阶段豁免）：

1. **文件必须落盘** — 不能只在对话里输出
2. **阶段必须落章** — 状态机 history 必须追加
3. **测试必须存在** — 进入 `implement` 前测试必须红灯
4. **自检必须执行** — 段二自检不可跳过
5. **防循环** — 段三修复仅一轮，不递归
6. **状态必推进** — 成功执行后 `current_stage` 必须变更，未推进即报错、不静默返回（防自主循环空转烧额度）；主动 block 例外，此时写 `blocked_reason`

**违反任一条 = 立即中止**。这避免 AI "轻飘飘地说做了但没落盘"，也避免循环拿滞后状态空转。

### Handoff：显式下一跳

每个 Layer 1/2 阶段结束时，Claude 会输出 handoff 块，告诉你"下一步该做什么"，并给出可直接复制的下一句调用。

---

## 9. 四段式工作流

每个 Layer 1/2 阶段统一为四段：

| 段 | 名称 | 职责 |
|---|---|---|
| 段一 | 执行 | 产出主文档 / 代码 / 配置 |
| 段二 | 自检 | 重读产物，按质量清单逐项检查 |
| 段三 | 修复 | 自动修复可修部分（单次，防循环） |
| 段四 | 交接 | 更新状态机 + 输出 handoff 下一步 |

`/pdlc-prd` 的执行轨迹示例：

```
段一：生成 PRD
  └→ docs/01_requirements/prd/F20260502-090000-user-auth-prd.md

段二：自检
  ✓ 背景与目标清晰
  ✓ 用户故事 >= 3 条
  ✗ 功能清单缺优先级
  ✓ 验收标准可度量
  ...（共 8 项质量关卡）

段三：修复
  → 自动补齐 P0/P1/P2 优先级标注
  → 重新检查：✓

段四：交接
  ✅ PRD 已创建
  📊 自检：8/8 通过
  📦 状态机已更新
  👉 下一步：/pdlc-design F20260502-090000
```

---

## 10. 扩展：自定义文档模板

plugin 自带 9 份用户文档模板（`references/templates/*-template.md`）。如果你的团队有自己的 PRD 格式 / API 设计模板，可以本地修改后重装：

```bash
git clone https://github.com/kanfu-panda/pdlc-skills.git
cd pdlc-skills

# 修改你需要定制的模板，例如 PRD：
$EDITOR references/templates/prd-template.md

# 重新安装到本地
bash install.sh --upgrade --global
```

之后所有走 `/pdlc-prd` 阶段的产出都会用你改过的模板。

> 想自定义阶段定义本身、加新阶段、改 IRON LAW 语气？这些是贡献者级别的扩展，请看 `CONTRIBUTING.md` 和 `CLAUDE.md`。

---

## 11. FAQ

**Q：可以跳过某个阶段吗？**
A：Layer 2 可以，但 `/pdlc-implement` 会检查测试是否存在——没测试会提示要先跑 `/pdlc-tdd`，这是**硬门禁（IRON LAW）**，不可绕过。

**Q：状态机文件要提交到 git 吗？**
A：**要**。`docs/.pdlc-state/*.json` 是审计记录，便于后续复盘和团队协作。

**Q：我卡在某一阶段了，怎么办？**
A：三步排查：
1. `/pdlc-status <feature-id>` 看当前在哪、下一步建议什么
2. 如果 Claude 报错，读错误信息（通常是硬门禁：缺文档、缺测试）
3. 补齐前置条件后重跑——状态机会自动续接，不会重复做已完成的阶段

**Q：AI 自动走完所有阶段会不会"跑偏"？**
A：每阶段有**自检 + 单次修复**机制（防循环），走完会输出自检报告。如果对某阶段产出不满意，单独跑该阶段的 Layer 2 命令即可，前后阶段不受影响。

**Q：怎么接入专业级 UI 设计（ui-ux-pro-max）？**
A：先装 `npm install -g uipro-cli && uipro init --ai claude`，然后 `/pdlc-ui-design-pro <设计目标>` 会自动调用它的 67 风格 / 161 配色 / 13 技术栈库。

**Q：产出语言怎么决定？**
A：**默认匹配你和 Claude 的对话语言**——你用中文聊，产出中文 PRD/代码注释；用英文聊，产出英文。也可以显式指定：`/pdlc-prd 给 X 做 PRD，用英文写`。

**Q：我想确认 plugin 已正确加载怎么办？**
A：在 Claude Code 里打 `/`，看下拉里能否找到 `/pdlc-feature` 等。能找到就是装好了。

**Q：能不能在多个仓库共享 PDLC 状态？**
A：当前不行。每个目标项目维护自己的 `docs/.pdlc-state/`，跨仓库共享需要团队约定，超出 plugin 范围。

**Q：发现 bug 或想提建议怎么办？**
A：[GitHub Issues](https://github.com/kanfu-panda/pdlc-skills/issues)（用模板）。讨论性问题用 [Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions)。安全问题见 [SECURITY.md](../SECURITY.md)。

---

**变更记录见 [`CHANGELOG.md`](../CHANGELOG.md)。贡献流程见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)。**
