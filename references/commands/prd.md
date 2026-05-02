---
name: pdlc-prd
description: 创建 PRD 文档（自动化生成 + 自检 + handoff）
argument-hint: <功能描述 | 已有需求文档路径>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
layer: 2
stage: requirements
produces:
  - docs/01_requirements/prd/<feature-id>-<feature-name>-prd.md
requires: []
next_step: pdlc-design
terminal_state: prd_done
---

# 创建 PRD 文档

根据用户提供的需求描述或已有需求文档，在 `docs/01_requirements/prd/` 目录下创建一份完整的 PRD（产品需求文档）。

<!-- @include templates/prompts/iron-law.md -->

## 段一：生成 PRD

### 1.1 输入解析（必须执行）

从 `$ARGUMENTS` 中判断输入类型：

1. **检测是否为文件路径**：匹配以下模式之一即视为文件输入：
   - 以 `/`、`./`、`../`、`~` 开头
   - 以 `.md`、`.txt`、`.docx`、`.pdf`、`.doc` 结尾
   - 包含 `docs/` 或 `requirements/` 路径片段
   - 是一个实际存在的文件路径

2. **文件输入处理**：
   - 读取文件内容（支持 Markdown、纯文本、PDF）
   - 若为飞书文档链接，通过飞书 API 获取
   - 从内容提取：功能名称、范围、用户故事、验收标准
   - **保留原文档核心内容**，仅补充和结构化，不重写
   - 在 PRD 中添加：`<!-- 来源文档: <原始路径> -->`

3. **文本输入处理**：按描述推断功能需求

> **核心原则**：文件输入是「基于已有内容结构化」，文本输入是「从零生成」。

### 1.2 功能ID分配

<!-- @include templates/prompts/feature-id.md -->

### 1.3 生成 PRD 文档

1. 阅读 `templates/prd-template.md` 获取模板格式
2. 阅读 `docs/00_standards/coding/` 获取编码规范（若存在）
3. 文件名格式：`<功能ID>-<功能名>-prd.md`
4. 文档顶部加 PDLC 追溯头：

<!-- @include templates/prompts/pdlc-trace.md -->

5. 文档必须包含：背景与目标、目标用户、功能需求（含优先级）、非功能需求、验收标准
6. 所有内容使用中文
7. 用户故事使用标准格式："作为[角色]，我希望[功能]，以便[收益]"

## 段二：自检（强制）

<!-- @include templates/prompts/self-audit.md -->

### PRD 自检清单（必须全部检查）

**完整性**：
- [ ] 背景与目标：清晰说明为什么做、业务价值是什么
- [ ] 目标用户：至少一类用户角色定义明确
- [ ] 用户故事：≥ 3 条且符合标准格式
- [ ] 功能清单：每条有 P0/P1/P2 优先级标注
- [ ] 验收标准：可度量、可验证（有具体数值或明确通过/不通过条件）
- [ ] 非功能需求：至少覆盖性能、安全、可用性中的两项

**一致性**：
- [ ] PDLC 追溯头所有字段齐全且日期是今天实际日期
- [ ] 功能ID 格式正确（F<YYYYMMDD>-<NN>）
- [ ] 文件路径符合规范

## 段三：修复（单次，不递归）

<!-- @include templates/prompts/loop-prevention.md -->

针对自检清单中未通过项：
- 可自动修复 → 直接补齐/修正
- 修复后再读一遍确认修复项现在通过
- 无法自动修复 → 记录到自审报告，继续段四

## 段四：更新状态机 + 交接

<!-- @include templates/prompts/state-update.md -->

**本阶段状态机更新**：
- `current_stage`: `requirements`
- 追加 history：
  ```json
  { "stage": "requirements", "done_at": "<ISO8601>", "produced": ["docs/01_requirements/prd/<...>-prd.md"], "self_audit": { "passed": <N>, "failed": <N>, "manual": <N> } }
  ```
- `next_step`: `pdlc-design`

<!-- @include templates/prompts/handoff.md -->

**本命令的 handoff 输出：**

```
✅ PRD 已创建：docs/01_requirements/prd/<feature-id>-<feature-name>-prd.md
📊 自检：<pass>/<total> 通过
📦 状态快照：docs/.pdlc-state/<feature-id>.json
👉 下一步：/pdlc-design <feature-id>
```

---

**目标需求**: $ARGUMENTS
