---
name: pdlc-changelog
description: 更新变更日志
argument-hint: [版本号]
allowed-tools: Read, Write, Edit, Bash
layer: 3
stage: engineering
produces:
  - CHANGELOG.md
requires: []
next_step: null
terminal_state: null
---

# 更新变更日志

<!-- @include templates/prompts/iron-law.md -->

根据最近的 git 提交记录，更新指定服务或应用的 CHANGELOG.md。

## 工作流程
1. 运行 `git log` 查看最近的提交记录
2. 按约定式提交分类：feat / fix / docs / chore / refactor / test
3. 更新对应服务/应用的 `CHANGELOG.md`
4. 遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 格式

## 分类规则
- **新增（Added）**: feat 类型的提交
- **修复（Fixed）**: fix 类型的提交
- **变更（Changed）**: refactor 类型的提交
- **移除（Removed）**: 删除功能相关的提交
- **文档（Docs）**: docs 类型的提交

## 要求
- 所有内容使用中文
- 每条记录简洁明了，描述"做了什么"和"为什么"
- 如果涉及破坏性变更，需特别标注

目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 变更日志 完成
📦 产出：CHANGELOG.md
👉 下一步：（本次流程结束，无后续）
```
