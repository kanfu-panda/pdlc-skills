---
name: pdlc-bootstrap
description: AI 对话式项目初始化
argument-hint: [项目目录]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: lifecycle
produces: []
requires: []
next_step: null
terminal_state: null
---

# AI 对话式项目初始化

<!-- @include templates/prompts/iron-law.md -->

接收一句话项目描述，自动分析需求、选择技术栈、生成完整的项目骨架（代码目录 + 基础配置 + PDLC 文档草稿）。

## 前置检查

1. 检查是否有未提交的变更（`git status`），如果有，提示用户先 commit 或 stash，然后继续
2. 检查 PDLC 目录结构是否存在（`docs/00_standards/` 等），如不存在则先运行 `make init`

## 功能ID分配

1. 获取当前日期与时分秒：`date +%Y%m%d`、`date +%H%M%S`
2. 生成功能ID：`F<YYYYMMDD>-<HHMMSS>`（示例形如 `F20260717-122801`；用执行时的真实值）
3. **本地防撞**：若该 ID 已被占用（`docs/` 或 `docs/.pdlc-state/` 下已有同名前缀），重新读取 `date +%H%M%S` 重取（生成本身有耗时、通常已跨秒；若仍同秒则 `sleep 1` 后再读一次，**不手算时分秒**，天然处理跨天边界）
4. 从用户描述中提取项目名关键词（英文小写+连字符）

> 用时分秒而非当日序号，是为了多人 / 多 AI 并行时零协调也不撞号、合并零冲突。旧 `F<日期>-<NN>` ID 仍可解析。

## 执行流程

### 第一步：分析项目需求

根据用户的一句话描述，自动分析并生成**项目计划摘要**：

1. **服务拆分**：确定后端服务列表及分类
   - services/ — 独立微服务（对外提供 API）
   - modules/ — 内部公共模块（被其他服务依赖）
   - clients/ — 客户端 SDK
2. **应用拆分**：确定前端应用列表及分类
   - web/ — PC Web 应用
   - h5/ — H5 移动端应用
   - miniprogram/ — 微信小程序
   - app/ — 原生/混合 App
3. **技术栈选择**：为每个服务/应用推荐技术栈
   - 后端：Java/Spring Boot、Go、Python/FastAPI、Node/NestJS
   - 前端：React/Next.js、Vue/Nuxt、微信小程序原生
4. **目录结构预览**：输出完整的目录树预览

输出格式：
```
## 项目计划摘要

### 后端服务
| 服务名 | 分类 | 技术栈 | 说明 |
|--------|------|--------|------|
| user-service | services | Java/Spring Boot | 用户管理 |
| ... | ... | ... | ... |

### 前端应用
| 应用名 | 分类 | 技术栈 | 说明 |
|--------|------|--------|------|
| web-admin | web | React/Next.js | 管理后台 |
| ... | ... | ... | ... |

### 目录结构预览
（输出目录树）
```

**如果描述太模糊**，主动追问 1-2 个关键问题（如"后端偏好 Java 还是 Go？"、"需要管理后台还是面向用户的前台？"），但不要超过 2 轮追问。

### 第二步：用户确认

将计划摘要展示给用户，等待确认。用户可以调整服务列表、技术栈等。
确认后一次性生成所有内容，不再逐步确认。

### 第三步：生成项目骨架

确认后，按以下顺序生成：

#### 3.1 后端服务骨架

对每个后端服务：
1. 创建目录结构 `backend/<分类>/<服务名>/`
2. 根据技术栈生成项目结构：
   - **Java/Spring Boot**：pom.xml、application.yml、DDD 分层（controller/service/repository/model/config）、Dockerfile
   - **Go**：go.mod、cmd/main.go、internal/（handler/service/repository/model）、Dockerfile
   - **Python/FastAPI**：pyproject.toml、app/（main.py/routers/services/models）、Dockerfile
   - **Node/NestJS**：package.json、src/（main.ts/modules/）、Dockerfile
3. 生成 README.md 和 CHANGELOG.md
4. 在 `backend/<分类>/<服务名>/docs/` 下创建 api-design.md 骨架

#### 3.2 前端应用骨架

对每个前端应用：
1. 创建目录结构 `frontend/<分类>/<应用名>/`
2. 根据技术栈生成项目结构：
   - **React/Next.js**：package.json、next.config.js、src/（pages/components/lib/styles）、public/
   - **Vue/Nuxt**：package.json、nuxt.config.ts、src/（pages/components/composables/assets）
   - **微信小程序**：project.config.json、app.json、pages/、components/、utils/
