#!/usr/bin/env bash
# Codex 适配器产物回归测试。
#
# 跑 adapters/build_codex.py 到临时目录，断言投影出的 Codex skills 结构：
#   - 34 个 skill 目录（36 skill − 2 denylist），denylist 确实缺席，loop-next 已投影
#   - 每个 skill 是 skills/<name>/SKILL.md，frontmatter 为 Codex skill 格式 name + description
#   - 无残留 @include；无 Claude 术语（Layer 1/2 命令）泄漏；adapter:claude-only 哨兵块被剥掉
#   - Claude 内部 frontmatter 字段（layer/produces/allowed-tools）被剥离
#   - next_step 已物化进正文（自然语言措辞，非斜杠命令）
#   - 文档模板引用改写到 ~/.codex/pdlc/templates/，无路径腐蚀
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

# skill SKILL.md 路径
sk() { echo "$OUT/skills/$1/SKILL.md"; }

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

# ─── skill 数量与 denylist ───
echo ""
echo "Test: skill 数量与 denylist"
n=$(find "$OUT/skills" -maxdepth 1 -type d -name 'pdlc-*' | wc -l | tr -d ' ')
assert_eq "投影 34 个 skill（36 − 2 denylist）" "34" "$n"
assert_absent "pdlc-settings 未投影（真·Claude-only）"       "$OUT/skills/pdlc-settings"
assert_absent "pdlc-loop-run 未投影（Task 版耦合子代理派发）" "$OUT/skills/pdlc-loop-run"
assert_exists "pdlc-loop-next 已投影（逻辑平台中立）"        "$(sk pdlc-loop-next)"
assert_exists "pdlc-feature 已投影"  "$(sk pdlc-feature)"
assert_exists "pdlc-prd 已投影"      "$(sk pdlc-prd)"
assert_exists "pdlc-review 已投影"   "$(sk pdlc-review)"

# ─── 自包含：无残留 @include，无 Claude 术语泄漏 ───
echo ""
echo "Test: 自包含 / 无 Claude 术语泄漏"
leftover_include="$(grep -rl '@include' "$OUT/skills/" 2>/dev/null || true)"
assert_eq "无残留 @include 指令" "" "$leftover_include"
leaked_layer="$(grep -rl 'Layer 1/2 命令\|Layer 2 命令' "$OUT/skills/" 2>/dev/null || true)"
assert_eq "无 'Layer 1/2 命令' 术语泄漏" "" "$leaked_layer"
assert_contains "pdlc-prd 内联了 IRON LAW" "IRON LAW" "$(cat "$(sk pdlc-prd)")"
# adapter:claude-only 哨兵块被剥掉：loop-next 的 claude 专属驱动 helper 不应残留
loopnext="$(cat "$(sk pdlc-loop-next)")"
assert_eq "loop-next 剥掉 claude -p 驱动 helper" "" "$(grep -c 'claude -p' <<< "$loopnext" | sed 's/0//')"
sentinel_left="$(grep -rl 'adapter:claude-only' "$OUT/skills/" 2>/dev/null || true)"
assert_eq "无 adapter:claude-only 哨兵残留" "" "$sentinel_left"

# ─── frontmatter：Codex skill 格式 name + description，剥离 Claude 内部字段 ───
echo ""
echo "Test: skill frontmatter（name + description，剥离内部字段）"
fm="$(awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$(sk pdlc-prd)")"
assert_contains "保留 name 字段（skill 格式）" "name: pdlc-prd" "$fm"
assert_contains "保留 description 字段" "description:" "$fm"
assert_contains "description 含 pdlc 触发提示" "用 pdlc" "$fm"
assert_eq "剥离 layer 字段"        "" "$(grep -c '^layer:' <<< "$fm" | tr -d ' ' | sed 's/0//')"
assert_eq "剥离 produces 字段"     "" "$(grep -c '^produces:' <<< "$fm" | tr -d ' ' | sed 's/0//')"
assert_eq "剥离 allowed-tools 字段" "" "$(grep -c '^allowed-tools:' <<< "$fm" | tr -d ' ' | sed 's/0//')"
assert_eq "剥离 argument-hint 字段" "" "$(grep -c '^argument-hint:' <<< "$fm" | tr -d ' ' | sed 's/0//')"

# ─── next_step 物化（自然语言措辞，非斜杠命令）───
echo ""
echo "Test: next_step 物化进正文"
tdd="$(cat "$(sk pdlc-tdd)")"
assert_contains "pdlc-tdd 正文含下一步区块" "下一步（PDLC 链式推进）" "$tdd"
assert_contains "pdlc-tdd 下一步指向 pdlc-implement 技能" "pdlc-implement" "$tdd"
assert_contains "下一步措辞用自然语言（非斜杠命令）" "按 pdlc implement" "$tdd"

# ─── 模板引用改写 ───
echo ""
echo "Test: 文档模板引用改写"
# 这里的 ~ 是产物里的字面文本（转译改写目标），不是待展开路径
# shellcheck disable=SC2088
assert_contains "pdlc-prd 模板引用（templates/ 形态）改写正确" "~/.codex/pdlc/templates/prd-template.md" "$(cat "$(sk pdlc-prd)")"
# shellcheck disable=SC2088
assert_contains "pdlc-adopt 模板引用（.claude/templates/pdlc/ 形态）改写正确" "~/.codex/pdlc/templates/adopt-report-template.md" "$(cat "$(sk pdlc-adopt)")"
# 防回归：全局 templates/ 替换曾把 .claude/templates/pdlc/ 腐蚀成 .claude/~/.codex/...（Copilot 评审）
leak="$(grep -rl '\.claude/~\|templates/pdlc/templates' "$OUT/skills/" 2>/dev/null || true)"
assert_eq "无 .claude/ 模板路径腐蚀泄漏" "" "$leak"

# ─── 升级路径：输出目录含 v1.5.0 旧 prompts/ 不应阻断重建（Copilot 评审）───
echo ""
echo "Test: 从 v1.5.0（旧 prompts/）升级重建"
UPG="$(mktemp -d)"
mkdir -p "$UPG/prompts"
printf 'stale\n' > "$UPG/prompts/pdlc-prd.md"   # 模拟 v1.5.0 遗留产物
python3 adapters/build_codex.py "$UPG" >/dev/null 2>&1; upg_rc=$?
assert_eq "含旧 prompts/ 的目录重建成功（不被守卫误拒）" "0" "$upg_rc"
assert_exists "重建后产出 skills/ 布局" "$UPG/skills/pdlc-prd/SKILL.md"
assert_absent "旧 prompts/ 被清掉" "$UPG/prompts"
rm -rf "$UPG"

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
