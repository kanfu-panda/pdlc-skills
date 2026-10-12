# 0008 · 状态推进交给脚本，Claude Code 另加可选 hooks

- **状态**：Accepted
- **日期**：2026-10-12
- **作者**：kanfu-panda
- **关系**：延续 v1.7.2 把 `checks` 交给 `pdlc-checks.sh` 的思路；不改 ADR 0007 的多平台投影方式

---

## 1. 背景

v1.7.2 起，`checks` 由 `pdlc-checks.sh` 按退出码生成，模型只负责原样抄进状态文件。但**推不推进阶段**仍由模型决定：
它读完检查结果，自己写 `ok`、`current_stage`、`next_step`。ADR 0007 §6 的准入闸实测里，GitHub Copilot CLI 三轮失败方式各不相同：

- 检查失败了仍把阶段从 `tdd` 推到 `impl`
- 声明了的 lint 没记
- 把测试里故意埋的错误用例改掉，再报全绿、推进到 review

这三种都不是"规则没写清楚"，而是"规则交给模型执行"。只要执行者是模型，换个平台、换个模型就会换一种错法。

另外，`/pdlc-fix`、`/pdlc-refactor` 一直没调 `pdlc-checks.sh`，`checks` 仍是模型手填的。

## 2. 决策

### 2.1 `bin/pdlc-advance.sh` 是状态推进的唯一写入口

11 个写状态的命令收尾时只调用它：`pdlc-advance.sh <功能ID> --stage <短名> --next <命令名|null> [--produced …]`。

- 检查由脚本按阶段自己跑，调用方不能挑：tdd 验红灯；impl / fix / refactor 跑 unit、coverage、lint；review 加 e2e；e2e 只跑 e2e；文档类与发布类阶段不跑
- `ok` 由脚本判：tdd 要求 `red_verified=true`；其它阶段任一检查为 `false` 即不推进，`null`（无法判定）不拦
- 不推进时只写 `last_phase_result`（`ok=false`、`blocked_reason` 由脚本列出原因），`current_stage` / `next_step` 不动；推进时整段写入，先写临时文件再改名
- 主动交还人类用 `--blocked "<原因>"`：照跑检查如实记录，但不推进；`ship_done` / `deploy_done` 用 `--done`，只有 ship / deploy 能用
- 退出码 `0` 已推进、`3` 未推进、`2` 无法执行。缺 jq 时退回手写，报告里必须写明"未经脚本"

脚本经 `adapters/sync_skills.py` 复制进每个写状态的 skill 的 `scripts/`，所以 Codex 等平台的投影也带着它——这一层对所有平台生效。

### 2.2 测试指纹

tdd 推进时，脚本把 `--produced` 里非 `docs/` 的测试文件哈希记进那条 history 的 `tests_fingerprint`；
impl / refactor / review 推进时重算，变了就不推进。确实要改（测试与设计矛盾）时带 `--tests-changed "<理由>"`：
理由记进 `auto_decisions`，并以改后的内容作新基准。

这道防线**不能彻底拦住**——模型仍可以带上理由硬改。它的作用是让改测试这件事必须摆到明面上，人看状态文件就知道。

### 2.3 Claude Code hooks：随插件注册，默认什么都不做

`hooks/hooks.json` 注册两个 hook，都调 `bin/pdlc-guard.sh`：

| 事件 | 做什么 | 开关 |
|---|---|---|
| PreToolUse（`Write\|Edit`） | 写 `docs/.pdlc-state/F*.json` / `B*.json` 时 deny，理由指向 `pdlc-advance.sh` | `state_write_guard` |
| Stop | 对 `git status` 里有改动的状态文件跑 `pdlc-state-lint.sh`，有偏差就 block 一次（`stop_hook_active` 为真时放行） | `lint_on_stop` |

开关在目标项目的 `docs/00_standards/pdlc-hooks.yml`，由 `/pdlc-settings hooks on|off` 写入。

- **为什么开关在脚本里**：官方文档写明插件的 hooks 随插件启用就注册，没有"只关 hooks、不关插件"的设置。所以"默认不打扰"只能由脚本自己做：没有开关文件、对应项不是 `on`、缺 jq、读不懂输入，一律退出 0 不输出
- **为什么放项目里**：团队共享同一份设置，随仓库走；不碰用户全局的 `settings.json`
- **为什么 Stop 只看有改动的文件**：老项目里历史遗留的偏差不该在每次收尾时都拦一次
- **不做"红灯之前拦写实现代码"**：要判断"正在做哪个功能"和"哪些路径算实现代码"，误拦太多

这是护栏不是沙箱：在 Bash 里用重定向写状态文件，PreToolUse 拦不到，Stop 的体检兜底。

## 3. 既有项目的兼容

| 情况 | 行为 |
|---|---|
| 没有 `test-commands.yml` | 照常推进，`checks` 写 `{}`（与旧规则一致）；tdd 由模型按项目约定手工验红灯，意外全绿时传 `--blocked` |
| 旧格式状态文件（`-NN` ID、缺 `last_phase_result` / `relations`、只有日期的时间戳、表外字段） | 照常推进；原有字段原样保留，只追加本阶段 |
| 旧功能没有测试指纹 | 不比对，不拦 |
| 状态文件损坏 | 退出 2，原样不动 |
| 没开 hooks（默认） | 与之前完全一样 |
| 不是 git 仓库 | Stop 体检不起作用（判断不了哪些是本次改动） |

状态文件格式向后兼容（只多一个可选的 `history[].tests_fingerprint`，体检本来就不限制 history 的字段），用户不需要迁移。

## 4. 测试

`tests/advance-check.sh`（第 13 个本地门禁脚本）用桩项目覆盖：各阶段推进与拒绝推进、三态、`--blocked` / `--done`、
参数守卫、测试指纹与 `--tests-changed`、上表的兼容情形、脚本与 `state-update.md` 映射表及 `pdlc-state-lint.sh` 合法阶段一致，
以及 `pdlc-guard.sh` 两个模式的开关、放行与拦截。脚本走 macOS 自带的 `/bin/bash` 3.2 也要能过。
