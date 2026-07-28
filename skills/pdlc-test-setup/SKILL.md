---
name: pdlc-test-setup
description: 立测试地基（探测技术栈 → 验证并生成 test-commands.yml → 脚手架测试目录 → 接本地钩子）
argument-hint: [项目目录] [--autonomous]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
artifact_type: surface
produces:
  - docs/00_standards/test-commands.yml
requires: []
next_step: null
terminal_state: null
recommended_model: sonnet
recommended_effort: medium
---

# 立测试地基

给项目一键立起「客观 check」的地基：**探测技术栈 → 逐条验证命令真能跑 → 写 `docs/00_standards/test-commands.yml` → 脚手架测试目录 → 接本地钩子**。

<!-- @include templates/prompts/iron-law.md -->
<!-- @include templates/prompts/noninteractive.md -->

## 为什么需要它

pdlc 的命门是「`checks` 只认命令退出码，绝不用模型自评」——`pdlc-tdd` / `pdlc-implement` / `pdlc-review`
与外层循环全都从 `docs/00_standards/test-commands.yml` 取命令。但**在此之前没有任何东西帮你把这个文件立起来**，
没有它，整条客观化链路就是空的。本命令把这块地基变成 turnkey。

> ⛔ **本命令最重要的一条纪律**：**写进 `test-commands.yml` 的每条命令，必须先被真跑过一次、亲眼看到退出码。**
> 一条"看起来对但跑不了"的命令**比留空更坏**——它会让下游每个阶段都拿到假的 `checks`，
> 而整个 pdlc 的可信度正建立在这些 checks 是真的之上。**猜出来的命令一律不写。**

## 段一：探测与验证

### 1.1 技术栈探测

扫描特征文件，识别语言 / 包管理器 / 测试框架：

| 特征文件 | 栈 | 典型 unit | 典型 coverage | 典型 lint |
|---|---|---|---|---|
| `Cargo.toml` | Rust | `cargo test` | `cargo llvm-cov --fail-under-lines <阈值>` | `cargo clippy -- -D warnings` |
| `package.json` | Node | `pnpm test` / `npm test` | `vitest run --coverage.thresholds.lines=<阈值>` | `npx eslint .` |
| `pyproject.toml` / `requirements.txt` | Python | `pytest` | `pytest --cov --cov-fail-under=<阈值>` | `ruff check .` |
| `go.mod` | Go | `go test ./...` | `go test ./... -cover` | `golangci-lint run` |
| `pom.xml` / `build.gradle` | JVM | `mvn test` / `./gradlew test` | jacoco check | `mvn checkstyle:check` |
| 仅 `*.sh` | Shell | 项目自有测试脚本 | —（通常无） | `shellcheck <文件>` |

**多语言 / monorepo**：逐个子项目探测；`test-commands.yml` 只能有一组命令，所以要么用能覆盖全仓的聚合命令
（如 `pnpm -r test`），要么与用户确认以哪个子项目为准。**探测不到唯一答案时不要自己拍板**（见 §1.3）。

### 1.2 逐条验证（不可跳过）

对每个候选命令**真的跑一次**，按退出码归类：

| 观察到的结果 | 结论 | 动作 |
|---|---|---|
| 退出码 0 | 命令可用且当前通过 | **采纳** |
| 退出码非 0、非 127，且输出像测试/lint 报告 | 命令可用，只是当前有失败项 | **采纳**（地基是"命令能跑"，不是"当前全绿"） |
| 退出码 127 / `command not found` / 工具未安装 | 命令不可用 | **留空**，在报告里写明缺什么 |
| 无对应配置（如没配覆盖率工具） | 该项本项目暂无 | **留空** |
| 命令挂起 / 需要交互 | 不适合做自动 check | **留空**，报告里说明 |

> ⚠️ **留空是合法且诚实的结果**，与状态机里「没有检查命令可跑的阶段 → `checks: {}` 留空」同一条纪律。
> 宁可空着并在报告里提示怎么补，也不要写一条没验证过的命令。

**覆盖率达标线写死在命令参数里**（如 `--cov-fail-under=85`），不做二次解释——这样"达标"就是退出码本身，
不需要任何一方去解析百分比数字。默认阈值 **85%**；项目已有更高要求则沿用已有。

### 1.3 需要人拍板的点（`--autonomous` 下 block，不猜）

以下属判断题而非流程题，**不得自动选**，须写明原因交还人类：

- 探测到**多个**并列候选（如同时有 `jest` 和 `vitest` 配置），无法判定以哪个为准
- **零候选**（项目还没有任何测试框架）——装哪个框架是技术选型，必须人定
- monorepo 里以哪个子项目 / 哪条聚合命令为准
- 覆盖率阈值定多少（若项目无既有约定）

