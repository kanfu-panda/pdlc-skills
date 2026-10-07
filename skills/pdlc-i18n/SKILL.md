---
name: pdlc-i18n
description: 国际化——抽取硬编码文案为 key、生成多语言资源文件并替换引用
argument-hint: <目标语言 | 模块名>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
produces: []
requires: []
next_step: null
terminal_state: null
---

# 国际化（i18n）

<!-- @include templates/prompts/iron-law-tool.md（已内联于下方，无需另读） -->
⛔ **IRON LAW · 不可违反的硬门禁（工具型命令）**

本命令不是主链路上的阶段：**不追加 `history`，不改 `current_stage` / `next_step` / `last_phase_result`**，也不为此分配功能ID。以下规则不可协商：

1. **文件必须落盘**：正文要求创建的文件必须作为实际文件写入磁盘，不可仅在对话中输出（只要求在对话里输出的，照正文办）。
2. **自检必须执行**：产出后按本命令的自检项逐项核对，不得以"已经很好了"为由跳过。
3. **防循环**：修复只做一次，不递归。修不了的问题记进报告，继续往下走。

**违反任一条 = 立即中止当前命令，输出违规详情，等待人工介入。**
<!-- @include-end templates/prompts/iron-law-tool.md -->

为指定的前端应用或后端服务添加国际化支持。

## 工作流程
1. **扫描硬编码文本**: 查找代码中所有硬编码的中文字符串
2. **提取文本资源**: 生成多语言资源文件
3. **替换硬编码**: 用 i18n 函数调用替换原有的硬编码文本
4. **生成翻译清单**: 输出待翻译的文本列表

## 前端（React/Vue）
- 资源文件位置: `src/locales/zh-CN.json`、`src/locales/en-US.json`
- 使用 `react-i18next` 或 `vue-i18n`
- Key 命名规范: `模块.页面.组件.描述`，如 `user.login.form.username`

## 后端（Java/Go/Python/Node）
- 错误提示信息国际化
- API 响应消息国际化
- 根据请求头 `Accept-Language` 返回对应语言

## 资源文件格式
```json
{
  "common": {
    "confirm": "确认",
    "cancel": "取消",
    "save": "保存",
    "delete": "删除"
  },
  "user": {
    "login": {
      "title": "用户登录",
      "username": "用户名",
      "password": "密码"
    }
  }
}
```

## 要求
- 默认语言为中文（zh-CN）
- Key 使用英文，值使用对应语言
- 先生成中文版本，英文版本标记 `// TODO: 待翻译`
- 日期、数字、货币使用 Intl API 格式化

目标: $ARGUMENTS

<!-- @include templates/prompts/handoff.md（已内联于下方，无需另读） -->
## 段四：交接（Handoff）

命令完成后必须输出以下格式的最终消息：

```
✅ <阶段名> 完成：<主要产出物路径>
📊 自检：<通过数>/<总数> 通过（若有未通过，附要点）
📦 状态快照：docs/.pdlc-state/<feature-id>.json
👉 下一步：/pdlc-<next_step>
   （如果有分叉）或 /pdlc-<alt>（条件：<选择依据>）
```

**规则：**
- 主流程命令（写状态机的命令；下一跳见正文里「本命令的状态机取值」）必须显式输出"下一步"，不可省略
- 工具型命令（Layer 3）可以没有 `next_step`，此时输出 `👉 下一步：（本次流程结束，无后续）`
- 分叉场景必须说明**选择条件**，例如"若需补充测试用例 → `/pdlc-tdd`；若测试已齐 → `/pdlc-review`"
<!-- @include-end templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 国际化资源文件 完成
📦 产出：src/locales/<语言>.json
👉 下一步：（本次流程结束，无后续）
```
