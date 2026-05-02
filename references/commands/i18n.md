---
name: pdlc-i18n
description: 国际化（i18n）
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

<!-- @include templates/prompts/iron-law.md -->

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

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 国际化资源文件 完成
📦 产出：src/locales/<语言>.json
👉 下一步：（本次流程结束，无后续）
```
