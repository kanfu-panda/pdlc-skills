---
name: pdlc-lint
description: 代码质量检查与自动修复
argument-hint: [目录 | 文件]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: quality
produces: []
requires: []
next_step: null
terminal_state: null
---

# 代码质量检查与自动修复

<!-- @include templates/prompts/iron-law.md -->

对项目代码执行静态分析、风格检查和质量度量，自动修复可安全修复的问题，输出结构化报告。

## 子命令解析

从 `$ARGUMENTS` 中解析子命令和参数：

| 子命令 | 格式 | 说明 |
|--------|------|------|
| `check [目标]` | 运行全量检查，输出报告（默认子命令） |
| `fix [目标]` | 自动修复可安全修复的问题 |
| `setup` | 为项目配置 lint 工具链（检测技术栈，生成配置文件） |

- `目标` 可选，支持：服务名、应用名、目录路径、文件路径。不传则检查整个项目。
- 如果未提供子命令，默认执行 `check`。

---

## 工具链自动探测

扫描项目目录，按以下优先级检测已有的 lint 工具：

### 前端 / Node.js 项目

按优先级检测（找到第一个可用的即停止）：

| 工具 | 检测方式 | 运行命令 |
|------|---------|---------|
| ESLint（flat config） | `eslint.config.*` 存在 | `npx eslint .` |
| ESLint（legacy） | `.eslintrc*` 存在 | `npx eslint .` |
| Biome | `biome.json` 或 `biome.jsonc` 存在 | `npx biome check .` |
| oxlint | `package.json` 含 `oxlint` 依赖 | `npx oxlint .` |

样式检查（与上述并行）：

| 工具 | 检测方式 | 运行命令 |
|------|---------|---------|
| Stylelint | `.stylelintrc*` 或 `stylelint.config.*` 存在 | `npx stylelint "**/*.{css,scss,less}"` |
| Prettier | `.prettierrc*` 或 `prettier.config.*` 存在 | `npx prettier --check .` |

TypeScript 类型检查（如存在 `tsconfig.json`）：
```bash
npx tsc --noEmit
```

### 后端 Java 项目

| 工具 | 检测方式 | 运行命令 |
|------|---------|---------|
| Checkstyle | `checkstyle*.xml` 或 pom.xml 含 checkstyle plugin | `mvn checkstyle:check` |
| SpotBugs | pom.xml 含 spotbugs plugin | `mvn spotbugs:check` |
| PMD | pom.xml 含 pmd plugin | `mvn pmd:check` |
| SonarQube | `sonar-project.properties` 或 pom.xml 含 sonar plugin | `mvn sonar:sonar`（需配置连接） |
| Spotless | pom.xml 含 spotless plugin | `mvn spotless:check` |

Gradle 项目检测 `build.gradle` / `build.gradle.kts` 并使用对应 gradle 命令。

### 后端 Go 项目

| 工具 | 检测方式 | 运行命令 |
|------|---------|---------|
| golangci-lint | `.golangci.yml` 或 `go.mod` 存在 | `golangci-lint run ./...` |
| go vet | `go.mod` 存在 | `go vet ./...` |
| staticcheck | `go.mod` 存在 | `staticcheck ./...` |

### 后端 Python 项目

| 工具 | 检测方式 | 运行命令 |
|------|---------|---------|
| Ruff | `ruff.toml` 或 `pyproject.toml` 含 `[tool.ruff]` | `ruff check .` |
| Flake8 | `.flake8` 或 `setup.cfg` 含 `[flake8]` | `flake8 .` |
| Pylint | `.pylintrc` 或 `pyproject.toml` 含 `[tool.pylint]` | `pylint **/*.py` |
| MyPy | `mypy.ini` 或 `pyproject.toml` 含 `[tool.mypy]` | `mypy .` |
| Black | `pyproject.toml` 含 `[tool.black]` | `black --check .` |

---

## 子命令执行流程

### check [目标]

1. **探测工具链**：按上述规则检测项目使用的 lint 工具
2. **未检测到任何工具** → 输出提示后**自动执行 setup 子命令**：
   ```
   ⚠️ 未检测到 lint 工具配置，正在为项目自动配置...
   ```
3. **检测到工具** → 按以下顺序运行：
   a. 代码风格检查（ESLint / Biome / Checkstyle / golangci-lint / Ruff 等）
   b. 类型检查（TypeScript tsc / MyPy / go vet 等）
   c. 安全扫描（如有 `npm audit` / `mvn dependency:analyze` / `safety check`）
   d. 代码复杂度分析（从 lint 输出中提取，或使用工具内置规则）
4. **收集结果**，按严重程度分类：

   | 级别 | 含义 | 示例 |
   |------|------|------|
   | 🔴 Error | 必须修复 | 语法错误、类型错误、安全漏洞 |
   | 🟠 Warning | 应该修复 | 未使用变量、复杂度过高、潜在 Bug |
   | 🟡 Info | 建议修复 | 命名不规范、缺少 JSDoc、import 排序 |
   | 🔵 Style | 可自动修复 | 格式化、尾逗号、引号风格 |

5. **输出报告**：

