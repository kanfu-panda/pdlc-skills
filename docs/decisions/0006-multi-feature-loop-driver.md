# 0006 · 多功能收敛循环驱动（bin/pdlc-loop.sh）

- **状态**：Accepted
- **日期**：2026-09-24
- **作者**：kanfu-panda

---

## 1. 背景与目标

[ADR 0001](0001-loop-engineering-integration.md) 给了收敛循环两种形态：插件内的 Task 版（`/pdlc-loop-run`，一次一个功能），
和写在使用手册里的外部 bash Runbook（一段示例脚本）。[ADR 0004](0004-codex-loop-run.md) 为 Codex 交付了一个真正的驱动
`adapters/codex-loop-run.sh`，同样一次一个功能。

实际使用里，外层想做的往往是「这几个功能一起推」「挑出所有能推的，并行跑一晚上」。插件没有提供这层，
AI 只能每次现写一个外层脚本：护栏靠临场发挥，依赖顺序、并行时的相互干扰、跑到一半的进度都没有着落。

**目标**：提供一个平台中立的外部驱动，AI 识别到「多个功能 / 并行 / 长跑」时直接用它：

- 接受多个功能 ID，或 `--ready` 自动挑出处于收敛段、未阻塞的功能
- `--platform claude|codex`，每一步一个全新进程
- `--parallel N`，互不干扰地同时跑
- 按状态机里的 `depends_on` 排先后
- 护栏与 Task 版一致，并且**绝不发布**
- 留下运行记录，`/pdlc-status` 能读出进度

**非目标**：不自动提交、合并、发布；不预测完成时间；不改动状态机契约（驱动只读状态机、只由各阶段 skill 写）。

---

## 2. 决策

### 2.1 一个驱动，两个平台

`bin/pdlc-loop.sh` 实现全部循环逻辑。`adapters/codex-loop-run.sh` 改为 `exec bin/pdlc-loop.sh --platform codex "$@"`，
原有调用方式、退出码与 21 条回归断言不变。两份循环实现合成一份，loop-next 映射不会再在两处各自漂移。

每一步的命令：

- claude：在功能的工作目录里 `claude -p "/pdlc-<阶段> <ID> --autonomous" --max-budget-usd X [--model <推荐模型>] <权限参数>`。
  模型取目标 skill frontmatter 的 `recommended_model`（ADR 0001 §G），权限参数默认与 evals 一致，可用
  `PDLC_LOOP_CLAUDE_FLAGS` 整体替换
- codex：`codex exec -C <工作目录> -s workspace-write --skip-git-repo-check "按 pdlc <阶段> <ID> --autonomous"`

### 2.2 护栏

与 Task 版和 ADR 0004 相同：步数上限（默认 4）、fail-stop（`last_phase_result.ok` 不是 `true`）、
stuck-stop（`current_stage` 没变）、收敛即停（`next_step` 为 `pdlc-ship`）。另外：

- **claude 真跑必须给 `--max-budget-usd`**，缺了按用法错退出——ADR 0001 已把预算定为硬护栏，驱动把它从文档要求变成代码约束
- **每个项目同时只有一个驱动**：运行目录里的 `lock` 记着驱动进程号；进程还在就拒绝，进程已不在就接管
- **中断可恢复**：收到 INT / TERM 时终止正在跑的步骤、把相关功能记为「被中断」、释放锁。被打断的那一步没写状态机，
  重跑同样的命令就从各功能当前阶段继续
- 总退出码取各功能退出码的最大值：`0` 全部收敛，`2` 阻塞 / 跳过，`3` 上限，`4` 平台出错，`5` 状态没推进

### 2.3 并行：每个功能一个 git worktree

同一个工作区里并行跑两个功能，测试、构建产物、状态文件都会互相踩。所以 `--parallel N>1` 时：

- 每个功能在 `.worktrees/pdlc-loop/<ID>`（分支 `pdlc-loop/<ID>`，从 `HEAD` 建）里跑；已有的 worktree 直接复用，便于续跑
- `/.worktrees/pdlc-loop/` 写进 `<git 公共目录>/info/exclude`，不出现在 `git status` 里，也不改项目的 `.gitignore`
- worktree 从 `HEAD` 建，看得到的只有已提交的状态文件——状态文件未提交或有改动的功能直接跳过，并说明原因
- 驱动**不提交、不合并**，产物留在 worktree 里由人审阅。这与「AI 只开不合」的做法一致，也让并行结果可以逐个取舍
- 默认并行数是 1（在原工作区里串行跑）。并行数翻倍，花费也翻倍，所以要显式给出

