---
name: pdlc-api-mock
description: API Mock 数据生成
argument-hint: <接口路径 | OpenAPI 文件>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces: []
requires: []
next_step: null
terminal_state: null
---

# API Mock 数据生成

<!-- @include templates/prompts/iron-law.md -->

根据 API 设计文档生成 Mock 数据和 Mock 服务配置，供前端联调使用。

## 工作流程
1. **阅读 API 设计**: 阅读 `docs/02_design/api/` 下的 API 设计文档
2. **生成 Mock 数据**: 为每个接口生成符合数据模型的 Mock 响应
3. **生成 Mock 配置**: 根据技术栈生成对应的 Mock 服务文件
4. **输出到指定位置**: 前端应用的 `mock/` 或 `src/services/__mocks__/` 目录

## Mock 数据要求
- 数据要贴近真实场景，不要用 "test1"、"aaa" 之类的无意义数据
- 列表接口至少生成 5-10 条数据
- 覆盖各种状态：正常数据、边界数据、空数据
- 包含分页信息
- 错误响应也要生成 Mock

## 输出格式
```json
{
  "code": 0,
  "message": "成功",
  "data": { ... }
}
```

## 要求
- Mock 数据中的中文内容要有实际含义
- 时间字段使用合理的时间范围
- ID 字段使用合理的格式（UUID/数字）
- 生成完成后告知前端同学如何启用 Mock 服务

目标接口: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ API Mock 数据 完成
📦 产出：（生成到前端应用 mock/ 目录）
👉 下一步：（本次流程结束，无后续）
```
