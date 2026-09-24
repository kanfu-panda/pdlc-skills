#!/usr/bin/env bash
# Codex 版 PDLC 收敛循环驱动（loop-run 的「外部 Runbook」形态）。
#
# 背景：pdlc-loop-run 的默认「Task 版」用 Claude Code 的 Task 子代理派发，Codex 无等价物、
# 未投影（见 build_agent_skills.py 的 DENYLIST）。本脚本是它的**外部进程隔离版**：每轮读状态机 →
# 用 loop-next 映射判下一跳 → 调 `codex exec "按 pdlc <阶段> <id> --autonomous"` → 读回状态机判
# ok / 推进 / block，带 max-steps + fail-stop + stuck-stop 护栏。
#
# 状态完整性准入闸已在真机通过（gpt-5.6-sol 真跑 test-commands.yml、诚实写 checks、
# fail-stop 正确、发 <<<PDLC blocked>>> 哨兵）——详见 docs/decisions/0004-codex-loop-run.md。
#
# 只覆盖机械收敛段 tdd → implement → review，到「评审通过、等发布」（next_step=pdlc-ship）即成功停机，**绝不自动 ship/deploy**。
#
# 用法：
#   adapters/codex-loop-run.sh <功能ID>... [--project DIR] [--max-steps N] [--parallel N] [--dry-run]
# 退出码：0=全部收敛（评审通过、等发布）  2=blocked  3=达上限  4=codex 出错  5=stuck  64=用法错
#
# 循环本身由平台中立的 bin/pdlc-loop.sh 实现（多个功能、并行、depends_on、运行记录都在那里）；
# 本脚本只是固定 --platform codex 的入口，保留原有的调用方式。
exec bash "$(cd "$(dirname "$0")/.." && pwd)/bin/pdlc-loop.sh" --platform codex "$@"