3. 生成 README.md 和 CHANGELOG.md

#### 3.3 PDLC 文档草稿

1. **PRD 草稿**：在 `docs/01_requirements/prd/` 下创建 `<功能ID>-<项目名>-prd.md`
   - 参考 `templates/prd-template.md` 模板格式
   - **文档顶部包含 PDLC 追溯头**（功能ID、阶段: 需求、前置文档: 无）
   - 包含：项目背景、目标用户、功能清单（基于服务拆分）、非功能需求、验收标准
2. **架构设计草稿（per-feature ledger）**：在 `docs/02_design/architecture/` 下创建 `<功能ID>-<项目名>-arch.md`
   - 参考 `templates/arch-design-template.md` 模板格式
   - **文档顶部包含 PDLC 追溯头**（功能ID、阶段: 设计、前置文档指向 PRD）
   - 包含：系统架构图（文本描述）、服务间通信方式、技术栈决策
   - ℹ️ 这是 **ledger 型**（记录"为这个 feature 为什么这样设计"）。系统级**架构总览**是 surface 型，由 `/pdlc-arch` 维护 `docs/ARCHITECTURE.md`（per-feature ledger 与系统级 surface 分工互补）。
   - ⚠️ **遗留检测**：若发现旧版 `*-arch-analysis.md`（v1.0 的 v1..v5 累积模式），提示用户运行 `/pdlc-arch` 整合到 `docs/ARCHITECTURE.md` 并归档旧文件。
3. **API 设计模板**：在 `docs/02_design/api/` 下为每个后端服务创建 `<功能ID>-<服务名>-api.md`
   - 参考 `templates/api-design-template.md` 模板格式
   - **文档顶部包含 PDLC 追溯头**
   - 包含：接口列表骨架、通用请求/响应规范
4. **数据库设计模板**：在 `docs/02_design/database/` 下创建 `<功能ID>-<项目名>-db.md`
   - 参考 `templates/db-design-template.md` 模板格式
   - **文档顶部包含 PDLC 追溯头**
   - 包含：初始表结构骨架（基于服务拆分推断）
5. **surface 入口 stub（向后兼容）**：在 `docs/` 根创建两个空 stub，提供 canonical surface 位置，内容留待对应技能填充
   - `docs/ARCHITECTURE.md`：参考 `templates/architecture-overview-template.md`，仅写 surface 标记 + 追溯头 + 占位说明（"运行 `/pdlc-arch` 生成完整架构总览"）
   - `docs/GLOSSARY.md`：参考 `templates/glossary-template.md`，仅写 surface 标记 + 占位说明（surface 型术语表，就地编辑维护，`git log` 审计）
   - ℹ️ 仅当文件不存在时创建，**不覆盖**已有内容

### 第四步：输出完成报告

```
## Bootstrap 完成报告（<功能ID>）

### 生成内容汇总
| 类型 | 路径 | 说明 |
|------|------|------|
| 后端服务 | backend/services/xxx | ... |
| 前端应用 | frontend/web/xxx | ... |
| PRD 草稿 | docs/01_requirements/prd/<功能ID>-... | ... |
| 架构设计 | docs/02_design/architecture/<功能ID>-... | ... |
| API 设计 | docs/02_design/api/<功能ID>-... | ... |
| 数据库设计 | docs/02_design/database/<功能ID>-... | ... |

### 下一步操作
- 运行 `/pdlc-prd <需求描述>` 完善产品需求文档
- 运行 `/pdlc-design <设计目标>` 细化技术设计
- 运行 `/pdlc-tdd <功能描述>` 开始测试驱动开发
- 运行 `git diff` 预览所有变更
- 运行 `git checkout .` 可一键回滚所有生成内容
```

## 要求

<!-- @include templates/prompts/output-language.md -->
- 服务名/应用名使用小写英文 + 连字符（如 user-service、web-admin）
- 日期使用执行当天的实际日期，格式 YYYYMMDD
- 生成的代码只包含骨架结构和基础配置，不包含业务逻辑实现
- 每个服务/应用生成独立，单个失败不影响其他
- 不过度设计，骨架够用即可，后续通过 /命令 逐步完善

项目描述: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 项目骨架初始化 完成
📦 产出：backend/ + frontend/ + docs/ 骨架
👉 下一步：（本次流程结束，无后续）
```
