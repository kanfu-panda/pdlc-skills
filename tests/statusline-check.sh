#!/usr/bin/env bash
# pdlc-statusline.sh 场景回归测试。
#
# 用 mock 状态文件喂给脚本、核对渲染输出，覆盖 ADR §9 的 7 个场景。
# 颜色统一关闭（NO_COLOR）以便断言纯文本。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

SL="$SCRIPT_DIR/bin/pdlc-statusline.sh"
export NO_COLOR=1

pass=0
fail=0

# jq 缺失则跳过（脚本本身设计为无 jq 静默降级，测试无意义）
if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq 未安装，跳过 statusline 场景测试"
    exit 0
fi

# 建一个临时项目根，喂给脚本的 stdin JSON 指向它
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/.pdlc-state"
STATE="$TMP/docs/.pdlc-state"

# 渲染：stdin 传 current_dir=临时项目根
render() {
    printf '{"workspace":{"current_dir":"%s"}}' "$TMP" | bash "$SL"
}

# 写一个状态文件
write_state() {
    # write_state <file> <json>
    printf '%s' "$2" > "$STATE/$1"
}

clear_state() { rm -f "$STATE"/*.json 2>/dev/null || true; }

assert_contains() {
    local desc="$1" needle="$2" hay="$3"
    if grep -qF "$needle" <<< "$hay"; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc"; echo "    期望包含: $needle"; echo "    实际输出: $hay"; fail=$((fail + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" hay="$3"
    if grep -qF "$needle" <<< "$hay"; then
        echo "  ✗ $desc"; echo "    不应包含: $needle"; echo "    实际输出: $hay"; fail=$((fail + 1))
    else
        echo "  ✓ $desc"; pass=$((pass + 1))
    fi
}

assert_empty() {
    local desc="$1" hay="$2"
    if [[ -z "${hay//[$'\n\t ']/}" ]]; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc（应为空，实际: $hay）"; fail=$((fail + 1))
    fi
}

now_iso() { date +%Y-%m-%dT%H:%M:%S; }

# ─── 场景 1：impl 阶段 · interactive（默认隐检查、隐 elapsed） ───
echo "场景 1：impl · interactive"
clear_state
write_state "F20260718-094301.json" "$(cat <<JSON
{"feature_id":"F20260718-094301","feature_name":"auth","current_stage":"impl",
 "run_mode":"interactive","next_step":"pdlc-review",
 "last_phase_result":{"checks":{"tests_pass":true,"lint_clean":true,"coverage_pass":true},"blocked_reason":null,"at":"$(now_iso)"}}
JSON
)"
out="$(render)"
assert_contains "显示功能名 auth" "auth" "$out"
assert_contains "进度条高亮 [实现]" "[实现]" "$out"
assert_contains "下一步 →评审" "→评审" "$out"
assert_contains "手动图标 👤" "👤" "$out"
assert_not_contains "interactive 默认不显示检查" "✓unit" "$out"

# ─── 场景 2：loop 收敛中 · autonomous（显检查、显 elapsed） ───
echo "场景 2：loop · autonomous"
clear_state
write_state "F20260718-101500.json" "$(cat <<JSON
{"feature_id":"F20260718-101500","feature_name":"payment","current_stage":"impl",
 "run_mode":"autonomous","next_step":"pdlc-review",
 "last_phase_result":{"checks":{"tests_pass":true,"lint_clean":true,"coverage_pass":true},"blocked_reason":null,"at":"$(now_iso)"}}
JSON
)"
out="$(render)"
assert_contains "autonomous 图标 🤖" "🤖" "$out"
assert_contains "显示 ✓unit" "✓unit" "$out"
assert_contains "显示 ✓lint" "✓lint" "$out"
assert_contains "显示停留时长 ⏱" "⏱" "$out"

# ─── 场景 3：blocked（全行最醒目 + reason + elapsed） ───
echo "场景 3：blocked"
clear_state
write_state "F20260718-110000.json" "$(cat <<JSON
{"feature_id":"F20260718-110000","feature_name":"search","current_stage":"impl",
 "run_mode":"autonomous","next_step":"pdlc-review",
 "last_phase_result":{"checks":{"tests_pass":false},"blocked_reason":"PRD 取舍需人工","at":"$(now_iso)"}}
JSON
)"
out="$(render)"
assert_contains "blocked 图标 ⛔" "⛔" "$out"
assert_contains "显示 blocked reason" "PRD 取舍需人工" "$out"
assert_contains "blocked 也带停留时长" "⏱" "$out"

# ─── 场景 4：review_done 终态 ───
echo "场景 4：review_done 终态"
clear_state
write_state "F20260718-120000.json" "$(cat <<JSON
{"feature_id":"F20260718-120000","feature_name":"profile","current_stage":"feature_done",
 "run_mode":"interactive","next_step":null,
 "last_phase_result":{"checks":{"tests_pass":true},"blocked_reason":null,"at":"$(now_iso)"}}
JSON
)"
out="$(render)"
assert_contains "终态显示 ✅ done" "✅ done" "$out"
assert_not_contains "终态不显示进度条 [实现]" "[实现]" "$out"

# ─── 场景 5：多 feature 并行（blocked 抢显示权） ───
echo "场景 5：多 feature · blocked 抢权"
clear_state
# 先写一个较旧的 impl，再写一个更新的 blocked
write_state "F20260718-130000.json" "$(cat <<JSON
{"feature_id":"F20260718-130000","feature_name":"aaa-impl","current_stage":"impl",
 "run_mode":"interactive","next_step":"pdlc-review",
 "last_phase_result":{"checks":{},"blocked_reason":null,"at":"$(now_iso)"}}
JSON
)"
sleep 1
write_state "F20260718-140000.json" "$(cat <<JSON
{"feature_id":"F20260718-140000","feature_name":"bbb-blocked","current_stage":"tdd",
 "run_mode":"autonomous","next_step":"pdlc-tdd",
 "last_phase_result":{"checks":{},"blocked_reason":"测试环境缺依赖","at":"$(now_iso)"}}
JSON
)"
out="$(render)"
assert_contains "blocked feature 抢到显示权" "bbb-blocked" "$out"
assert_contains "显示为 blocked 行" "⛔" "$out"

# ─── 场景 6：§5.4 边界负例（窗口外的旧 blocked 不抢权） ───
echo "场景 6：窗口外旧 blocked 不抢权"
clear_state
# window=5：写 1 个旧 blocked，再写 5 个更新的非 blocked，把 blocked 挤出窗口
write_state "F20260718-000001.json" "$(cat <<JSON
{"feature_id":"F20260718-000001","feature_name":"old-blocked","current_stage":"impl",
 "run_mode":"autonomous","next_step":"pdlc-review",
 "last_phase_result":{"checks":{},"blocked_reason":"很久以前卡住","at":"2026-07-18T00:00:01"}}
JSON
)"
sleep 1
for i in 1 2 3 4 5; do
    write_state "F20260718-20000$i.json" "$(cat <<JSON
{"feature_id":"F20260718-20000$i","feature_name":"fresh-$i","current_stage":"impl",
 "run_mode":"interactive","next_step":"pdlc-review",
 "last_phase_result":{"checks":{},"blocked_reason":null,"at":"$(now_iso)"}}
JSON
)"
done
out="$(render)"
assert_not_contains "窗口外旧 blocked 不抢权" "old-blocked" "$out"
assert_not_contains "不渲染为 blocked 行" "⛔" "$out"
assert_contains "显示的是窗口内的活跃 feature" "fresh-" "$out"

# ─── 场景 7：非 PDLC 项目 / 无状态文件（吐空、退出 0） ───
echo "场景 7：非 PDLC 项目"
NONPDLC="$(mktemp -d)"
out="$(printf '{"workspace":{"current_dir":"%s"}}' "$NONPDLC" | bash "$SL"; echo "rc=$?")"
rm -rf "$NONPDLC"
assert_contains "非 PDLC 项目退出码 0" "rc=0" "$out"
assert_empty "非 PDLC 项目吐空" "${out%rc=0}"

# 空 state 目录也吐空
clear_state
out="$(render; echo "rc=$?")"
assert_contains "空 state 目录退出码 0" "rc=0" "$out"
assert_empty "空 state 目录吐空" "${out%rc=0}"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