探测到**唯一**候选且验证通过 → 属流程性确认，`--autonomous` 下自动采纳并在报告里留痕。

## 段二：落地

### 2.1 写 `docs/00_standards/test-commands.yml`

以 `templates/test-commands-template.yml` 为骨架。**这是 surface 型产物**——就地编辑，不做 `-v2` 累积。

- **文件已存在** → **不覆盖**。改为逐条校验现有命令是否仍能跑：
  - 仍能跑 → 保持原样（用户的选择优先于探测结果）
  - 已跑不通（工具改名 / 脚本删了）→ 报告里列出，**建议**改法，等人确认
  - 缺失的项（空字符串）→ 若这次探测到可用命令，提议补上
- **文件不存在** → 用本次验证通过的命令生成；未验证通过的项留空字符串。

### 2.2 脚手架测试目录（已有则不动）

按栈惯例建空目录 + 一个占位说明，**不生成业务测试用例**：

- Rust `tests/`、Node `src/__tests__/` 或 `tests/`、Python `tests/`、Go 同包 `*_test.go`、JVM `src/test/java/`
- 若项目是 `backend/services/*` / `frontend/*` 布局，按 `pdlc-implement` 前置守卫认得的路径建
  （`backend/services/<name>/tests/`、`frontend/<app>/src/__tests__/`），否则守卫会找不到测试而误拦

### 2.3 接本地钩子（不进 CI）

在**本地** git 钩子里跑基础 check（`husky` / `lefthook` / `pre-commit` / 原生 `.git/hooks`，按项目已有的来）：

- **pre-commit**：`lint`（快，秒级）
- **pre-push**：`unit`（+ `coverage` 若已配）

> **不新建 CI workflow**：这些 check 本地秒级可得，放 CI 只会让每次迭代都烧配额。
> 已有 CI 的项目也不改它的触发条件——那需要项目所有者单独授权。

### 2.4 老项目：可选的轻量底线回填

仅当用户要求：为**当前覆盖率最低**的若干核心模块补特征化测试（characterization test，锁住现有行为），
把覆盖率抬到阈值线。**这不是补齐测试**，只是让地基能立住。深度用例仍走 `/pdlc-tdd`。

## 段三：自检（强制）

<!-- @include templates/prompts/self-audit.md -->

### 自检清单（必须全部检查）

- [ ] `test-commands.yml` 里**每一条非空命令**，都在本次会话中被真跑过、看到过退出码
- [ ] **收尾复跑一遍**：从写好的 yml 里逐条读命令再跑一次，确认与写入时的结论一致（防止写错路径 / 引号）
- [ ] 留空的项，报告里都写明了「为什么空」和「怎么补」
- [ ] 覆盖率阈值已写死在命令参数里，不依赖任何一方解析百分比
- [ ] 测试目录路径能被 `pdlc-implement` 的前置守卫找到（`backend/services/*/tests/` 等布局）
- [ ] 钩子是**本地**的，没有新建或修改任何 CI workflow
- [ ] 已存在的 `test-commands.yml` 没有被静默覆盖

## 段四：修复（单次，不递归）

<!-- @include templates/prompts/loop-prevention.md -->

- 复跑发现某条命令与写入时结论不一致 → 修正或改为留空
- 无法自动修复 → 记入报告，交还人类

## 段五：交接

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 测试地基已立：docs/00_standards/test-commands.yml
  unit     : <命令>            （退出码 <N>，已验证）
  coverage : <命令 | 留空>      （<验证结论 | 为什么空>）
  lint     : <命令>            （退出码 <N>，已验证）
  e2e      : <命令 | 留空>      （<验证结论 | 为什么空>）
🪝 本地钩子：pre-commit → lint · pre-push → unit
📁 测试目录：<路径列表>
⚠️ 待人工：<留空项怎么补 / 需要拍板的选型>
👉 下一步：/pdlc-tdd <功能描述>   —— 本命令只立地基，深度用例走 TDD
```

## 诚实边界（务必如实说明，不要夸大）

- 本命令**只立地基 + 可选补底线**，**不生成完整测试套件**。AI 生成的测试容易浅、容易只测 happy path，
  真正的用例设计仍走 `/pdlc-tdd`（测试先行、红灯门）。
- 留空的项就是**当前没有**，不要为了让输出好看而填一条没验证过的命令。
- 覆盖率阈值只是一条线，**过线不等于测得好**——它挡的是"几乎没测"，不保证用例有效。

---

**目标项目**: $ARGUMENTS
