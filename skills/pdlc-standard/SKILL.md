---
name: pdlc-standard
description: 管理 00_standards 规范型 surface 产物（add/edit/archive/index）
argument-hint: <add|edit|archive|index> [args]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 3
stage: engineering
artifact_type: surface
produces:
  - docs/00_standards/**
requires: []
next_step: null
terminal_state: null
---

# 规范文档管理（surface 型）

<!-- @include templates/prompts/iron-law.md -->

管理 `docs/00_standards/` 下的团队规范（编码约定 / API 约定 / 命名规则等）。这类产物是 **surface 型**——描述"当前规范是什么"的状态快照，**就地编辑**而非 ledger 累积。

## ⛔ surface 铁律（不可违反）

1. **不允许版本化文件名**：禁止 `coding-style-v2.md` / `coding-style-2026-Q1.md` 这类 ledger 绕路。一个主题永远一个文件，就地改。
2. **就地编辑 + `_changelog.md`**：每次修改在同目录 `_changelog.md` 追加一条（日期 / 命令 / 变更摘要）。
3. **git log 是真实审计链**：演进历史靠 `git log <file>` 看，不靠多份文件。
4. **归档不删除**：废弃的规范用 `archive` 子命令移到 `docs/00_standards/.archive/`，留 stub 指向新位置。

## 段一：执行子命令

从 `$ARGUMENTS` 解析：

### `add <category>/<name>`
新建规范。`category` 如 `coding` / `api` / `naming`。
1. 在 `docs/00_standards/<category>/<name>.md` 创建（**确认不存在同名 v2 变体**）
2. 文件顶部加 `<!-- artifact_type: surface -->` 标记
3. 同目录 `_changelog.md` 追加创建记录
4. 更新 `docs/00_standards/_index.md`

### `edit <path> <change>`
就地编辑已有规范。改完在 `_changelog.md` 追加变更摘要。**禁止**另存为新版本文件。

### `archive <path>`
移到 `docs/00_standards/.archive/`，原位置留 stub（一行指向新位置 + 废弃原因）。

### `index`
扫描 `docs/00_standards/**`，重新生成 `_index.md`（按 category 分组列出所有规范 + 一句话摘要）。

## 段二：自检（强制）

<!-- @include templates/prompts/self-audit.md -->

### 规范管理自检清单

- [ ] 无版本化文件名泄漏（`*-v[0-9]` / `*-20[0-9][0-9]*` 模式不存在）
- [ ] 本次涉及的 `_changelog.md` 已追加记录
- [ ] 新建/修改的规范文件含 `artifact_type: surface` 头标记
- [ ] `_index.md` 与实际文件一致（无遗漏 / 无悬空条目）

## 段三：修复（单次，不递归）

<!-- @include templates/prompts/loop-prevention.md -->

- 可自动修复（漏更 `_changelog.md` / `_index.md` 不一致）→ 直接补
- 发现版本化文件名 → 提示用户合并到主文件（不自动合并，避免丢内容）

## 段四：交接

> **状态机豁免**：本命令非 feature-scoped，不更新 `<feature-id>.json`。同 `/pdlc-changelog`。

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ 规范操作完成：<子命令> <参数>
📦 已更新：docs/00_standards/<...> + _changelog.md + _index.md
👉 下一步：本次流程结束
```

---

**规范操作**: $ARGUMENTS
