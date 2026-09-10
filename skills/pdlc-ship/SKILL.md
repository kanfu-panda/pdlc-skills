---
name: pdlc-ship
description: 发布工作流（跑测试 → bump VERSION → 更 CHANGELOG → tag → 触发 CI/CD）
argument-hint: [--version <x.y.z>] [--skip-tests (仅 hotfix)]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
layer: 2
stage: ship
produces:
  - VERSION
  - CHANGELOG.md
  - .git/refs/tags/v<version>
requires:
  - docs/.pdlc-state/
next_step: pdlc-deploy
terminal_state: ship_done
---

# 发布工作流

串联发布一个版本所需的所有步骤：跑测试 → 升级 VERSION → 更新 CHANGELOG → 创建 tag → 推送触发 CI/CD。

<!-- @include templates/prompts/iron-law.md -->
<!-- @include templates/prompts/noninteractive.md -->

> ⛔ **发布是破坏性·不可逆操作**：打 tag / bump 版本 / 触发 CI/CD 属破坏性范畴。**`--autonomous` 对本命令无效**——即使带该参数，§1.1（未完成功能）与 §1.2（测试门）的人工确认仍必须真实由人应答。自主循环（`/pdlc-loop-run`）的终态是 `review_done`，永不进入本命令。

## 段一：执行

### 1.1 前置检查

1. 确认当前分支不是 `master` / `main`（参考 CLAUDE.md §5）
2. 确认工作区干净（`git status` clean）
3. 检查 `docs/.pdlc-state/` 下是否有未完成的功能（`current_stage` 不在 `[*_done]` 的）
   - 有 → 列出来并询问是否继续（用户明确同意才继续）
   - 无 → 直接进入下一步
4. **质量闸门检查**（若项目有 `docs/00_standards/quality-targets.yml`）：
   读 `docs/07_reviews/quality/` 下**最近一份 `.md` 报告**（同名 `.html` 只是视图，
   闸门一律以 `.md` 为准——两者若不一致，信 `.md`）：
   - 无任何报告 → 提示先跑 `/pdlc-quality`，询问是继续还是先出报告
   - 报告**总判定未达标** → **默认不放行**；要发必须由人**显式 override 并写明理由**，
     该理由需记入本次发布的 CHANGELOG 或发布说明（不允许无声跳过）
   - 报告**过期**——分两档处理，**不是所有过期都等价**（见下）
   - 达标且未过期 → 在发布报告里引用该报告路径、日期与 commit SHA 作为质量证据

   #### 过期判定：按「改动了什么」分两档

   报告头部记着生成时的 `<!-- 仓库版本: <commit SHA> -->`（由 `/pdlc-quality` 落盘时写入）。
   取该 SHA，跑 `git diff --name-only <SHA>..HEAD` 看这期间动了什么：

   | 这期间改动命中 | 判定 | 理由 |
   |---|---|---|
   | `docs/01_requirements/prd/`、`docs/00_standards/quality-targets.yml`、`docs/00_standards/e2e-flow-map.yml`、`docs/00_standards/test-commands.yml` | **硬闸·不放行** | 报告里的 PRD ↔ `core_flows` 对账与 E2E 覆盖矩阵的**输入变了**，结论不再成立。重跑单测补不回对账——必须重跑 `/pdlc-quality` |
   | 只有其它代码 / 文档 | 提示已过期，**建议**重跑 | 对账仍成立，测量数字可能略旧 |
   | 报告里没有 `仓库版本` 字段，或该 SHA 在本仓库解析不了 | **按「不可判」处理**：明确告知无法核对新鲜度，建议重跑 | 与三态语义同一条纪律——「查不了」不等于「没问题」，不得静默当作未过期 |

   > ⛔ 硬闸同样允许人**显式 override 并写明理由**（与「总判定未达标」同一条通道，理由须记入
   > CHANGELOG 或发布说明），但**不得无声跳过**。

   #### `quality-targets.yml` 变动要单独看一眼「闸门是不是被调松了」

   若上表命中的文件里**包含 `quality-targets.yml`**，除了要求重跑，还必须把
   `git diff <SHA>..HEAD -- docs/00_standards/quality-targets.yml` **原样展示给人**，
   并逐条点出下列「变松」信号——**命中任何一条都要人明确确认，不得只当作普通过期**：

   - 覆盖率目标数字**下降**（如 85 → 70）
   - `core_flows` 条目**减少**（核心流被移出闸门视野）
   - lint 策略**放宽**（如 zero-warnings 改为允许若干 warning）
   - 新增了**豁免声明**（把某些 PRD / 流程排除在对账之外）

   > **为什么单列**：报告达标之后把目标调低，重跑一次照样是绿的——日期新、SHA 新、结论"达标"，
   > 但**尺子本身变短了**。这与 `/pdlc-test-setup --refresh` 的「严向自动、松向人确认」是同一条
   > 原则换个位置：**放松闸门永远是人的决定，不能由流程默默吸收。**

