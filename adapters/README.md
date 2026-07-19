# 平台适配器（多平台投影）

把 pdlc-skills 的**单一源**（`skills/*/SKILL.md` + `references/templates/`）**构建期投影**成各 AI 编程工具的原生命令文件。设计与取舍见 [ADR 0003](../docs/decisions/0003-multi-platform-adapters.md)。

## 心智模型

- **唯一源**：`skills/*/SKILL.md`（Claude Code 的技能正文）。**永远只改这里**，不手维护各平台副本。
- **投影**：每个适配器是一个小转译器，把源投影到目标平台的命令目录。新增平台 = 新增一个适配器，**不动源**。
- **Claude Code 是一等公民**，不经适配器——它直接用 `skills/`（本仓库即插件）。适配器只服务**其它**平台。

## 转译四步（每个适配器都做）

1. **内联 `@include`**：把 `references/templates/prompts/*.md` 片段（IRON LAW、状态机、handoff…）直接内联进正文，
   产出**自包含**命令文件，不依赖「模型读注释按约定加载」这个 Claude-Code-only 运行时约定；顺带剥掉片段首行的来源标记注释（避免把 `Layer 1/2 命令` 等 Claude 术语带出去）。
2. **重写 frontmatter**：只留目标平台认识的字段，剥掉 Claude 内部字段（`layer` / `produces` / `requires` / `allowed-tools` / …）。
3. **物化命名空间**：把 `next_step` 等靠 frontmatter 驱动的链式推进，写成正文里的显式指令（目标平台不把 frontmatter 当逻辑）。
4. **丢弃不支持能力**：Claude-Code-only 的 skill（状态栏配置、自主收敛引擎）不投影。

## 已有适配器

| 适配器 | 目标 | 脚本 | 产物 |
|---|---|---|---|
| Codex | Codex CLI 自定义 prompts（`~/.codex/prompts/*.md`） | `build_codex.py` | `dist/codex/`（prompts + templates + 方法论） |

### Codex（`build_codex.py`）

```bash
python3 adapters/build_codex.py [输出目录]   # 默认 dist/codex
# 或经 installer 一步装：
bash install.sh --target codex               # 构建 + 拷到 ~/.codex/
bash install.sh --target codex --uninstall   # 移除
```

- **语言**：python3 **标准库**（零 pip 依赖）。选 python 而非 bash：markdown 文本变换（frontmatter 解析、内联、改写）用 bash 的 sed/awk 脆弱易错，python 稳健得多；且这是**构建期专用**、不进运行时。
- **denylist**（本 PoC 暂不投影，2 个）：`pdlc-settings`（真·Claude-only，状态栏配置）；`pdlc-loop-run`（默认 Task 版耦合 Claude 子代理派发，Runbook 版可移植但需驱动 harness + 过准入闸）。`pdlc-loop-next` **已投影**（逻辑平台中立，作独立只读查询），其正文里 `claude -p` 驱动 helper 由 `adapter:claude-only` 哨兵剥掉。其余共 34 个 skill 投影为 `/pdlc-*` prompt。详见 `build_codex.py` 里 `DENYLIST` 的注释。
- **`adapter:claude-only` 哨兵**：源里被 `<!-- adapter:claude-only-start -->` / `<!-- adapter:claude-only-end -->` 包裹的块是 Claude 专属内容（如用 `claude -p` 驱动的示例管线），投影到其它平台时整段剥掉；Claude Code 看不见 HTML 注释、行为不变。这是「单一源、按目标裁剪」的通用手段。
- **模板**：`references/templates/*-template.*` 拷到 `dist/codex/templates/`，正文里 `templates/X.md` 引用改写到 `~/.codex/pdlc/templates/X.md`。
- **frontmatter 假设**：Codex 自定义 prompt 支持 `description` / `argument-hint` frontmatter。若你的 Codex 版本不解析 frontmatter，仅头部多几行文本、不影响正文（正文自包含）。

> ⚠️ Codex 的 prompt 是**按需调用**（像 Claude 斜杠命令），非常驻，所以自包含内联无常驻 token 成本。
> Cursor / Copilot / Cline 会把项目规则**每轮常驻**——那类适配器（Phase 3/4）需按 [ADR 0003 §9#6](../docs/decisions/0003-multi-platform-adapters.md) 常驻只放精简核、完整文档按需引用。

## 新增一个平台适配器

1. 读目标平台的命令机制（命令目录、frontmatter schema、调用命名空间、是否常驻加载）。
2. 仿 `build_codex.py` 写 `build_<platform>.py`：复用「转译四步」，按平台差异调 frontmatter 与路径改写。
3. 在 `install.sh` 加 `--target <platform>` 分支。
4. 加 `tests/adapter-<platform>-check.sh`：断言产物结构（无残留 `@include`、denylist 缺席、frontmatter 剥离、命名空间物化）。
5. **过准入闸**（ADR 0003 §6.1）：在该平台造一个红灯测试，验证它写进 `docs/.pdlc-state/` 的 `checks` 来自真实退出码、`ok=false` 不虚报——过了才允许它参与跨工具状态延续。

## 产物不入库

`dist/` 是构建产物，`.gitignore` 忽略，按需 `python3 adapters/build_*.py` 现生成（见 ADR 0003 §9#1）。
