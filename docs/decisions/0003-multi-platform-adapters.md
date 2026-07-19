# 0003 · 让 pdlc-skills 支持多平台（Codex / Cursor / Windsurf / Copilot / Cline …）

- **状态**：Accepted
- **日期**：2026-07-19
- **作者**：kanfu-panda

---

## 1. 背景与目标

pdlc-skills 目前**只支持 Claude Code**：它靠 Claude Code 的插件 / 技能（SKILL.md → `/pdlc-*`
斜杠命令）与状态栏机制落地。但越来越多用户在别的 AI 编程工具里工作——Codex CLI、Cursor、
Windsurf、VS Code + Copilot、Cline 等。这些用户**想用 pdlc 的方法论，却因为环境不同而用不起来**，
只能让 AI「再改一个版本」，重复劳动、还容易走样。

**核心判断**：pdlc-skills 真正的价值不在「Claude Code 插件」这层外壳，而在三样**平台中立**的东西——
**① PDLC 方法论**（PRD→设计→TDD→实现→评审→发布→复盘的分阶段纪律 + Iron Law）、
**② 状态机契约**（`docs/.pdlc-state/<功能ID>.json`）、**③ 文档模板**。外壳被锁死的部分占比很小。

**目标**：在**不牺牲 Claude Code 一等公民体验**的前提下，让同一套 pdlc 方法论能被其它主流
AI 编程工具驱动，且**单一源、无分叉维护**。

**非目标（明确不做）**：
- **不做**「五个平台一次性全上」——那是 N 倍回归负担 + 追移动靶（各家命令机制都在快速演进）。
- **不做**降低 Claude Code 版体验去迁就最小公倍数；Claude Code 仍是功能最全的一等公民。
- **不做**运行时跨平台抽象层 / 统一 SDK（各家运行时差异太大，投入产出不划算）。
- **不把** statusline 等 Claude-Code-only 能力硬移植到不支持的平台（该 drop 就 drop）。
- **不为**「未来可能支持的平台」提前建通用适配框架（YAGNI）——只对**已验证有需求**的平台出适配。

---

## 2. 关键洞察：状态机本来就是跨工具的公共底座

`docs/.pdlc-state/*.json` 长在**用户项目里**，不属于任何工具——它就是仓库里的普通 JSON 文件。
这意味着：**同一个仓库，今天用 Claude Code 跑 `/pdlc-review`，明天用 Codex 接着跑，状态无缝延续。**

> 💡 **工具只是可替换的「驱动器」，PDLC 的产物是共享底物。** 多平台的正确心智模型**不是**
> 「每个工具各揣一份互不相干的 pdlc」，而是「**一套 PDLC 状态机，谁都能来推**」。这是本方案
> 最强的概念卖点，也是判断一切设计取舍的锚点：**凡是破坏「状态机跨工具可延续」的方案都不可取。**

因此本方案的第一性原理：**把中立的三层（方法论 / 状态机 / 模板）当唯一真源，各平台只是它的
不同「投影」。**

---

## 3. 可移植性盘点：哪些能搬，哪些锁死

| 组成 | 本质 | 可移植性 | 处理策略 |
|---|---|---|---|
| 36 个 SKILL.md 的**正文** | 给 LLM 的工作流指令 | ✅ 几乎全可移植（本质是 prompt） | 作为唯一源，各平台复用正文 |
| `docs/.pdlc-state/*.json` **状态机** | 项目里的普通 JSON | ✅ **完全中立** | 不动，天然共享 |
| `references/templates/` 文档模板 | Markdown | ✅ 完全可移植 | 原样带过去 |
| `@include` 共享片段（Iron Law…） | 共享 prompt | ✅ 可移植 | **构建期内联**（见 §5） |
| `next_step` / `produces` 等 frontmatter | 流程链元数据 | ⚠️ 靠正文驱动可移植；字段 schema 各家不同 | 适配器重写 frontmatter |
| `plugin.json` / marketplace / `/pdlc-*` 注册 | Claude Code 插件机制 | ❌ 锁死 | 各平台各自的分发/注册方式 |
| `allowed-tools` | 工具沙箱声明 | ❌ 各家命名不同 / 没有 | 适配器映射或省略 |
| `bin/pdlc-statusline.sh` + `/pdlc-settings` | Claude Code statusline | ❌ 锁死 | 不 emit 到不支持的平台 |

**结论**：被锁死的全是**外壳和糖**，占比小；被锁死里最核心的方法论、状态机、模板都是中立的。
这正是「可行」的根本原因——**护城河是内容，不是封装。**

### 3.1 各平台的命令机制已经收敛（利好）

