---
name: pdlc-arch
description: 架构分析
argument-hint: <项目 | 模块范围>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: design
produces:
  - docs/02_design/arch/**
requires: []
next_step: null
terminal_state: null
---

# 架构分析

<!-- @include templates/prompts/iron-law.md -->

对当前项目架构进行全面分析，输出架构评估报告。

## 分析维度

### 1. 服务拆分合理性
- 各微服务的职责边界是否清晰
- 是否存在循环依赖
- 服务粒度是否合适（过大/过小）
- 数据归属是否明确

### 2. 通信机制
- 服务间通信方式（同步REST/gRPC、异步消息队列）
- 是否存在分布式事务问题
- 接口版本管理策略
- 错误传播和容错机制

### 3. 数据架构
- 数据库拆分策略（每服务独立数据库 vs 共享）
- 数据一致性方案
- 缓存策略
- 数据备份与恢复

### 4. 可观测性
- 日志规范（结构化日志、链路追踪ID）
- 监控指标（RED指标：Rate/Errors/Duration）
- 告警策略
- 分布式追踪

### 5. 可扩展性
- 水平扩展能力
- 负载均衡策略
- 容量规划

## 工作流程
1. 扫描 `backend/` 和 `frontend/` 下的所有服务和应用
2. 阅读 `docs/02_design/architecture/` 下的架构设计文档
3. 分析代码中的依赖关系和调用链路
4. **【必须创建文件】** 生成架构分析报告到 `docs/07_reviews/design/`

> ⚠️ **必须创建文件，不可仅在对话中输出。**

## 输出格式

文件名: `YYYYMMDD-arch-analysis.md`

**文档顶部包含 PDLC 追溯头**：
```
<!-- PDLC-TRACE -->
<!-- 功能名称: 架构分析 -->
<!-- 阶段: 架构评估 -->
<!-- 创建时间: <ISO 8601> -->
```

**报告内容**：
- 架构全景图（文本描述）
- 各维度评分（1-5分）
- 问题清单与改进建议

**创建后验证**：确认文件已存在于 `docs/07_reviews/design/` 目录

## 要求
- 所有内容使用中文
- 评价要客观，给出依据
- 建议要可操作，标注优先级

$ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 架构分析报告 完成
📦 产出：docs/02_design/arch/YYYYMMDD-arch-analysis.md
👉 下一步：（本次流程结束，无后续）
```
