#!/usr/bin/env bash
# Codex 适配器产物回归测试。
#
# 跑 adapters/build_codex.py 到临时目录，断言投影产物的结构：
#   - 33 个 prompt（36 skill − 3 denylist），denylist 确实缺席
#   - 无残留 @include 指令；无 Claude 术语（Layer 1/2 命令）泄漏
#   - frontmatter 只留 description（+ 可选 argument-hint），Claude 内部字段被剥离
#   - next_step 已物化进正文
#   - 文档模板引用改写到 ~/.codex/pdlc/templates/
#   - 方法论 + 模板一并落地
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

pass=0
fail=0

if ! command -v python3 >/dev/null 2>&1; then
    echo "⚠️  python3 未安装，跳过 Codex 适配器测试"
    exit 0
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

assert_contains() {
    local desc="$1" needle="$2" hay="$3"
    if grep -qF "$needle" <<< "$hay"; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc"; echo "    期望包含: $needle"; fail=$((fail + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (期望 $expected，实际 $actual)"; fail=$((fail + 1))
    fi
}

assert_exists() {
    local desc="$1" path="$2"
    if [[ -e "$path" ]]; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (缺失: $path)"; fail=$((fail + 1))
    fi
}

assert_absent() {
    local desc="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        echo "  ✓ $desc"; pass=$((pass + 1))
    else
        echo "  ✗ $desc (不该存在: $path)"; fail=$((fail + 1))
    fi
}

# ─── 构建 ───
echo "Test: 构建 Codex 适配器"
build_out="$(python3 adapters/build_codex.py "$OUT" 2>&1)"
assert_eq "构建退出码 0" "0" "$?"
assert_contains "报告 denylist 跳过 2 个" "denylist 跳过 2" "$build_out"

# ─── prompt 数量与 denylist ───
echo ""
echo "Test: prompt 数量与 denylist"
n=$(find "$OUT/prompts" -name 'pdlc-*.md' | wc -l | tr -d ' ')
assert_eq "投影 34 个 prompt（36 − 2 denylist）" "34" "$n"
assert_absent "pdlc-settings 未投影（真·Claude-only）"   "$OUT/prompts/pdlc-settings.md"
assert_absent "pdlc-loop-run 未投影（Task 版耦合子代理派发）" "$OUT/prompts/pdlc-loop-run.md"
assert_exists "pdlc-loop-next 已投影（逻辑平台中立）" "$OUT/prompts/pdlc-loop-next.md"
assert_exists "pdlc-feature 已投影"  "$OUT/prompts/pdlc-feature.md"
assert_exists "pdlc-prd 已投影"      "$OUT/prompts/pdlc-prd.md"
assert_exists "pdlc-review 已投影"   "$OUT/prompts/pdlc-review.md"

# ─── 自包含：无残留 @include，无 Claude 术语泄漏 ───
echo ""
echo "Test: 自包含 / 无 Claude 术语泄漏"
leftover_include="$(grep -rl '@include' "$OUT/prompts/" 2>/dev/null || true)"
assert_eq "无残留 @include 指令" "" "$leftover_include"
leaked_layer="$(grep -rl 'Layer 1/2 命令\|Layer 2 命令' "$OUT/prompts/" 2>/dev/null || true)"
assert_eq "无 'Layer 1/2 命令' 术语泄漏" "" "$leaked_layer"
# IRON LAW 确实被内联进产出（自包含证据）
assert_contains "pdlc-prd 内联了 IRON LAW" "IRON LAW" "$(cat "$OUT/prompts/pdlc-prd.md")"
# adapter:claude-only 哨兵块被剥掉：loop-next 的 claude 专属驱动 helper 不应残留
loopnext="$(cat "$OUT/prompts/pdlc-loop-next.md")"
assert_eq "loop-next 剥掉 claude -p 驱动 helper" "" "$(grep -c 'claude -p' <<< "$loopnext" | sed 's/0//')"
sentinel_left="$(grep -rl 'adapter:claude-only' "$OUT/prompts/" 2>/dev/null || true)"
assert_eq "无 adapter:claude-only 哨兵残留" "" "$sentinel_left"

# ─── frontmatter 剥离 ───
echo ""
echo "Test: frontmatter 剥离 Claude 内部字段"
fm="$(awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$OUT/prompts/pdlc-prd.md")"
assert_contains "保留 description" "description:" "$fm"
assert_eq "剥离 layer 字段"        "" "$(grep -c '^layer:' <<< "$fm" | tr -d ' ' | sed 's/0//')"
assert_eq "剥离 produces 字段"     "" "$(grep -c '^produces:' <<< "$fm" | tr -d ' ' | sed 's/0//')"
assert_eq "剥离 allowed-tools 字段" "" "$(grep -c '^allowed-tools:' <<< "$fm" | tr -d ' ' | sed 's/0//')"

# ─── next_step 物化 ───
echo ""
echo "Test: next_step 物化进正文"
assert_contains "pdlc-tdd 正文含下一步区块" "下一步（PDLC 链式推进）" "$(cat "$OUT/prompts/pdlc-tdd.md")"
assert_contains "pdlc-tdd 下一步指向 pdlc-implement" "/pdlc-implement" "$(cat "$OUT/prompts/pdlc-tdd.md")"

# ─── 模板引用改写 ───
echo ""
echo "Test: 文档模板引用改写"
# 这里的 ~ 是产物里的字面文本（转译改写目标），不是待展开路径
# shellcheck disable=SC2088
assert_contains "pdlc-prd 模板引用（templates/ 形态）改写正确" "~/.codex/pdlc/templates/prd-template.md" "$(cat "$OUT/prompts/pdlc-prd.md")"
# shellcheck disable=SC2088
assert_contains "pdlc-adopt 模板引用（.claude/templates/pdlc/ 形态）改写正确" "~/.codex/pdlc/templates/adopt-report-template.md" "$(cat "$OUT/prompts/pdlc-adopt.md")"
# 防回归：全局 templates/ 替换曾把 .claude/templates/pdlc/ 腐蚀成 .claude/~/.codex/...（Copilot 评审）
leak="$(grep -rl '\.claude/~\|templates/pdlc/templates' "$OUT/prompts/" 2>/dev/null || true)"
assert_eq "无 .claude/ 模板路径腐蚀泄漏" "" "$leak"

# ─── 附带产物 ───
echo ""
echo "Test: 方法论 + 模板落地"
assert_exists "方法论文档随产物落地" "$OUT/pdlc-methodology.md"
tpl_n=$(find "$OUT/templates" -name '*-template.*' | wc -l | tr -d ' ')
if [[ "$tpl_n" -ge 9 ]]; then
    echo "  ✓ 文档模板已拷贝（$tpl_n 个）"; pass=$((pass + 1))
else
    echo "  ✗ 文档模板数异常（$tpl_n）"; fail=$((fail + 1))
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
