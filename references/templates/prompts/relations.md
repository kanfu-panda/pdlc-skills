<!-- 关系链定义 · RFC#6 单一真相源 · 被 state-update.md / pdlc-relate / pdlc-trace.md 引用 -->

## Feature 关系链（6 种类型）

PDLC 用扁平 feature ID 空间。关系链在 5 个位置冗余表达，本文件是类型与语法的**单一真相源**。

### 6 种关系类型

| 类型 | 语义 | 方向性 | 示例 |
|---|---|---|---|
| `extends` | A 是 B 的增量增强 | 有向（A→B） | `user-auth-otp` extends `user-auth-phone` |
| `depends_on` | A 需要 B 存在 | 有向（A→B） | `user-profile` depends_on `user-base` |
| `supersedes` | A 替代 B（B 进入废弃/待机） | 有向（A→B） | `auth-v2` supersedes `auth-v1` |
| `resolves` | A 修复缺陷 B | 有向（A→B） | `F20260603-090000` resolves `B20260520-110000` |
| `conflicts_with` | A 与 B 互斥 | 对称 | `payment-stripe` conflicts_with `payment-paypal` |
| `relates_to` | 弱耦合，应一起考虑 | 对称 | `password-policy` relates_to `otp-policy` |

**有向 vs 对称**：
- 有向类型（extends / depends_on / supersedes / resolves）只在源 feature 的关系块里存一条出边。
- 对称类型（conflicts_with / relates_to）写入时**两端都要镜像**（A.conflicts_with 含 B 时，B.conflicts_with 也必须含 A）。

### 表达位置 1：文档追溯头（pdlc-trace）

在 PDLC-TRACE 头加一行（无关系时整行省略）：

```
<!-- 关系: extends=F20260510-100000; depends_on=F20260501-090000,F20260415-110000; resolves=B20260520-110000 -->
```

语法：`type=id` 对，多 id 用 `,` 分隔，多对用 `; ` 分隔。

### 表达位置 2：状态机关系块（state JSON）

见 `state-update.md` 的 `relations` block。存**出边**；入边由 `/pdlc-relate rebuild` 派生到 `_relations.json`。

### 表达位置 3：反向索引 `_relations.json`（自动生成）

`/pdlc-relate rebuild` 扫描所有 `<id>.json` 关系块 + 文档头，生成正向 edges + 预计算 inbound/outbound index。

### 表达位置 4：全局图 `_graph.md`（自动生成）

mermaid 可视化。边样式按类型区分：`supersedes` 虚线、`conflicts_with` 粗线、其余实线。

### 表达位置 5：PRD §6.1 关系表

见 `prd-template.md` §6.1。

### 校验规则（`/pdlc-relate validate`）

- 悬空引用：关系指向的 ID 不存在
- 自引用：feature 关系到自己
- 循环：`extends` / `depends_on` 链不允许成环
- 矛盾对：同一目标同时 `supersedes` + `depends_on`
- 对称一致性：`conflicts_with` / `relates_to` 两端必须互含
