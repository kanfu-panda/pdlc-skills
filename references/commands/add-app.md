---
name: pdlc-add-app
description: 添加新的前端应用
argument-hint: <应用名>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces:
  - frontend/*/**
requires: []
next_step: null
terminal_state: null
---

# 添加新的前端应用

<!-- @include templates/prompts/iron-law.md -->

在项目中添加一个新的前端应用，并生成完整的目录结构和初始文档。

## 工作流程
1. 运行 `make new-app` 或直接在 `frontend/web/` 下创建应用目录（或 `frontend/h5/`、`frontend/miniprogram/`、`frontend/app/`）
2. 根据技术栈生成标准目录结构
3. 创建应用的 README.md、CHANGELOG.md、package.json
4. 在 `frontend/<分类>/<应用名>/docs/` 下创建初始文档
5. 更新项目 CLAUDE.md 中的应用列表（如需要）

## 支持的技术栈
- react: React + TypeScript + Vite
- vue: Vue 3 + TypeScript + Vite
- nextjs: Next.js（React SSR）
- miniprogram: 微信小程序

## 要求
- 所有文档和注释使用中文
- 应用名使用小写英文 + 连字符（如 web-admin）
- 创建完成后提示用户下一步编写 UI 设计文档

$ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 新前端应用 完成
📦 产出：frontend/<分类>/<应用名>/
👉 下一步：（本次流程结束，无后续）
```
