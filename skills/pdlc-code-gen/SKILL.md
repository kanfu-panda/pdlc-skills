---
name: pdlc-code-gen
description: 代码脚手架生成
argument-hint: <模板类型 | 目标目录>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces: []
requires: []
next_step: null
terminal_state: null
---

# 代码脚手架生成

<!-- @include templates/prompts/iron-law.md -->

根据设计文档快速生成模块代码脚手架（骨架代码）。

## 工作流程
1. **阅读设计文档**: 阅读 `docs/02_design/api/` 和 `docs/02_design/database/` 下的设计文档
2. **确定目标服务**: 确认代码生成到哪个服务或应用
3. **生成代码骨架**: 按技术栈生成对应的代码文件

## 后端生成内容（按分层架构）

### Java/Spring Boot
- Controller（控制器层）: 路由、参数校验、响应封装
- Service（服务层）: 业务逻辑接口和实现
- Repository（数据层）: 数据访问接口
- DTO/VO/Entity: 数据传输对象、视图对象、实体类
- 单元测试骨架

### Go
- Handler（处理器层）: HTTP 路由处理
- Service（服务层）: 业务逻辑
- Repository（仓储层）: 数据访问
- Model（模型层）: 数据结构定义
- 单元测试骨架

### Python/FastAPI
- Router（路由层）: API 路由定义
- Service（服务层）: 业务逻辑
- Repository（仓储层）: 数据访问
- Schema/Model: Pydantic 模型、ORM 模型
- 单元测试骨架

### Node.js
- Controller（控制器层）: 路由处理
- Service（服务层）: 业务逻辑
- Model（模型层）: 数据模型
- Middleware（中间件）: 通用中间件
- 单元测试骨架

## 前端生成内容
- 页面组件骨架
- API 请求服务层
- 类型定义（TypeScript）
- 状态管理模块
- 单元测试骨架

## 要求
<!-- @include templates/prompts/output-language.md -->
- 生成的代码要遵循 `docs/00_standards/coding-standards.md` 规范（未命中 → 提示 `consider /pdlc-standard add coding/<topic>`）
- 方法体用 `// TODO: 待实现` 占位
- 测试用例用 `// TODO: 补充测试逻辑` 占位
- 生成后提示用户先运行 `/tdd` 补充测试

生成目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 代码脚手架 完成
📦 产出：（生成到目标服务/应用目录）
👉 下一步：（本次流程结束，无后续）
```
