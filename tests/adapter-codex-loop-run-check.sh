#!/usr/bin/env bash
# Codex loop-run 驱动的映射与护栏回归测试。
#
# 覆盖：
#   - loop-next 映射（--dry-run）：tdd/implement/review 前进；ship/deploy/null/终态 → done；
#     prd/design 或未知 → blocked；blocked_reason 非空 → blocked
#   - 用法守卫：缺 ID / 状态机不存在 / --max-steps 非正整数 → 退出 64
#   - 护栏（非 dry-run，用 codex stub 驱动 mock 状态）：advance→收敛 done(0)、
#     max-steps 上限(3)、fail-stop(2)、stuck-stop(5)、codex 非零退出(4)
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
        echo "  ✗ $desc (退出码 $rc 期望 ${want_rc}；输出未含「${needle}」)"; echo "    实际: $out"; fail=$((fail + 1))
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
assert_rc "--max-steps 非正整数 → 退出 64" 64 impl-next --project "$MK" --max-steps foo
assert_rc "--dry-run 缺 codex 也能跑决策 → 退出 0" 0 impl-next --project "$MK" --dry-run

echo ""
echo "Test: 非 dry-run 护栏（用 codex stub 驱动 mock 状态）"
# 假 codex：按 STUB_BEHAVIOR 改 STUB_STATE，覆盖 dry-run 覆盖不到的护栏分支
BIN="$(mktemp -d)"
cat > "$BIN/codex" <<'STUB'
#!/usr/bin/env bash
[ "${STUB_BEHAVIOR:-}" = error ] && exit 1
S="$STUB_STATE"; tmp="$S.tmp"
cur="$(jq -r '.current_stage' "$S")"
case "${STUB_BEHAVIOR:-}" in
  advance)  # tdd→impl（下一步 review）；impl→review（下一步 ship→done）
    if [ "$cur" = tdd ]; then
      jq '.current_stage="impl"|.next_step="pdlc-review"|.last_phase_result={ok:true,blocked_reason:null}' "$S" >"$tmp"
    else
      jq '.current_stage="review"|.next_step="pdlc-ship"|.last_phase_result={ok:true,blocked_reason:null}' "$S" >"$tmp"
    fi ;;
  failstop) jq '.last_phase_result={ok:false,blocked_reason:"stub failstop"}' "$S" >"$tmp" ;;   # 不推进 current_stage
  stuck)    jq '.last_phase_result={ok:true,blocked_reason:null}' "$S" >"$tmp" ;;               # ok=true 但不推进 → stuck
  *)        cp "$S" "$tmp" ;;
esac
mv "$tmp" "$S"; exit 0
STUB
chmod +x "$BIN/codex"

# run_guard <desc> <behavior> <want_rc> [额外 driver 参数...]
run_guard() {
    local desc="$1" behavior="$2" want_rc="$3"; shift 3
    cat > "$MK/docs/.pdlc-state/G.json" <<'J'
{ "feature_id":"G","current_stage":"tdd","next_step":"pdlc-implement","last_phase_result":{"ok":true,"blocked_reason":null} }
J
    local rc
    STUB_STATE="$MK/docs/.pdlc-state/G.json" STUB_BEHAVIOR="$behavior" PATH="$BIN:$PATH" \
        bash "$DRIVER" G --project "$MK" "$@" >/dev/null 2>&1
    rc=$?
    if [[ "$rc" == "$want_rc" ]]; then
        echo "  ✓ ${desc}（退出 ${rc}）"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (退出码 $rc 期望 $want_rc)"; fail=$((fail + 1))
    fi
}

run_guard "advance → tdd→impl→review→收敛 done" advance 0
run_guard "max-steps 上限停机（advance 但限 1 步）" advance 3 --max-steps 1
run_guard "fail-stop（stub 写 ok=false）" failstop 2
run_guard "stuck-stop（ok=true 但 current_stage 未推进）" stuck 5
run_guard "codex exec 非零退出" error 4
rm -rf "$BIN"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