### 2.4 depends_on

读状态机的 `relations.depends_on`，只认形如功能 / 缺陷 ID 的目标：

- 依赖在本次运行里 → 等它收敛；它没收敛（阻塞、上限、出错、跳过）→ 依赖方跳过
- 依赖不在本次运行里 → 它必须已经收敛（`next_step` 为 `pdlc-ship` 或已发布），否则依赖方跳过
- 所有排队的功能都在等彼此、又没有在跑的 → 依赖成环，全部跳过，一次模型都不调用
- 并行时，依赖方需要看到被依赖方的改动，而驱动不合并。所以只有一个本次运行中的依赖时，依赖方**在被依赖方的 worktree 里接着跑**；
  同时依赖两个及以上本次运行中的功能时跳过，等人合并后再单独跑

### 2.5 运行记录与进度

- 位置：git 项目放在 `<git 公共目录>/pdlc-loop/`（不入库，各 worktree 共享）；非 git 项目放在 `docs/.pdlc-state/_loop/`，
  以 `_` 开头，读侧与体检照例跳过
- 结构：`latest` 指向最近一次运行；`<run-id>/run.json` 记平台、并行数、功能列表、驱动进程号与主机；
  每个功能一份 `<ID>.json`（状态、阶段、步数、各时间点、说明、工作目录）和一份 `<ID>.log`（模型的完整输出）
- 并发写入：每份功能记录在启动后只由它自己的 worker 进程写，主进程只读，不需要锁；写入一律先写临时文件再 `mv`
- `--status` 由脚本确定性地算出：功能数与各状态计数、每个功能在哪一步、本步已跑多久；
  驱动进程已不在但运行没收尾时提示可能被中断，单步超过 45 分钟（`PDLC_LOOP_STALE_MIN`）时提示看日志
- **不给预计完成时间**：一步可能是几十秒的 review，也可能是半小时的 implement，平均值只会误导
- `/pdlc-status` 跑随 skill 分发的 `scripts/pdlc-loop.sh --status`，把输出原样放进总览，不重算。worktree 里的功能，
  主工作区的状态文件不是最新的，总览会注明以循环运行一节为准

---

## 3. 取舍

- **为什么不做成 skill**：长跑的外层循环本身不该占着一个模型会话；一步一个全新进程也正是 ADR 0001 推荐的隔离方式。
  skill（`/pdlc-loop-run`、`/pdlc-status`）只负责告诉模型有这个驱动、怎么调用，驱动随它们分发在 `scripts/` 下
- **为什么不自动合并 worktree**：合并需要判断冲突与取舍，属于人工评审；自动合并还会把一个功能的失败带进另一个
- **为什么依赖方借用被依赖方的 worktree，而不是在被依赖方收敛后自动提交**：自动提交会替人做版本控制决定，
  借用 worktree 不产生任何提交，代价只是这两个功能的产物落在同一个分支上
- **兼容性**：驱动要在 macOS 自带的 bash 3.2 上跑，所以不用关联数组、`mapfile`、`wait -n`；功能列表用空白分隔的字符串，
  worker 进程号写在运行目录里，调度用轮询（`PDLC_LOOP_POLL`，默认 2 秒）

---

## 4. 验证

- `tests/loop-driver-check.sh`（80 条断言）：用假的 claude / codex 驱动 mock 状态机，覆盖用法守卫、`--ready` 挑选、
  串行与总退出码、各护栏、claude 命令形态（预算、推荐模型）、依赖排序 / 跳过 / 成环、并行 worktree（确实重叠执行、
  主工作区不被改、未提交的跳过、依赖方借用 worktree、`git status` 干净）、运行记录位置、锁与中断、`--status` 各种提示。
  测试优先用 `/bin/bash` 跑驱动，保证 bash 3.2 兼容
- `tests/adapter-codex-loop-run-check.sh` 的 21 条断言在 `codex-loop-run.sh` 改为入口后原样通过
- 针对驱动的 12 组变异里 11 组变红；剩下一组去掉「claude 必须给预算」的检查后，紧接着的「预算须为数字」检查仍以同样的
  退出码和提示拒绝空值，行为不变，属等价变异

---

## 5. 后续

- 状态栏可以加一个循环进度徽标（如 `🔁 2/5`），`/pdlc-retro` 可以统计循环跑的步数与阻塞原因——等有实际使用数据再做
- 多平台支持按 Agent Skills 开放标准重新梳理，另立 ADR