调研发现主流工具**已收敛到同一模式：markdown 文件当可调用的 slash command / workflow**——
这让「正文照抄即可用」成为可能，机械活主要集中在 frontmatter schema 与文件路径：

| 平台 | 命令载体（markdown） | 项目级规则 | 分发方式 |
|---|---|---|---|
| **Claude Code**（现状） | `skills/<name>/SKILL.md` → `/pdlc-*` | `CLAUDE.md` | plugin marketplace（一行装） |
| **Codex CLI** | `~/.codex/prompts/*.md` → `/name` | `AGENTS.md` | 拷文件 / 脚本 |
| **Windsurf** | `.windsurf/workflows/*.md` → `/name` | `.windsurf/rules/` | 拷文件 |
| **Cursor** | `.cursor/commands/*.md` | `.cursor/rules/`、`AGENTS.md` | 拷文件 |
| **Copilot（VS Code）** | `.github/prompts/*.prompt.md` | `.github/copilot-instructions.md` | 拷文件 |
| **Cline** | `.clinerules/workflows/*.md` → `/name` | `.clinerules/` | 拷文件 |

> ⚠️ 上表是**待评审阶段的调研快照**，各平台机制在快速演进，实现前需逐一复核官方文档
> （尤其 frontmatter 字段与调用命名空间）。**不要**把此表当成永久契约。
>
> 📌 **实现纪要（v1.5.1，真机验证后更正）**：上表「Codex CLI → `~/.codex/prompts/*.md` → `/name` 斜杠命令」的假设**未在真机验证就发了 v1.5.0，是错的**。实测目标 Codex 是**兼容 Claude Code 生态的发行版**，用 `~/.codex/skills/<name>/SKILL.md`（frontmatter `name`+`description`，靠 **description 触发、非斜杠命令**）；gpt-5.6-sol 按描述匹配到 `pdlc-prd` 并正确执行、写出 schema 正确的状态机。v1.5.1 已把适配器改到 `skills/` 布局。教训：**§6.1 的准入闸必须在真机上跑**——这次栽在没验证就发版。（vanilla OpenAI Codex 是否用 `prompts/` 仍未验证，留待有该环境的用户复核。）

---

## 4. 分层策略：三层投影，按需交付

不追求「所有平台等价」，而是分三层，**成本与体验各就各位**：

- **Tier 1 · 通用方法论层（保底，覆盖所有工具）**
  一份 `AGENTS.md` 风格的方法论文档 + 模板 + 状态机 spec，教会**任何** agent 整套 PDLC，
  用自然语言触发（「按 pdlc 跑一轮 review」）。到处优雅降级、维护成本最低。**这是多平台的地板。**

- **Tier 2 · Claude Code（一等公民，维持现状）**
  现在这套 36 命令 + statusline + loop 自主收敛，**体验最全，不降级**。

- **Tier 3 · 按需原生命令（甜点，逐个平台加）**
  从**同一源** transpile 出目标平台的原生命令文件（Codex prompts / Windsurf workflows…），
  让该平台用户也能敲 `/pdlc-review`。**只对已验证有需求的平台做**，不预建全家桶。

> 三层不是「必须全做」，而是**优先级**：Tier 1 先立地板，Tier 3 按真实需求一个个长。

---

## 5. 架构方案：单一源 + 构建期适配器（transpile）

保留现有 `skills/*/SKILL.md` 为**唯一权威源**，新增一个**构建步骤**把它投影到各平台包：

```
skills/*/SKILL.md  ─┐
references/…        ├─▶  adapters/build.<lang>  ─▶  dist/claude-code/  (现状，不变)
状态机 spec / 模板   ─┘                              dist/codex/        (~/.codex/prompts/*.md + AGENTS.md)
                                                    dist/windsurf/     (.windsurf/workflows/*.md)
                                                    dist/cursor/       (.cursor/commands/*.md)
                                                    dist/copilot/      (.github/prompts/*.prompt.md)
```

适配器（每个目标平台一个小转译器）干四件事：

1. **构建期内联 `@include`**——把 Iron Law / handoff 等共享片段直接内联进正文，各平台拿到
   **自包含**文件，不再依赖「模型读注释按约定加载」这个 Claude-Code-only 的运行时约定。
   > 💡 这一步把原本的**弱点**（`@include` 非 Claude Code 官方特性、跨平台不保证解析）
   > 变成了**优点**：内联后各平台零依赖。
2. **重写 frontmatter**——把 pdlc 内部字段映射到目标平台的 schema（或剥掉平台不认的字段，
   把 `next_step` 等语义下沉进正文的自然语言指令，靠 prompt 驱动链式推进）。
