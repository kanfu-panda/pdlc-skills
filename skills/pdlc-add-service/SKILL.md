---
name: pdlc-add-service
description: 添加新的微服务
argument-hint: <服务名>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces:
  - backend/services/<service-name>/**
requires: []
next_step: null
terminal_state: null
---

# 添加新的微服务

<!-- @include templates/prompts/iron-law.md -->

在项目中添加一个新的后端微服务，并生成完整的目录结构和初始文档。

## 工作流程
1. 运行 `make new-service` 或直接在 `backend/services/` 下创建服务目录
2. 根据技术栈生成标准目录结构
3. 创建服务的 README.md、CHANGELOG.md
4. 在 `backend/services/<服务名>/docs/` 下创建 api-design.md 初始文档
5. 更新项目 CLAUDE.md 中的服务列表（如需要）

## 支持的技术栈
- java/spring: Maven + Spring Boot 标准结构
- go: Go 标准项目布局（cmd/internal/pkg）
- python: FastAPI/Flask 项目结构
- node: Express/NestJS 项目结构

## 要求
<!-- @include templates/prompts/output-language.md -->
- 服务名使用小写英文 + 连字符（如 user-service）
- 创建完成后提示用户下一步编写 API 设计文档

$ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 新微服务 完成
📦 产出：backend/services/<service-name>/
👉 下一步：（本次流程结束，无后续）
```