### 1.2 发布前测试门（参考 CLAUDE.md §6）

**必须主动询问用户**（不得默认跳过，也不得默认强制跑）：

```
📦 发布前测试门检查：是否先跑全量单测 + E2E 测试？

[选项 A] 跑测试（推荐）
  → 后端：./gradlew test 或 mvn test
  → 前端：pnpm test 或 npm test
  → E2E：pnpm exec playwright test（如有）

[选项 B] 跳过测试 —— 仅适用于生产 hotfix
  → 理由：<请说明>
  → 自动记录到 commit 消息

请选择 A 或 B。
```

若选 B：`$ARGUMENTS` 必须含 `--skip-tests` 且有理由说明，否则中止。

### 1.3 版本号处理

1. 读取当前 `VERSION` 文件
2. 若 `$ARGUMENTS` 带 `--version x.y.z`，用指定值；否则按语义化规则建议：
   - 本次发布含 fix 且无 feature → 补丁号 +1
   - 含 feature 且无 breaking → 次版本号 +1
   - 含 breaking → 主版本号 +1
3. 写回 `VERSION`

### 1.4 更新 CHANGELOG.md

1. 读取 `docs/.pdlc-state/` 自上次 tag 以来所有 `current_stage` 在 `[*_done]` 的功能
2. 按 `stage` 分组（feature → "新增"，fix → "修复"，refactor → "重构"）
3. 每条用"- <简要描述>（<feature-id>）"格式写入 CHANGELOG 的 `[未发布]` 段
4. 把 `[未发布]` 改为 `[<new-version>] - <今日日期>`

### 1.5 创建 Tag 并提交

```bash
git add VERSION CHANGELOG.md
git commit -m "release: v<new-version>"
git tag -a "v<new-version>" -m "Release v<new-version>"
```

若选项 B（跳过测试）：commit 消息末尾追加 `[skip-tests: <理由>]`。

### 1.6 CI/CD 配置管理

若项目尚未有 CI 配置，根据技术栈生成对应的 CI 文件：

**GitHub Actions**（`.github/workflows/ci.yml`）：
- 触发：push 到 main / tag v* / PR
- 步骤：checkout → setup 运行时 → install → lint → test → build
- 按项目技术栈选模板（Node/Python/Java/Go）
- 敏感信息通过 Secrets 注入，不硬编码（never hardcode secrets — use Secrets / env vars）
- 支持按服务单独触发（路径过滤）

**GitLab CI**（`.gitlab-ci.yml`）：
- stages: build / test / deploy
- cache: 依赖目录
- jobs: 对应各 stage 的执行命令
- 生产环境：手动审批后部署

**Jenkins**（`Jenkinsfile`）/ **云效 / 其他**：按项目已有约定生成。

若已有 CI 配置，检查是否覆盖本次新增的功能/测试路径，必要时更新。
生成后在 `docs/05_deployment/ci-cd/` 下记录流水线使用说明。

## 段二：自检

<!-- @include templates/prompts/self-audit.md -->

**发布自检清单：**
- [ ] VERSION 已更新到新版本号
- [ ] CHANGELOG 有本次发布条目
- [ ] tag 已创建（`git tag -l v<new-version>` 返回非空）
- [ ] 若选 A，测试已全绿
- [ ] 若选 B，commit 消息含 `[skip-tests]` 标记
- [ ] 分支不是 main/master

<!-- @include templates/prompts/loop-prevention.md -->

## 段三：修复（若需）

针对未通过项：
- VERSION 未更新 → 重跑 1.3
- CHANGELOG 缺失 → 重跑 1.4
- tag 未创建 → 重跑 1.5
- 分支错误 → 立即中止（不可自动修复）

## 段四：更新状态机 + 交接

<!-- @include templates/prompts/state-update.md -->

**本阶段状态机更新**：对所有本次发布涉及的功能，追加 `{ "stage": "ship", ... }` 到其 history。

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 发布准备完成：v<new-version>
  - VERSION：已更新
  - CHANGELOG：已追加
  - Tag：v<new-version> 已创建
  - 测试：<通过 / [skip-tests: 理由]>
📦 状态机：已更新 <N> 个功能
👉 下一步：/pdlc-deploy v<new-version>（或手动 git push origin v<new-version> 触发 CI）
```

---

**参数**：$ARGUMENTS