3. **映射命令命名空间**——正文里对下一步命令的引用（如「接着跑 `/pdlc-review`」）按平台改写。
4. **丢弃不支持的能力**——statusline、`/pdlc-settings` 等 Claude-Code-only 交付物在其它平台
   直接不 emit，Tier 1 方法论文档里以「此能力仅 Claude Code」注明。

**分发**：配一个 `install.sh` 增强版——**探测当前工具**（或让用户 `--target codex`），把对应
`dist/<平台>/` 的文件拷到该平台约定位置。Claude Code 仍走 marketplace 一行装、路径不变。

### 5.1 为什么选「构建期投影」而非其它

- **对比「每平台各维护一份源」**：分叉是维护地狱，改一个 stage 要手动同步 N 份，必然走样。否决。
- **对比「运行时统一抽象层」**：各家运行时差异大、投入产出低，且 §1 已列为非目标。否决。
- **构建期投影的代价**：多一个 `dist/` 构建产物 + 每平台一个小转译器 + 每平台一套冒烟测试。
  这是**可控且线性**的成本，且新增平台是**加法**（写一个新适配器），不动既有源。✅

---

## 6. 分阶段落地（先窄后宽，一次一个平台）

**绝不一次上五个平台。** 平台需求都真实——作者本人在下列平台间日常轮换切用（Claude Code 额度
受限时切别家继续干活），所以排序不按「谁有需求」（都有），而按「**先验 GPT 系能否老实写状态，
再上命令机制更杂的**」，且**一次只接一个**——这样跨工具状态完整性一旦崩，能定位是哪个适配器写坏的。

**确定顺序**：

1. **Phase 0 · Tier 1 通用层**：抽出一份 `AGENTS.md` 风格 pdlc 方法论文档（内联关键片段）+
   指向模板与状态机 spec。**零风险**（不碰现有 Claude Code 包），立刻让所有工具能「自然语言跑 pdlc」。
2. **Phase 1 · Claude Code（已成，一等公民）** —— 现状基线，不变。
3. **Phase 2 · Codex（首个 Tier 3 适配器）**：`adapters/build.codex` → `~/.codex/prompts/`。
   先做它因为它是**作者日常轮换的平台之一**、且 GPT 驱动——正好用来验最硬的假设。
4. **Phase 3 · VS Code Copilot**：`.github/prompts/*.prompt.md`（同为 GPT 系，验证可复用 Codex 经验）。
5. **Phase 4 · Cursor / Windsurf 等**：命令机制更杂、移动靶更明显，放最后按同样闸门逐个接。

### 6.1 每个平台的准入闸（不可退让）

新平台接入前**必须过两关**，过了才允许它参与「跨工具状态延续」：

1. **状态完整性闸（§9#4）**：在该平台跑一轮、**故意造一个红灯测试**，验证它写进
   `docs/.pdlc-state/` 的 `last_phase_result.checks` 来自**真实退出码**、`ok=false` 不虚报。
   —— 因为作者会来回切，任一平台写脏状态就污染所有平台共用的那份；**最弱环决定整体可信度。**
2. **刚性分级（§7#4）**：判定该平台配「完整 pdlc」还是只给「Tier-1 精简版」，并在文档如实标注——
   避免「同一套 pdlc 在不同平台刚性不均匀、状态可信度不一致」这个隐患。

> 📌 Phase 0 + Phase 2（Codex）是本方案的**最小可交付切片**；Phase 3/4 不在首个 PR 承诺内，
> 各自单独一个适配器 + 冒烟测试 + 过准入闸后再合。

---

## 7. 风险与取舍（战略层）

1. **维护成本 N 倍**：每加一平台，stage 改动就要多一套回归验证。**缓解**：单一源 + 每平台
   自动化冒烟测试（mock 一个状态机、断言生成的命令文件结构正确），把「走样」挡在 CI 前的本地测试里。
2. **各平台机制是移动靶**：Codex/Cursor/Windsurf 的命令约定都在演进。**缓解**：适配器薄、隔离在
   `adapters/`，某平台变了只改它自己那个转译器；Tier 1 通用层不受影响。
3. **真正的风险不是「有没有需求」，而是「跨平台状态完整性」**：需求是真实的——作者本人在
   Claude Code / Codex / Copilot / Cursor / Windsurf 间日常轮换（额度受限即切别家），多平台是其
   自用刚需 + dogfooding，不是为假想用户造。风险转移到：**多个不同平台的 agent 写同一份状态机时，
   最弱的那个若用自评而非真退出码，就污染所有平台共用的状态**（N 路最弱环）。**缓解**：§6.1 的
   状态完整性准入闸——每接一个平台先造红灯验 `ok=false` 不虚报，过闸才允许它参与跨工具延续。
   外部推广需求另说：Tier 1 已是净收益，Tier 3 是否扩到 Claude Code 之外的**别人**，按真实需求再定。
