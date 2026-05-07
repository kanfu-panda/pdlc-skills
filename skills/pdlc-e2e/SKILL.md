---
name: pdlc-e2e
description: 端到端测试（生成或执行 E2E 用例）
argument-hint: <功能ID | 业务流程描述>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: e2e
produces:
  - e2e/**/*.spec.ts
requires: []
next_step: pdlc-review
terminal_state: e2e_done
---

# 端到端测试

<!-- @include templates/prompts/iron-law.md -->

编写端到端（E2E）测试用例，验证完整的用户操作流程。

## 工作流程
1. **阅读需求文档**: 阅读 `docs/01_requirements/user-stories/` 下的用户故事和验收标准
2. **阅读 UI 设计**: 阅读 `docs/02_design/ui-ux/` 下的 UI 设计文档
3. **梳理测试场景**: 按用户旅程梳理核心操作路径
4. **编写测试计划**: 在 `docs/04_testing/e2e-tests/` 下补充 E2E 测试用例
5. **编写测试代码**: 使用项目对应的 E2E 框架编写自动化测试
6. **运行验证**: 确保测试可通过

## 测试场景设计
- **核心路径（P0）**: 必须通过，如登录→主流程→结果验证
- **分支路径（P1）**: 常见的备选操作路径
- **异常路径（P2）**: 网络错误、超时、权限不足等异常场景
- **边界场景（P3）**: 空数据、超长输入、并发操作

## 测试框架（根据前端技术栈）
- React/Vue/Next.js: Playwright 或 Cypress
- 微信小程序: miniprogram-automator
- API 层: 直接用 HTTP 请求库

## 要求
<!-- @include templates/prompts/output-language.md -->
- 测试用例命名格式: `应该_当<条件>时_<预期行为>`
- 测试数据独立，不依赖其他测试的执行结果
- 每个测试结束后清理数据

测试目标: $ARGUMENTS

<!-- @include templates/prompts/state-update.md -->
<!-- @include templates/prompts/handoff.md -->
