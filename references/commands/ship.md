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

## 段一：执行

### 1.1 前置检查

1. 确认当前分支不是 `master` / `main`（参考 CLAUDE.md §5）
2. 确认工作区干净（`git status` clean）
3. 检查 `docs/.pdlc-state/` 下是否有未完成的功能（`current_stage` 不在 `[*_done]` 的）
   - 有 → 列出来并询问是否继续（用户明确同意才继续）
   - 无 → 直接进入下一步

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
- 注释使用中文；敏感信息通过 Secrets 注入，不硬编码
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
