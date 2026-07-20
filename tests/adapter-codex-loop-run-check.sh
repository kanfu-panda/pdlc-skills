#!/usr/bin/env bash
# Codex loop-run 驱动的映射与护栏回归测试。
#
# 用 mock 状态机 + --dry-run 覆盖决策逻辑（不真跑 codex）：
#   - loop-next 映射：tdd/implement/review 前进；ship/deploy/null/终态 → done；
#     prd/design 或未知 → blocked；blocked_reason 非空 → blocked
#   - 用法守卫：缺 ID / 状态机不存在 → 退出 64
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1
DRIVER="$SCRIPT_DIR/adapters/codex-loop-run.sh"

pass=0
fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq 未安装，跳过 loop-run 驱动测试"
    exit 0
fi

MK="$(mktemp -d)"
trap 'rm -rf "$MK"' EXIT
mkdir -p "$MK/docs/.pdlc-state"

# 写一个 mock 状态机：write_state <id> <current_stage> <next_step> <blocked_reason|null>
write_state() {
    local id="$1" stage="$2" nxt="$3" reason="$4"
    local rj="null"; [[ "$reason" != "null" ]] && rj="\"$reason\""
    local nj="null"; [[ "$nxt" != "null" ]] && nj="\"$nxt\""
    cat > "$MK/docs/.pdlc-state/$id.json" <<JSON
{ "feature_id": "$id", "current_stage": "$stage", "next_step": $nj,
  "last_phase_result": { "ok": true, "blocked_reason": $rj } }
JSON
}

# 断言：跑驱动（dry-run），stdout 含 needle，退出码 == want_rc
assert_run() {
    local desc="$1" id="$2" want_rc="$3" needle="$4"
    local out rc
    out="$(bash "$DRIVER" "$id" --project "$MK" --dry-run 2>&1)"; rc=$?
    if [[ "$rc" == "$want_rc" ]] && grep -qF "$needle" <<< "$out"; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (退出码 $rc 期望 $want_rc；输出未含「$needle」)"; echo "    实际: $out"; fail=$((fail + 1))
    fi
}

assert_rc() {
    local desc="$1" want_rc="$2"; shift 2
    local rc; bash "$DRIVER" "$@" >/dev/null 2>&1; rc=$?
    if [[ "$rc" == "$want_rc" ]]; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (退出码 $rc 期望 $want_rc)"; fail=$((fail + 1))
    fi
}

echo "Test: loop-next 映射（前进段）"
write_state tdd-next      tdd    pdlc-tdd       null
assert_run "next=pdlc-tdd → 决策 pdlc-tdd"           tdd-next      0 "按 pdlc tdd"
write_state impl-next     tdd    pdlc-implement null
assert_run "next=pdlc-implement → 决策 pdlc-implement" impl-next   0 "按 pdlc implement"
write_state review-next   impl   pdlc-review    null
assert_run "next=pdlc-review → 决策 pdlc-review"      review-next   0 "按 pdlc review"

echo ""
echo "Test: 收敛完成 → done（发布留人）"
write_state ship-next     review pdlc-ship      null
assert_run "next=pdlc-ship → done"                   ship-next     0 "review_done"
write_state deploy-next   deploy pdlc-deploy    null
assert_run "next=pdlc-deploy → done"                 deploy-next   0 "review_done"
write_state null-next     review null           null
assert_run "next=null → done"                        null-next     0 "review_done"
write_state terminal      feature_done null      null
assert_run "current_stage=feature_done → done"       terminal      0 "review_done"

echo ""
echo "Test: 超出收敛段 / blocked → blocked（退出 2）"
write_state prd-next      requirements pdlc-prd  null
assert_run "next=pdlc-prd（tdd 之前）→ blocked"       prd-next      2 "blocked"
write_state blocked-one   impl   pdlc-implement "PRD 取舍需人工"
assert_run "blocked_reason 非空 → blocked（带原因）"  blocked-one   2 "PRD 取舍需人工"

echo ""
echo "Test: 用法守卫"
assert_rc "缺功能ID → 退出 64" 64 --project "$MK"
assert_rc "状态机不存在 → 退出 64" 64 NOPE --project "$MK"
assert_rc "--dry-run 缺 codex 也能跑决策 → 退出 0" 0 impl-next --project "$MK" --dry-run

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
