#!/usr/bin/env bash
# Codex 版 PDLC 收敛循环驱动（loop-run 的「外部 Runbook」形态）。
#
# 背景：pdlc-loop-run 的默认「Task 版」用 Claude Code 的 Task 子代理派发，Codex 无等价物、
# 未投影（见 build_codex.py DENYLIST）。本脚本是它的**外部进程隔离版**：一个 bash 循环，
# 每轮读状态机 → 用 loop-next 映射判下一跳 → 调 `codex exec "按 pdlc <阶段> <id> --autonomous"`
# → 读回状态机判 ok/推进/block，带 max-steps + fail-stop + stuck-stop 护栏。
#
# 状态完整性准入闸已在真机通过（gpt-5.6-sol 真跑 test-commands.yml、诚实写 checks、
# fail-stop 正确、发 <<<PDLC blocked>>> 哨兵）——详见 docs/decisions/0004-codex-loop-run.md。
#
# 只覆盖机械收敛段 tdd → implement → review，到 review_done 即成功停机，**绝不自动 ship/deploy**。
#
# 用法：
#   adapters/codex-loop-run.sh <功能ID> [--project DIR] [--max-steps N] [--dry-run]
# 退出码：0=收敛到 review_done  2=blocked  3=达上限  4=codex 出错  5=stuck  64=用法错
set -uo pipefail

FID=""
PROJECT="$PWD"
MAX_STEPS=4
DRY_RUN=0

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|-C) PROJECT="${2:?--project 需要目录}"; shift 2 ;;
    --max-steps)  MAX_STEPS="${2:?--max-steps 需要数字}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage 0 ;;
    -*)           echo "未知参数: $1" >&2; usage 64 ;;
    *)            if [[ -z "$FID" ]]; then FID="$1"; else echo "多余参数: $1" >&2; usage 64; fi; shift ;;
  esac
done

[[ -n "$FID" ]] || { echo "错误：缺功能ID" >&2; usage 64; }
command -v jq >/dev/null 2>&1 || { echo "错误：需要 jq" >&2; exit 64; }
STATE="$PROJECT/docs/.pdlc-state/$FID.json"
[[ -f "$STATE" ]] || { echo "错误：状态机不存在 $STATE" >&2; exit 64; }
if [[ "$DRY_RUN" -eq 0 ]]; then
  command -v codex >/dev/null 2>&1 || { echo "错误：需要 codex CLI（或用 --dry-run 看决策）" >&2; exit 64; }
fi

# loop-next 映射（复刻 pdlc-loop-next：以 next_step 为主键，blocked_reason/终态优先）。
# 输出白名单单 token：pdlc-tdd | pdlc-implement | pdlc-review | done | blocked
compute_next() {
  jq -r '
    if (.last_phase_result.blocked_reason // null) != null then "blocked"
    elif ((.current_stage // "") | endswith("_done")) then "done"
    else (.next_step // "null") as $ns
      | if ($ns == "pdlc-tdd" or $ns == "pdlc-implement" or $ns == "pdlc-review") then $ns
        elif ($ns == "pdlc-ship" or $ns == "pdlc-deploy" or $ns == "null") then "done"
        else "blocked" end
    end
  ' "$STATE"
}

echo "🔁 Codex loop-run：$FID  项目=$PROJECT  上限=$MAX_STEPS 步$([[ $DRY_RUN -eq 1 ]] && echo '  [dry-run]')"

step=0
while :; do
  next="$(compute_next)"
  case "$next" in
    done)
      echo "✅ 收敛到 review_done（或无后续）。发布是人工闸门 —— 交人工决定 /pdlc-ship。"
      exit 0 ;;
    blocked)
      echo "⛔ blocked：$(jq -r '.last_phase_result.blocked_reason // "（next_step 超出收敛段，需人工）"' "$STATE")"
      exit 2 ;;
    pdlc-tdd|pdlc-implement|pdlc-review) ;;
    *)
      echo "❌ 非法决策 token：$next" >&2; exit 5 ;;
  esac

  step=$((step + 1))
  if [[ "$step" -gt "$MAX_STEPS" ]]; then
    echo "🛑 达迭代上限（${MAX_STEPS}）——停机防空转烧 token。当前 next=$next"
    exit 3
  fi

  short="${next#pdlc-}"
  stage_before="$(jq -r '.current_stage // ""' "$STATE")"
  echo "▶ step ${step}：pdlc-${short}（当前 stage=${stage_before}）"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "   [dry-run] 将执行：codex exec -C \"$PROJECT\" -s workspace-write \"按 pdlc $short $FID --autonomous\""
    echo "   [dry-run] 停在首个决策（不真跑 codex）。"
    exit 0
  fi

  if ! codex exec -C "$PROJECT" -s workspace-write --skip-git-repo-check \
        "按 pdlc $short $FID --autonomous"; then
    echo "❌ codex exec 非零退出（stage=pdlc-${short}）——停机。" >&2
    exit 4
  fi

  # 读回状态机判定（状态机是唯一真源，不信 codex stdout）
  ok="$(jq -r '.last_phase_result.ok // "null"' "$STATE")"
  stage_after="$(jq -r '.current_stage // ""' "$STATE")"

  if [[ "$ok" != "true" ]]; then
    echo "⛔ fail-stop：last_phase_result.ok=$ok  reason=$(jq -r '.last_phase_result.blocked_reason // "?"' "$STATE")"
    exit 2
  fi
  if [[ "$stage_after" == "$stage_before" ]]; then
    echo "🛑 stuck-stop：current_stage 未推进（仍 ${stage_after}，违反 IRON LAW 第 6 条）——停机报错。" >&2
    exit 5
  fi
  echo "   ✓ 推进 $stage_before → ${stage_after}（ok=true）"
done