4. **体验不对等的预期管理**：非 Claude Code 平台拿不到 statusline / loop 自主收敛。**缓解**：
   Tier 1 文档里如实标注「哪些能力仅 Claude Code」，不夸大跨平台等价。
5. **CI 用量**：多平台构建/测试若全塞 GitHub Actions 会烧配额（违反项目 CI 纪律）。**缓解**：
   构建与冒烟测试**全本地 / pre-commit**，CI 只在 release tag 触发时打包产物。

---

## 8. 交付物（Phase 0 + Phase 2（Codex）范围）

```
docs/pdlc-methodology.md（或 AGENTS.md 模板）  ← Tier 1 通用方法论层（内联关键片段、平台无关）
adapters/build.codex.*                         ← Codex 转译器：SKILL.md → ~/.codex/prompts/*.md
adapters/README.md                             ← 适配器架构说明（如何新增一个平台）
dist/codex/                                    ← 构建产物（.gitignore 或按需入库，待定见 §9）
install.sh（增强）                             ← 增加 --target codex：探测/指定平台并落文件
tests/adapter-codex-check.sh                   ← Codex 产物结构冒烟（本地/pre-commit 跑）
docs/usage-guide.md（新增一节）                ← 「在 Codex 里用 pdlc」接入说明
```

> 📌 **随附同步**：本方案会新增「多平台」概念，需同步 `README.md` / `README.zh-CN.md`
> （加「支持的平台」小节，如实标注 Tier 分层与能力差异）、`docs/ARCHITECTURE.md`
> （新增「多平台适配器」一节）、`docs/GLOSSARY.md`（Tier / 适配器 / 通用层术语）。

---

## 9. 待决问题

1. **`dist/` 是否入库**：构建产物入库（用户直接拷）省一步构建，但污染仓库、易与源不同步；
   或只入库、CI 打包发 Release。倾向**不入库源码树，release 时打包**——待定。
2. **Tier 1 文档形态**：单一 `docs/pdlc-methodology.md` 由各平台 rules 文件 `@import`／链接，
   还是每平台生成一份自包含 `AGENTS.md`？倾向**单一源 + 各平台投影**，与 §5 一致。
3. **frontmatter 字段下沉的边界**：`next_step` / `produces` / `requires` 有多少能安全下沉进
   自然语言正文而不丢流程严谨性？需在 Codex PoC 里实测链式推进是否可靠。
4. **状态机跨工具写入的一致性**：不同工具的 agent 写 `docs/.pdlc-state/` 时，`run_mode`、
   `last_phase_result.checks` 的语义是否都能被非 Claude Code 平台如实产出（尤其「客观 check
   来自真实退出码」这条）？这是 §2 假设成立与否的关键，PoC 必须验证。
5. **命名 / 品牌**：跨平台后是否仍叫 pdlc-skills（"skills" 是 Claude Code 术语）？还是仓库名
   保持、对外描述改为「PDLC 方法论 + 多平台适配」？倾向仓库名不动、描述调整——待定。
6. **常驻规则的 token 成本（Phase 2 接平台时定）**：Tier 1 方法论文档 `docs/pdlc-methodology.md`
   约 275 行。在 Claude Code 里它是「底层规格、按需读」，无常驻开销；但 Cursor / Copilot / Cline
   会把项目规则文件（`.cursor/rules` / `copilot-instructions.md` / `.clinerules`）**每轮常驻加载**——
   整份进上下文 = 每轮吃 token。适配器接这类平台时倾向：**常驻只放精简核**（IRON LAW + 状态机契约 +
   §7 客观检查命门 + §8 触发映射），完整方法论文档**按需引用**。拆分点与精简核边界待 Codex / Cursor
   PoC 实测后定——这也印证 §9#2「单一源 + 各平台投影」：投影时按平台的加载模型裁剪常驻量。

---

## 10. 一句话小结

pdlc 的价值是**平台中立的方法论 + 状态机 + 模板**，被锁死的只是 Claude Code 的外壳。因此多平台
**可行且是加法**：以现有 `skills/*/SKILL.md` 为唯一源，**构建期内联 `@include` 并投影**出各平台
原生命令文件（`@include` 从弱点变自包含优点），Claude Code 维持一等公民不降级。落地**先窄后宽**——
先出 **Tier 1 通用方法论层**立地板，再拿**作者在用的 Codex** 做单点 PoC，验证「同一状态机被两个工具
交替驱动、无缝延续」这个第一性假设；跑通再按真实需求逐个长平台。**绝不 all-in 五平台、绝不分叉源、
绝不为未来平台预建全家桶（YAGNI）。**