```
## 代码质量报告

### 工具链
| 工具 | 版本 | 状态 |
|------|------|------|
| ESLint | 9.x | ✅ 已运行 |
| TypeScript | 5.x | ✅ 已运行 |
| Prettier | 3.x | ✅ 已运行 |

### 问题汇总
| 级别 | 数量 | 可自动修复 |
|------|------|-----------|
| 🔴 Error | N | N |
| 🟠 Warning | N | N |
| 🟡 Info | N | N |
| 🔵 Style | N | N |

### 问题详情（按文件分组）

#### `src/services/userService.ts`
| 行 | 级别 | 规则 | 描述 | 可修复 |
|----|------|------|------|--------|
| 23 | 🔴 | @typescript-eslint/no-explicit-any | 避免使用 any 类型 | ❌ |
| 45 | 🔵 | prettier/prettier | 格式化不一致 | ✅ |

### 质量指标
- 问题密度：X 个/千行代码
- 可自动修复比例：XX%

### 建议
👉 运行 `/pdlc-lint fix` 自动修复 N 个问题
```

### fix [目标]

1. **探测工具链**（同 check）
2. **先运行 check** 收集所有问题，统计可自动修复数量
3. **执行自动修复**（按工具分别运行）：

   | 技术栈 | 修复命令 |
   |--------|---------|
   | ESLint | `npx eslint --fix .` |
   | Biome | `npx biome check --write .` |
   | Prettier | `npx prettier --write .` |
   | Stylelint | `npx stylelint --fix "**/*.{css,scss,less}"` |
   | Spotless (Java) | `mvn spotless:apply` |
   | golangci-lint | `golangci-lint run --fix ./...` |
   | Ruff | `ruff check --fix .` |
   | Black | `black .` |

4. **修复后再次运行 check**，对比修复前后数量
5. **输出报告**：

```
## 自动修复报告

### 修复结果
| 指标 | 修复前 | 修复后 | 变化 |
|------|--------|--------|------|
| 🔴 Error | N | N | -N |
| 🟠 Warning | N | N | -N |
| 🟡 Info | N | N | -N |
| 🔵 Style | N | 0 | -N |
| **总计** | N | N | **-N** |

### 修改的文件
| 文件 | 修复数 |
|------|--------|
| src/xxx.ts | N |

### 剩余需手动修复的问题
（列出无法自动修复的 Error 和 Warning）

### 建议
- 🔴 Error 需要手动修复，建议逐一处理
- 考虑将 lint 检查加入 CI：`/pdlc-ship`（发布流水线含 CI/CD 配置管理）
```

6. **不自动提交**：修复后的文件保留为未暂存状态，由用户决定是否提交

### setup

1. **探测技术栈**：扫描 `package.json`、`pom.xml`、`build.gradle`、`go.mod`、`pyproject.toml`、`requirements.txt` 等
2. **按技术栈生成配置文件**：

   **Node.js / 前端项目**：
   - 生成 `eslint.config.mjs`（flat config，ESLint 9+）
   - 生成 `.prettierrc`（格式化配置）
   - 若有 TypeScript，确保 `tsconfig.json` 含 `strict: true`
   - 在 `package.json` 的 `scripts` 中追加：
     ```json
     "lint": "eslint .",
     "lint:fix": "eslint --fix . && prettier --write .",
     "type-check": "tsc --noEmit"
     ```

   **Java/Maven 项目**：
   - 在 `pom.xml` 中追加 Checkstyle + Spotless plugin（若不存在）
   - 生成 `checkstyle.xml`（基于 Google Java Style 或项目已有规范）

   **Go 项目**：
   - 生成 `.golangci.yml`（含常用 linter 配置）

   **Python 项目**：
   - 生成 `ruff.toml`（推荐 Ruff 作为默认 linter）
   - 配置 line-length、target-version 等

3. **检查 Git Hooks**：
   - 若未配置 pre-commit hook，建议配置：
     ```
     💡 建议配置 Git pre-commit hook 自动运行 lint：
        npx husky init          # Node.js 项目
        pre-commit install      # Python 项目（需 pip install pre-commit）
     ```

4. **输出配置报告**：

```
✅ Lint 工具链配置完成

已生成/更新的配置文件：
  📄 eslint.config.mjs
  📄 .prettierrc
  📄 package.json (scripts)

已检测的技术栈：
  - TypeScript 5.x + React 18
  - Tailwind CSS 3.x

建议下一步：
  /pdlc-lint check     ← 运行首次全量检查
  /pdlc-lint fix       ← 自动修复可修复的问题
  /pdlc-ship           ← 将 lint 加入 CI 流水线（发布时自动配置）
```

---

## 与其他 PDLC 命令的联动

- **`/pdlc-feature`**：可在阶段五（自查评审）中自动触发 `lint check` 验证代码质量
- **`/pdlc-review`**：评审时参考 lint 报告
- **`/pdlc-ship`**：在发布流水线的 CI/CD 配置中增加 lint 阶段

---

## 要求

<!-- @include templates/prompts/output-language.md -->
- 不修改 lint 工具本身的配置（除 setup 子命令外）
- fix 子命令只修复工具标记为"可自动修复"的问题，不做额外改动
- 遇到工具未安装的情况，优先使用 `npx` / `mvn` 等包管理器临时调用

检查目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 代码质量检查 完成
📦 产出：（lint 报告输出到控制台）
👉 下一步：（本次流程结束，无后续）
```
