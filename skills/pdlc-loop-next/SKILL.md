---
name: pdlc-loop-next
description: 打印循环下一步应执行的命令（机器可读，供 loop 驱动）
argument-hint: <功能ID>
allowed-tools: Read, Glob, Bash
layer: 3
stage: ops
produces: []
requires:
  - docs/.pdlc-state/
next_step: null
terminal_state: null
---

# 循环下一步（loop-next）

读取指定功能的状态机，**只打印一个 token**，告诉外层循环下一步该跑哪条命令。它是 `/pdlc-loop-run` 与用户自写 bash 循环的低层 helper——自身**只读、不改任何状态**、不含 `--autonomous` 语义。

## 输出契约（安全关键）

输出**必须**是下列固定白名单中的**单个 token**，独占一行，**不含任何散文、标点或解释，尤其不要用代码块（三反引号）或反引号包裹**：

```
pdlc-tdd | pdlc-implement | pdlc-review | done | blocked
```

- ✅ 正确：整个回复就是一行 `pdlc-implement`
- ❌ 错误：用 ``` 包成代码块、用反引号包住、加 `下一步：` 前缀或任何解释——**任何包裹/前缀都会让下游 `case` 匹配失败**。
- 本命令只覆盖**机械收敛段** `tdd → implement → review`。到达 `review_done` 或更后（发布属人工闸门）→ 输出 `done`，**绝不**输出 `pdlc-ship` / `pdlc-deploy`（发布永远留人）。
- 下游 helper **必须**先**净化**（去反引号/空白）再校验 token 属于白名单，非法即中止（见下方参考脚本）——这是防御模型偶发包裹的兜底。

## 执行流程

1. 从 `$ARGUMENTS` 取功能ID；读取 `docs/.pdlc-state/<功能ID>.json`。
2. 文件不存在 / 无法解析 → 输出 `blocked`。
3. `last_phase_result.blocked_reason` 非空 → 输出 `blocked`。
4. `current_stage` 属终态（以 `_done` 结尾——实际由编排器写入的终态值为 `feature_done` / `fix_done`）→ 输出 `done`。（注：单阶段命令的 `current_stage` 用短名 `impl`/`review`，review 完成的判定靠下面第 5 步的 `next_step`，不靠此处。）
5. 否则**以 `next_step`（状态机里存的下一跳命令名）为主键**判定并输出。

   > ⚠️ **必须用 `next_step` 判定，不要用 `current_stage` 字符串匹配**：现有状态机的 `current_stage` 用短名（`requirements` / `design` / `tdd` / `impl` / `review`，如 `pdlc-implement` 明写 `current_stage: impl`），格式不适合直接判阶段；而 `next_step` 是无歧义的命令名。

   | `next_step` | 输出 | 说明 |
   |---|---|---|
   | `pdlc-tdd` | `pdlc-tdd` | |
   | `pdlc-implement` | `pdlc-implement` | |
   | `pdlc-review` | `pdlc-review` | |
   | `pdlc-ship` / `pdlc-deploy` / `null` | `done` | 机械收敛已完成（review 通过），发布留人 |
   | `pdlc-prd` / `pdlc-design` | `blocked` | 尚在 tdd 之前，需人工（超出循环范围） |
   | 其它 | `blocked` | |

6. 不写文件、不产任何 artifact。

## 参考 helper（供 usage-guide / 外层循环使用，含白名单校验）

```bash
# 净化：去反引号后，从输出中抽取第一个白名单 token（容忍首尾空白/标点/前缀/代码块包裹）
RAW=$(claude -p "/pdlc-loop-next $ID")
CMD=$(printf '%s' "$RAW" | tr -d '`' | grep -oE '(pdlc-tdd|pdlc-implement|pdlc-review|done|blocked)' | head -1)
case "$CMD" in
  pdlc-tdd|pdlc-implement|pdlc-review)
    claude -p "/$CMD $ID --autonomous" ;;
  done)    echo "✅ 已到 review_done，交人工决定是否 /pdlc-ship"; break ;;
  blocked) echo "⛔ 需人工介入"; break ;;
  *)       echo "❌ 非法命令（原始输出：$RAW）"; exit 1 ;;
esac
```

功能ID: $ARGUMENTS
