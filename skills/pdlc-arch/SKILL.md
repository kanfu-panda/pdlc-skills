---
name: pdlc-arch
description: 架构分析（生成/更新 docs/ARCHITECTURE.md 系统架构总览 · surface 型）
argument-hint: <项目 | 模块范围>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: design
artifact_type: surface
produces:
  - docs/ARCHITECTURE.md
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

> **架构总览是 surface 型产物**：`docs/ARCHITECTURE.md` 描述"系统当前长什么样"，**就地覆盖更新**，不按日期累积多份文件。演进历史靠 `git log docs/ARCHITECTURE.md` 追溯。这与 per-feature 的 `docs/02_design/architecture/F-xxx-arch.md`（ledger 型，记录"为某个 feature 为什么改架构"）分工互补。

1. 扫描 `backend/` 和 `frontend/` 下的所有服务和应用
2. 阅读 `docs/02_design/architecture/` 下的 per-feature 架构 ledger（若有）
3. 分析代码中的依赖关系和调用链路
4. **遗留检测**：若发现旧版按日期命名的 `*-arch-analysis.md`（散落在 `docs/02_design/architecture/` 或旧 review 目录，即 v1.0 的 v1..v5 累积模式），提示并移到 `docs/.archive/architecture/`，以最新一份作为 `ARCHITECTURE.md` 的起点
5. **【必须创建/更新文件】** 就地生成/覆盖 `docs/ARCHITECTURE.md`（参考 `templates/architecture-overview-template.md`）

> ⚠️ **必须写入磁盘，不可仅在对话中输出。**

## 输出格式

文件路径：`docs/ARCHITECTURE.md`（固定，就地覆盖）

**文档顶部包含 PDLC 追溯头 + surface 标记**：
```
<!-- artifact_type: surface -->
<!-- PDLC-TRACE -->
<!-- 功能名称: 架构总览 -->
<!-- 阶段: design -->
<!-- 创建时间: <执行时的实际 ISO 8601 时间戳> -->
```

**报告内容**：
- 架构全景图（文本描述 / mermaid）
- 服务拆分 / 通信 / 数据 / 可观测性 / 可扩展性 各维度评分（1-5）
- 问题清单与改进建议

**创建后验证**：确认 `docs/ARCHITECTURE.md` 已存在且为本次内容

## 要求
<!-- @include templates/prompts/output-language.md -->
- 评价要客观，给出依据
- 建议要可操作，标注优先级
- surface 铁律：不创建带日期/版本号的架构文件，永远就地覆盖 `ARCHITECTURE.md`

$ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 架构总览已更新：docs/ARCHITECTURE.md
📦 surface 型就地覆盖（历史见 git log docs/ARCHITECTURE.md）
👉 下一步：（本次流程结束，无后续）
```
