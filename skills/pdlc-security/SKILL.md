---
name: pdlc-security
description: 安全审计
argument-hint: <模块 | 服务名>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: quality
produces:
  - docs/04_testing/security/<feature-id>-audit.md
requires: []
next_step: null
terminal_state: null
---

# 安全审计

<!-- @include templates/prompts/iron-law.md -->

对指定服务或应用进行安全审计，检查常见安全漏洞。

## 审计范围
1. **OWASP Top 10 检查**
   - SQL 注入
   - XSS（跨站脚本）
   - CSRF（跨站请求伪造）
   - 不安全的直接对象引用
   - 安全配置错误
   - 敏感数据泄露
   - 缺失的访问控制
   - 不安全的反序列化
   - 使用含已知漏洞的组件
   - 日志记录和监控不足

2. **认证与授权**
   - 密码存储方式（是否加盐哈希）
   - Token 生成与验证
   - 接口权限控制
   - 会话管理

3. **数据安全**
   - 敏感信息是否加密存储
   - 环境变量中是否有硬编码密钥
   - 日志中是否打印敏感数据
   - API 响应中是否泄露内部信息

4. **依赖安全**
   - 检查依赖包是否有已知漏洞
   - 检查是否使用了过时的库版本

## 输出格式

> ⚠️ **必须创建文件，不可仅在对话中输出。**

**【必须创建文件】** 在 `docs/07_reviews/code/` 下创建安全审计报告：
- 文件名: `YYYYMMDD-<服务名>-security-audit.md`
- **文档顶部包含 PDLC 追溯头**：
  ```
  <!-- PDLC-TRACE -->
  <!-- 功能名称: <服务名> -->
  <!-- 阶段: 安全审计 -->
  <!-- 创建时间: <ISO 8601> -->
  ```
- 按严重程度分级：紧急 / 高危 / 中危 / 低危 / 信息
- 每个问题包含：位置、描述、风险、修复建议、参考链接
- **创建后验证**：确认文件已存在于 `docs/07_reviews/code/` 目录
- 在对话中输出报告摘要，但**完整报告必须在文件中**

## 要求
<!-- @include templates/prompts/output-language.md -->
- 给出具体的代码位置和修复代码示例
- 关键漏洞标注修复优先级

审计目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 安全审计报告 完成
📦 产出：docs/04_testing/security/<feature-id>-audit.md
👉 下一步：（本次流程结束，无后续）
```
