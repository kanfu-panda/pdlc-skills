---
name: pdlc-refactor
description: 代码重构（保持外部行为不变，改善内部结构）
argument-hint: <重构目标 | 文件路径>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: refactor
produces: []
requires: []
next_step: pdlc-review
terminal_state: refactor_done
---

# 代码重构

<!-- @include templates/prompts/iron-law.md -->

对指定服务或模块进行安全重构，保证行为不变。

## 工作流程
1. **确认测试覆盖**: 先检查现有测试是否充分，不充分则先补测试
2. **阅读设计文档**: 阅读 `docs/02_design/` 对应子目录下的相关设计文档
3. **识别坏味道**: 分析代码中的坏味道（Code Smell）
4. **制定重构计划**: 列出重构项，按风险排序
5. **逐步重构**: 每次只做一个小的重构，确保测试通过
6. **运行完整测试**: 确认没有破坏现有功能

## 常见重构场景
- **提取方法/类**: 过长的方法、过大的类
- **消除重复**: DRY 原则，提取公共逻辑
- **简化条件**: 复杂的 if-else 链、嵌套条件
- **改善命名**: 不清晰的变量名、方法名
- **解耦依赖**: 降低模块间耦合度
- **统一风格**: 对齐项目编码规范

## 要求
<!-- @include templates/prompts/output-language.md -->
- 重构提交信息格式: `refactor: <简要描述>`
- 严禁在重构中混入新功能
- 每个重构步骤都要保证测试通过
- 更新 CHANGELOG.md

重构目标: $ARGUMENTS

<!-- @include templates/prompts/state-update.md -->
<!-- @include templates/prompts/handoff.md -->
