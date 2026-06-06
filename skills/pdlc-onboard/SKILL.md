---
name: pdlc-onboard
description: 新人引导 / 自动化生成用户手册
argument-hint: [项目目录 | 模块]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: lifecycle
produces:
  - docs/ONBOARDING.md
requires: []
next_step: null
terminal_state: null
---

# 新人引导

<!-- @include templates/prompts/iron-law.md -->

为新加入项目的开发者生成引导文档，帮助快速上手。

## 工作流程
1. 扫描整个项目结构，了解当前状态
2. 运行 `make status` 查看服务和应用列表
3. 阅读 `CLAUDE.md`、`README.md` 获取项目概述
4. 汇总输出新人引导信息

## 输出内容

### 1. 项目总览
- 项目名称和用途
- 技术栈概述
- 微服务列表及各自职责
- 前端应用列表及各自职责

### 2. 环境搭建
- 必要的开发工具和版本要求
- 本地开发环境搭建步骤
- 配置文件说明

### 3. 开发规范
- 引用 `docs/00_standards/coding-standards.md`（未命中 → 提示 `consider /pdlc-standard add coding/<topic>`）
- Git 分支策略和提交规范
- PDLC 工作流说明

### 4. 快速上手
- 如何运行项目
- 如何运行测试
- 如何创建新功能（指向 `/new-feature` 命令）
- 常用 Make 命令一览

### 5. 关键文档索引
- 列出 `docs/` 下所有重要文档的路径和摘要

### 6. 常见问题
- 构建失败怎么办
- 测试报错怎么排查
- 如何联调

## 要求
<!-- @include templates/prompts/output-language.md -->
- 输出到 `docs/03_development/onboard-guide.md`
- 步骤具体可操作
- 标注哪些步骤可以跳过（视角色而定）

$ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 新人引导文档 完成
📦 产出：docs/ONBOARDING.md
👉 下一步：（本次流程结束，无后续）
```
